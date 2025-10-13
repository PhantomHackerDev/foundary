// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title Staking
 * @dev A comprehensive staking contract with reward distribution
 */
contract Staking is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // Staking token (the token users stake)
    IERC20 public immutable stakingToken;

    // Reward token (the token users earn)
    IERC20 public immutable rewardToken;

    // Reward rate per second (rewards per token staked)
    uint256 public rewardRate;

    // Last time rewards were updated
    uint256 public lastUpdateTime;

    // Reward per token stored
    uint256 public rewardPerTokenStored;

    // Total staked tokens
    uint256 public totalStaked;

    // Minimum staking period (in seconds)
    uint256 public minimumStakingPeriod;

    // Early withdrawal penalty percentage (100 = 1%)
    uint256 public earlyWithdrawalPenalty;

    // Staker information
    struct StakerInfo {
        uint256 stakedAmount;           // Amount of tokens staked
        uint256 rewardPerTokenPaid;     // Reward per token paid
        uint256 rewards;                // Pending rewards
        uint256 lastStakedTime;         // Last time user staked
    }

    // Mapping from staker address to staker info
    mapping(address => StakerInfo) public stakers;

    // Events
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount, uint256 penalty);
    event RewardClaimed(address indexed user, uint256 reward);
    event RewardRateUpdated(uint256 newRate);
    event MinimumStakingPeriodUpdated(uint256 newPeriod);
    event EarlyWithdrawalPenaltyUpdated(uint256 newPenalty);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    /**
     * @dev Constructor
     * @param _stakingToken Address of the staking token
     * @param _rewardToken Address of the reward token
     * @param _rewardRate Initial reward rate per second
     * @param _minimumStakingPeriod Minimum staking period in seconds (e.g., 7 days = 604800)
     * @param _earlyWithdrawalPenalty Early withdrawal penalty (e.g., 1000 = 10%)
     */
    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardRate,
        uint256 _minimumStakingPeriod,
        uint256 _earlyWithdrawalPenalty
    ) Ownable(msg.sender) {
        require(_stakingToken != address(0), "Invalid staking token");
        require(_rewardToken != address(0), "Invalid reward token");
        require(_earlyWithdrawalPenalty <= 5000, "Penalty too high"); // Max 50%

        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardRate = _rewardRate;
        minimumStakingPeriod = _minimumStakingPeriod;
        earlyWithdrawalPenalty = _earlyWithdrawalPenalty;
        lastUpdateTime = block.timestamp;
    }

    /**
     * @dev Update reward variables
     */
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;

        if (account != address(0)) {
            stakers[account].rewards = earned(account);
            stakers[account].rewardPerTokenPaid = rewardPerTokenStored;
        }
        _;
    }

    /**
     * @dev Calculate reward per token
     * @return Reward per token
     */
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }

        return rewardPerTokenStored +
            (((block.timestamp - lastUpdateTime) * rewardRate * 1e18) / totalStaked);
    }

    /**
     * @dev Calculate earned rewards for an account
     * @param account Address to check
     * @return Amount of rewards earned
     */
    function earned(address account) public view returns (uint256) {
        StakerInfo memory staker = stakers[account];
        return ((staker.stakedAmount *
            (rewardPerToken() - staker.rewardPerTokenPaid)) / 1e18) + staker.rewards;
    }

    /**
     * @dev Stake tokens
     * @param amount Amount to stake
     */
    function stake(uint256 amount) external nonReentrant whenNotPaused updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");

        StakerInfo storage staker = stakers[msg.sender];

        // Update staker info
        staker.stakedAmount += amount;
        staker.lastStakedTime = block.timestamp;
        totalStaked += amount;

        // Transfer tokens from user to contract
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    /**
     * @dev Withdraw staked tokens
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");

        StakerInfo storage staker = stakers[msg.sender];
        require(staker.stakedAmount >= amount, "Insufficient staked amount");

        uint256 penalty = 0;

        // Check if early withdrawal penalty applies
        if (block.timestamp < staker.lastStakedTime + minimumStakingPeriod) {
            penalty = (amount * earlyWithdrawalPenalty) / 10000;
        }

        // Update state
        staker.stakedAmount -= amount;
        totalStaked -= amount;

        // Transfer tokens
        uint256 amountToTransfer = amount - penalty;
        stakingToken.safeTransfer(msg.sender, amountToTransfer);

        // Transfer penalty to owner if applicable
        if (penalty > 0) {
            stakingToken.safeTransfer(owner(), penalty);
        }

        emit Withdrawn(msg.sender, amount, penalty);
    }

    /**
     * @dev Claim rewards
     */
    function claimReward() public nonReentrant updateReward(msg.sender) {
        StakerInfo storage staker = stakers[msg.sender];
        uint256 reward = staker.rewards;

        require(reward > 0, "No rewards to claim");

        staker.rewards = 0;
        rewardToken.safeTransfer(msg.sender, reward);

        emit RewardClaimed(msg.sender, reward);
    }

    /**
     * @dev Withdraw all staked tokens and claim all rewards
     */
    function exit() external {
        StakerInfo memory staker = stakers[msg.sender];
        if (staker.stakedAmount > 0) {
            withdraw(staker.stakedAmount);
        }
        if (staker.rewards > 0) {
            claimReward();
        }
    }

    /**
     * @dev Emergency withdraw without caring about rewards (no penalty)
     */
    function emergencyWithdraw() external nonReentrant {
        StakerInfo storage staker = stakers[msg.sender];
        uint256 amount = staker.stakedAmount;

        require(amount > 0, "Nothing to withdraw");

        // Reset staker info
        staker.stakedAmount = 0;
        staker.rewards = 0;
        staker.rewardPerTokenPaid = 0;
        totalStaked -= amount;

        stakingToken.safeTransfer(msg.sender, amount);

        emit EmergencyWithdraw(msg.sender, amount);
    }

    // ============ Admin Functions ============

    /**
     * @dev Update reward rate
     * @param _rewardRate New reward rate per second
     */
    function setRewardRate(uint256 _rewardRate) external onlyOwner updateReward(address(0)) {
        rewardRate = _rewardRate;
        emit RewardRateUpdated(_rewardRate);
    }

    /**
     * @dev Update minimum staking period
     * @param _minimumStakingPeriod New minimum staking period in seconds
     */
    function setMinimumStakingPeriod(uint256 _minimumStakingPeriod) external onlyOwner {
        minimumStakingPeriod = _minimumStakingPeriod;
        emit MinimumStakingPeriodUpdated(_minimumStakingPeriod);
    }

    /**
     * @dev Update early withdrawal penalty
     * @param _earlyWithdrawalPenalty New penalty percentage (100 = 1%)
     */
    function setEarlyWithdrawalPenalty(uint256 _earlyWithdrawalPenalty) external onlyOwner {
        require(_earlyWithdrawalPenalty <= 5000, "Penalty too high"); // Max 50%
        earlyWithdrawalPenalty = _earlyWithdrawalPenalty;
        emit EarlyWithdrawalPenaltyUpdated(_earlyWithdrawalPenalty);
    }

    /**
     * @dev Deposit reward tokens for distribution
     * @param amount Amount of reward tokens to deposit
     */
    function depositRewards(uint256 amount) external onlyOwner {
        require(amount > 0, "Cannot deposit 0");
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev Withdraw excess reward tokens (emergency only)
     * @param amount Amount to withdraw
     */
    function withdrawRewards(uint256 amount) external onlyOwner {
        rewardToken.safeTransfer(msg.sender, amount);
    }

    /**
     * @dev Pause staking
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause staking
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ View Functions ============

    /**
     * @dev Get staker information
     * @param account Address to query
     * @return stakedAmount Amount staked
     * @return earnedRewards Earned rewards
     * @return lastStakedTime Last stake timestamp
     */
    function getStakerInfo(address account) external view returns (
        uint256 stakedAmount,
        uint256 earnedRewards,
        uint256 lastStakedTime
    ) {
        StakerInfo memory staker = stakers[account];
        return (
            staker.stakedAmount,
            earned(account),
            staker.lastStakedTime
        );
    }

    /**
     * @dev Calculate potential penalty for early withdrawal
     * @param account Address to check
     * @return penalty Penalty amount in tokens
     */
    function calculateWithdrawalPenalty(address account) external view returns (uint256 penalty) {
        StakerInfo memory staker = stakers[account];

        if (block.timestamp < staker.lastStakedTime + minimumStakingPeriod) {
            penalty = (staker.stakedAmount * earlyWithdrawalPenalty) / 10000;
        } else {
            penalty = 0;
        }
    }

    /**
     * @dev Get APR (Annual Percentage Rate)
     * @return APR in basis points (10000 = 100%)
     */
    function getAPR() external view returns (uint256) {
        if (totalStaked == 0) {
            return 0;
        }

        // APR = (rewardRate * seconds in year * 100) / totalStaked
        uint256 annualReward = rewardRate * 365 days;
        return (annualReward * 10000) / totalStaked;
    }
}
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

    // Token launch status
    bool public tokenLaunched;
    uint256 public launchDate;

    // Individual stake information
    struct StakeInfo {
        uint256 amount;                 // Amount of tokens staked
        uint256 startTime;              // When this stake was created
        uint256 rewardPerTokenPaid;     // Reward per token paid for this stake
        uint256 rewards;                // Pending rewards for this stake
        bool withdrawn;                 // Whether this stake has been withdrawn
    }

    // Mapping from staker address to array of stakes
    mapping(address => StakeInfo[]) public userStakes;

    // Mapping from staker address to total staked amount
    mapping(address => uint256) public userTotalStaked;

    // Events
    event StakeCreated(address indexed user, uint256 stakeIndex, uint256 amount);
    event StakeWithdrawn(address indexed user, uint256 stakeIndex, uint256 amount, uint256 penalty);
    event StakeRewardClaimed(address indexed user, uint256 stakeIndex, uint256 reward);
    event AllRewardsClaimed(address indexed user, uint256 totalReward);
    event RewardRateUpdated(uint256 newRate);
    event MinimumStakingPeriodUpdated(uint256 newPeriod);
    event EarlyWithdrawalPenaltyUpdated(uint256 newPenalty);
    event EmergencyWithdrawStake(address indexed user, uint256 stakeIndex, uint256 amount);
    event TokenLaunched(uint256 launchDate);

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
        tokenLaunched = false;
        launchDate = 0;
    }

    /**
     * @dev Update global reward variables
     */
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
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

    /**
     * @dev Set launch date for token
     * @param _launchDate Launch date timestamp
     */
    function setLaunchDate(uint256 _launchDate) external onlyOwner {
        require(!tokenLaunched, "Token already launched");
        require(_launchDate > block.timestamp, "Launch date must be in future");
        launchDate = _launchDate;
    }

    /**
     * @dev Launch token and enable staking
     */
    function launchToken() external onlyOwner {
        require(!tokenLaunched, "Token already launched");
        tokenLaunched = true;
        if (launchDate == 0) {
            launchDate = block.timestamp;
        }
        emit TokenLaunched(launchDate);
    }

    // ============ Multiple Stakes Functions ============

    /**
     * @dev Create a new stake
     * @param amount Amount to stake
     */
    function createStake(uint256 amount) external nonReentrant whenNotPaused updateReward(msg.sender) {
        require(tokenLaunched, "Staking not available: Token not launched yet");
        require(amount > 0, "Cannot stake 0");

        // Update total staked
        userTotalStaked[msg.sender] += amount;
        totalStaked += amount;

        // Create new stake
        userStakes[msg.sender].push(StakeInfo({
            amount: amount,
            startTime: block.timestamp,
            rewardPerTokenPaid: rewardPerTokenStored,
            rewards: 0,
            withdrawn: false
        }));

        uint256 stakeIndex = userStakes[msg.sender].length - 1;

        // Transfer tokens from user to contract
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit StakeCreated(msg.sender, stakeIndex, amount);
    }

    /**
     * @dev Withdraw a specific stake
     * @param stakeIndex Index of the stake to withdraw
     */
    function withdrawStake(uint256 stakeIndex) public nonReentrant updateReward(msg.sender) {
        require(stakeIndex < userStakes[msg.sender].length, "Invalid stake index");

        StakeInfo storage stakeInfo = userStakes[msg.sender][stakeIndex];
        require(!stakeInfo.withdrawn, "Stake already withdrawn");
        require(stakeInfo.amount > 0, "Nothing to withdraw");

        uint256 amount = stakeInfo.amount;
        uint256 penalty = 0;

        // Check if early withdrawal penalty applies
        if (block.timestamp < stakeInfo.startTime + minimumStakingPeriod) {
            penalty = (amount * earlyWithdrawalPenalty) / 10000;
        }

        // Calculate and store rewards before withdrawal
        uint256 stakeReward = calculateStakeReward(msg.sender, stakeIndex);
        stakeInfo.rewards = stakeReward;

        // Mark as withdrawn
        stakeInfo.withdrawn = true;

        // Update totals
        userTotalStaked[msg.sender] -= amount;
        totalStaked -= amount;

        // Transfer tokens
        uint256 amountToTransfer = amount - penalty;
        stakingToken.safeTransfer(msg.sender, amountToTransfer);

        // Transfer penalty to owner if applicable
        if (penalty > 0) {
            stakingToken.safeTransfer(owner(), penalty);
        }

        emit StakeWithdrawn(msg.sender, stakeIndex, amount, penalty);
    }

    /**
     * @dev Claim rewards from a specific stake
     * @param stakeIndex Index of the stake
     */
    function claimStakeReward(uint256 stakeIndex) public nonReentrant updateReward(msg.sender) {
        require(stakeIndex < userStakes[msg.sender].length, "Invalid stake index");

        StakeInfo storage stakeInfo = userStakes[msg.sender][stakeIndex];
        require(!stakeInfo.withdrawn, "Stake already withdrawn");

        uint256 reward = calculateStakeReward(msg.sender, stakeIndex);
        require(reward > 0, "No rewards to claim");

        // Update stake reward tracking
        stakeInfo.rewardPerTokenPaid = rewardPerTokenStored;
        stakeInfo.rewards = 0;

        // Transfer reward
        rewardToken.safeTransfer(msg.sender, reward);

        emit StakeRewardClaimed(msg.sender, stakeIndex, reward);
    }

    /**
     * @dev Claim rewards from all active stakes
     */
    function claimAllStakeRewards() external nonReentrant updateReward(msg.sender) {
        uint256 totalReward = 0;
        StakeInfo[] storage stakes = userStakes[msg.sender];

        for (uint256 i = 0; i < stakes.length; i++) {
            if (!stakes[i].withdrawn) {
                uint256 stakeReward = calculateStakeReward(msg.sender, i);
                stakes[i].rewardPerTokenPaid = rewardPerTokenStored;
                stakes[i].rewards = 0;
                totalReward += stakeReward;
            }
        }

        require(totalReward > 0, "No rewards to claim");
        rewardToken.safeTransfer(msg.sender, totalReward);

        emit AllRewardsClaimed(msg.sender, totalReward);
    }

    /**
     * @dev Withdraw all active stakes
     */
    function withdrawAllStakes() external {
        StakeInfo[] storage stakes = userStakes[msg.sender];

        for (uint256 i = 0; i < stakes.length; i++) {
            if (!stakes[i].withdrawn && stakes[i].amount > 0) {
                withdrawStake(i);
            }
        }
    }

    /**
     * @dev Emergency withdraw a specific stake without caring about rewards (no penalty)
     * @param stakeIndex Index of the stake to emergency withdraw
     */
    function emergencyWithdrawStake(uint256 stakeIndex) external nonReentrant {
        require(stakeIndex < userStakes[msg.sender].length, "Invalid stake index");

        StakeInfo storage stakeInfo = userStakes[msg.sender][stakeIndex];
        require(!stakeInfo.withdrawn, "Stake already withdrawn");
        require(stakeInfo.amount > 0, "Nothing to withdraw");

        uint256 amount = stakeInfo.amount;

        // Mark as withdrawn and reset
        stakeInfo.withdrawn = true;
        stakeInfo.rewards = 0;

        // Update totals
        userTotalStaked[msg.sender] -= amount;
        totalStaked -= amount;

        // Transfer without penalty
        stakingToken.safeTransfer(msg.sender, amount);

        emit EmergencyWithdrawStake(msg.sender, stakeIndex, amount);
    }

    /**
     * @dev Emergency withdraw all active stakes without caring about rewards (no penalty)
     */
    function emergencyWithdrawAll() external nonReentrant {
        StakeInfo[] storage stakes = userStakes[msg.sender];
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < stakes.length; i++) {
            if (!stakes[i].withdrawn && stakes[i].amount > 0) {
                totalAmount += stakes[i].amount;
                stakes[i].withdrawn = true;
                stakes[i].rewards = 0;
                emit EmergencyWithdrawStake(msg.sender, i, stakes[i].amount);
            }
        }

        require(totalAmount > 0, "Nothing to withdraw");

        // Update totals
        userTotalStaked[msg.sender] -= totalAmount;
        totalStaked -= totalAmount;

        // Transfer without penalty
        stakingToken.safeTransfer(msg.sender, totalAmount);
    }

    /**
     * @dev Calculate reward for a specific stake
     * @param account User address
     * @param stakeIndex Index of the stake
     * @return Reward amount
     */
    function calculateStakeReward(address account, uint256 stakeIndex) public view returns (uint256) {
        require(stakeIndex < userStakes[account].length, "Invalid stake index");

        StakeInfo memory stakeInfo = userStakes[account][stakeIndex];

        if (stakeInfo.withdrawn) {
            return stakeInfo.rewards;
        }

        uint256 currentRewardPerToken = rewardPerToken();
        return ((stakeInfo.amount * (currentRewardPerToken - stakeInfo.rewardPerTokenPaid)) / 1e18) + stakeInfo.rewards;
    }

    /**
     * @dev Get all stakes for a user
     * @param account User address
     * @return Array of StakeInfo
     */
    function getUserStakes(address account) external view returns (StakeInfo[] memory) {
        return userStakes[account];
    }

    /**
     * @dev Get number of stakes for a user
     * @param account User address
     * @return Number of stakes
     */
    function getUserStakeCount(address account) external view returns (uint256) {
        return userStakes[account].length;
    }

    /**
     * @dev Get active stakes count for a user
     * @param account User address
     * @return Number of active stakes
     */
    function getActiveStakeCount(address account) external view returns (uint256) {
        uint256 activeCount = 0;
        StakeInfo[] memory stakes = userStakes[account];

        for (uint256 i = 0; i < stakes.length; i++) {
            if (!stakes[i].withdrawn) {
                activeCount++;
            }
        }

        return activeCount;
    }

    /**
     * @dev Get total rewards from all active stakes
     * @param account User address
     * @return Total rewards
     */
    function getTotalStakeRewards(address account) external view returns (uint256) {
        uint256 totalRewards = 0;
        StakeInfo[] memory stakes = userStakes[account];

        for (uint256 i = 0; i < stakes.length; i++) {
            if (!stakes[i].withdrawn) {
                totalRewards += calculateStakeReward(account, i);
            }
        }

        return totalRewards;
    }

    // ============ View Functions ============

    /**
     * @dev Calculate potential penalty for early withdrawal of a specific stake
     * @param account Address to check
     * @param stakeIndex Index of the stake
     * @return penalty Penalty amount in tokens
     */
    function calculateStakePenalty(address account, uint256 stakeIndex) external view returns (uint256 penalty) {
        require(stakeIndex < userStakes[account].length, "Invalid stake index");

        StakeInfo memory stakeInfo = userStakes[account][stakeIndex];

        if (stakeInfo.withdrawn) {
            return 0;
        }

        if (block.timestamp < stakeInfo.startTime + minimumStakingPeriod) {
            penalty = (stakeInfo.amount * earlyWithdrawalPenalty) / 10000;
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

    /**
     * @dev Get comprehensive user summary for dashboard
     * @param account User address
     * @return totalStakedAmount Total amount staked across all stakes
     * @return activeStakesCount Number of active (non-withdrawn) stakes
     * @return totalStakesCount Total number of stakes (including withdrawn)
     * @return totalPendingRewards Total pending rewards from all active stakes
     * @return canWithdrawWithoutPenalty Number of stakes that can be withdrawn without penalty
     * @return isLaunched Whether staking is available (token launched)
     */
    function getUserSummary(address account) external view returns (
        uint256 totalStakedAmount,
        uint256 activeStakesCount,
        uint256 totalStakesCount,
        uint256 totalPendingRewards,
        uint256 canWithdrawWithoutPenalty,
        bool isLaunched
    ) {
        totalStakedAmount = userTotalStaked[account];
        totalStakesCount = userStakes[account].length;
        activeStakesCount = 0;
        totalPendingRewards = 0;
        canWithdrawWithoutPenalty = 0;
        isLaunched = tokenLaunched;

        StakeInfo[] memory stakes = userStakes[account];

        for (uint256 i = 0; i < stakes.length; i++) {
            if (!stakes[i].withdrawn) {
                activeStakesCount++;
                totalPendingRewards += calculateStakeReward(account, i);

                // Check if this stake can be withdrawn without penalty
                if (block.timestamp >= stakes[i].startTime + minimumStakingPeriod) {
                    canWithdrawWithoutPenalty++;
                }
            }
        }
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title Staking
 * @dev A comprehensive staking contract with reward distribution (Upgradeable)
 */
contract Staking is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // Staking token (used for both staking and rewards)
    IERC20 public stakingToken;

    // Annual reward rate: 630% APR
    uint256 public constant ANNUAL_REWARD_RATE = 630;

    // Total staked tokens
    uint256 public totalStaked;

    // Allowed staking durations in days
    uint256 public constant DURATION_7_DAYS = 7 days;
    uint256 public constant DURATION_14_DAYS = 14 days;
    uint256 public constant DURATION_21_DAYS = 21 days;

    // Individual stake information
    struct StakeInfo {
        uint256 amount;                 // Amount of tokens staked
        uint256 startTime;              // When this stake was created
        uint256 duration;               // Staking duration (7, 14, or 21 days)
        uint256 endTime;                // When this stake ends
        bool withdrawn;                 // Whether this stake has been withdrawn
    }

    // Mapping from staker address to array of stakes
    mapping(address => StakeInfo[]) public userStakes;

    // Mapping from staker address to total staked amount
    mapping(address => uint256) public userTotalStaked;

    // Events
    event StakeCreated(address indexed user, uint256 stakeIndex, uint256 amount, uint256 duration);
    event StakeWithdrawn(address indexed user, uint256 stakeIndex, uint256 amount, uint256 reward);

    function initialize() external initializer {

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        stakingToken = IERC20(address(0xA0F7551c5EfbCDf13A2975F257185aC5D9634dD1));
        totalStaked = 0;
    }

    // ============ Admin Functions ============

    /**
     * @dev Deposit reward tokens for distribution
     * @param amount Amount of reward tokens to deposit
     */
    function depositRewards(uint256 amount) external onlyOwner {
        require(amount > 0, "Cannot deposit 0");
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev Withdraw excess tokens (emergency only)
     * @param amount Amount to withdraw
     */
    function withdrawTokens(uint256 amount) external onlyOwner {
        stakingToken.safeTransfer(msg.sender, amount);
    }

    // ============ Staking Functions ============

    /**
     * @dev Validate staking duration
     * @param duration Duration to validate
     * @return true if valid
     */
    function isValidDuration(uint256 duration) public pure returns (bool) {
        return duration == DURATION_7_DAYS ||
               duration == DURATION_14_DAYS ||
               duration == DURATION_21_DAYS;
    }

    /**
     * @dev Create a new stake with specified duration
     * @param amount Amount to stake
     * @param duration Staking duration (7, 14, or 21 days)
     */
    function createStake(uint256 amount, uint256 duration) external nonReentrant {
        require(amount > 0, "Cannot stake 0");
        require(isValidDuration(duration), "Invalid duration: must be 7, 14, or 21 days");

        // Update total staked
        userTotalStaked[msg.sender] += amount;
        totalStaked += amount;

        uint256 endTime = block.timestamp + duration;

        // Create new stake
        userStakes[msg.sender].push(StakeInfo({
            amount: amount,
            startTime: block.timestamp,
            duration: duration,
            endTime: endTime,
            withdrawn: false
        }));

        uint256 stakeIndex = userStakes[msg.sender].length - 1;

        // Transfer tokens from user to contract
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit StakeCreated(msg.sender, stakeIndex, amount, duration);
    }

    /**
     * @dev Calculate rewards for a specific stake (630% APR prorated)
     * @param account User address
     * @param stakeIndex Index of the stake
     * @return Reward amount
     */
    function calculateStakeReward(address account, uint256 stakeIndex) public view returns (uint256) {
        require(stakeIndex < userStakes[account].length, "Invalid stake index");

        StakeInfo memory stakeInfo = userStakes[account][stakeIndex];

        if (stakeInfo.withdrawn) {
            return 0;
        }

        // Calculate rewards: (amount * 630% * duration) / 365 days
        // Formula: (stakedAmount * ANNUAL_REWARD_RATE * duration) / (100 * 365 days)
        uint256 rewards = (stakeInfo.amount * ANNUAL_REWARD_RATE * stakeInfo.duration) / (100 * 365 days);

        return rewards;
    }

    /**
     * @dev Withdraw a specific stake (only after duration ends)
     * @param stakeIndex Index of the stake to withdraw
     */
    function withdrawStake(uint256 stakeIndex) public nonReentrant {
        require(stakeIndex < userStakes[msg.sender].length, "Invalid stake index");

        StakeInfo storage stakeInfo = userStakes[msg.sender][stakeIndex];
        require(!stakeInfo.withdrawn, "Stake already withdrawn");
        require(stakeInfo.amount > 0, "Nothing to withdraw");
        require(block.timestamp >= stakeInfo.endTime, "Staking period not ended yet");

        uint256 amount = stakeInfo.amount;
        uint256 reward = calculateStakeReward(msg.sender, stakeIndex);

        // Mark as withdrawn
        stakeInfo.withdrawn = true;

        // Update totals
        userTotalStaked[msg.sender] -= amount;
        totalStaked -= amount;

        // Transfer staked tokens + rewards
        uint256 totalAmount = amount + reward;
        require(stakingToken.balanceOf(address(this)) >= totalAmount, "Insufficient balance in contract");

        stakingToken.safeTransfer(msg.sender, totalAmount);

        emit StakeWithdrawn(msg.sender, stakeIndex, amount, reward);
    }

    /**
     * @dev Withdraw all completed stakes
     */
    function withdrawAllStakes() external {
        StakeInfo[] storage stakes = userStakes[msg.sender];

        for (uint256 i = 0; i < stakes.length; i++) {
            if (!stakes[i].withdrawn && stakes[i].amount > 0 && block.timestamp >= stakes[i].endTime) {
                withdrawStake(i);
            }
        }
    }

    // ============ View Functions ============

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
     * @dev Check if a stake can be withdrawn (duration ended)
     * @param account Address to check
     * @param stakeIndex Index of the stake
     * @return true if can be withdrawn
     */
    function canWithdrawStake(address account, uint256 stakeIndex) external view returns (bool) {
        require(stakeIndex < userStakes[account].length, "Invalid stake index");

        StakeInfo memory stakeInfo = userStakes[account][stakeIndex];

        if (stakeInfo.withdrawn) {
            return false;
        }

        return block.timestamp >= stakeInfo.endTime;
    }

    /**
     * @dev Get APR (Annual Percentage Rate)
     * @return APR percentage (630 = 630%)
     */
    function getAPR() external pure returns (uint256) {
        return ANNUAL_REWARD_RATE;
    }

    /**
     * @dev Get comprehensive user summary for dashboard
     * @param account User address
     * @return totalStakedAmount Total amount staked across all stakes
     * @return activeStakesCount Number of active (non-withdrawn) stakes
     * @return totalStakesCount Total number of stakes (including withdrawn)
     * @return totalPendingRewards Total pending rewards from all active stakes
     * @return completedStakesCount Number of stakes that can be withdrawn (duration ended)
     */
    function getUserSummary(address account) external view returns (
        uint256 totalStakedAmount,
        uint256 activeStakesCount,
        uint256 totalStakesCount,
        uint256 totalPendingRewards,
        uint256 completedStakesCount
    ) {
        totalStakedAmount = userTotalStaked[account];
        totalStakesCount = userStakes[account].length;
        activeStakesCount = 0;
        totalPendingRewards = 0;
        completedStakesCount = 0;

        StakeInfo[] memory stakes = userStakes[account];

        for (uint256 i = 0; i < stakes.length; i++) {
            if (!stakes[i].withdrawn) {
                activeStakesCount++;
                totalPendingRewards += calculateStakeReward(account, i);

                // Check if this stake duration has ended
                if (block.timestamp >= stakes[i].endTime) {
                    completedStakesCount++;
                }
            }
        }
    }
}
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

address constant COLLECT_WALLET = 0x6De1644863a8fca0eD20dbD76Cff30C44f104dac; //developer wallet
uint256 constant INITIAL_TOKEN_PRICE = 14; //0.0014
address constant MAINNET_USDT = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0; //USDT address in Ethereum
address constant MAINNET_USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; //USDC address in Sepolia
address constant MAINNET_PSHIBA = 0xA0F7551c5EfbCDf13A2975F257185aC5D9634dD1; //PSHIBA address in Sepolia

address constant UNISWAPV2_ROUTER_ADDRESS = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

IUniswapV2Router02 constant router = IUniswapV2Router02(address(UNISWAPV2_ROUTER_ADDRESS));
IERC20 constant usdt = IERC20(MAINNET_USDT); // USDT contract address
IERC20 constant usdc = IERC20(MAINNET_USDC); // USDC contract address
IERC20 constant pshiba = IERC20(MAINNET_PSHIBA);

contract Presale is Initializable {
    bool public presaleStarted;
    uint public startTimeStamp;
    uint public endTimeStamp;
    uint256 public totalCap;
    address public deployer;
    bool public claimApproved;

    event TokenBuyWithUSDT(address indexed buyer, uint256 amount);
    event TokenBuyWithUSDC(address indexed buyer, uint256 amount);
    event TokenBuyWithETH(address indexed buyer, uint256 amount);
    event TokenClaimed(address indexed caller, uint256 amount);
    event AddressBlacklisted(address indexed account);
    event AddressUnblacklisted(address indexed account);
    event BulkBlacklisted(address[] accounts, uint256 count);
    event BulkUnblacklisted(address[] accounts, uint256 count);

    mapping (address=>uint256) public balances;
    mapping (address=>bool) public blacklisted;
    address[] private blacklistedAddresses;

    uint256 public launchDate;
    bool public tokenLaunched;

    // Referral system
    mapping(address => address) public referrer; // user => referrer address
    mapping(address => uint256) public referralBonus; // user => bonus tokens earned from referrals
    mapping(address => address[]) public referrals; // referrer => list of referred users
    mapping(address => uint256) public totalReferralEarnings; // total earnings per referrer
    uint256 public referralBonusPercent; // bonus percentage for referrer (e.g., 5 = 5%)

    // Staking system
    struct StakeInfo {
        uint256 amount;           // Amount staked
        uint256 stakingPeriod;    // 7, 14, or 21 days
        uint256 stakeStartTime;   // When staking started
        uint256 unlockTime;       // When can unstake
        bool claimed;             // Has claimed staking rewards
    }

    mapping(address => StakeInfo) public stakes;
    mapping(address => uint256) public stakedBalance; // Amount currently staked
    uint256 public totalStaked; // Total tokens staked in contract

    // New events
    event ReferralRegistered(address indexed user, address indexed referrer);
    event ReferralBonusEarned(address indexed referrer, address indexed user, uint256 bonus);
    event TokensStaked(address indexed user, uint256 amount, uint256 period, uint256 unlockTime);
    event TokensUnstaked(address indexed user, uint256 amount);
    event BonusClaimed(address indexed user, uint256 amount);
    event LaunchDateSet(uint256 launchDate);
    event TokenLaunched(uint256 launchDate);

    receive() external payable {}

    modifier onlyDeployer() {
        require(msg.sender == deployer, "Not authorized: Only deployer allowed");
        _;
    }

    function transferDeployer(address newDeployer) external onlyDeployer {
        require(newDeployer != address(0), "Invalid address");
        deployer = newDeployer;
    }

    function initialize() external initializer {
        endTimeStamp = 0;
        startTimeStamp = 0;
        totalCap = 0;
        presaleStarted = false;
        claimApproved = false;

        deployer = msg.sender;

        // Initialize new V2 variables
        referralBonusPercent = 5; // 5% referral bonus by default
        tokenLaunched = false;
        launchDate = 0;
        totalStaked = 0;
    }

    function startPresale(uint256 _endTimeStamp) public onlyDeployer {
        require(
            block.timestamp < _endTimeStamp,
            "Update endtime in the future"
        );

        startTimeStamp = block.timestamp;
        endTimeStamp = _endTimeStamp;
        presaleStarted = true;
    }

    function finishPresale() public onlyDeployer {
        presaleStarted = false;
    }

    function setClaimApprove() public onlyDeployer {
        claimApproved = true;
    }

    function getClaimApprovement () public view returns (bool){
        return claimApproved;
    }

    function resumePresale() public onlyDeployer {
        require(presaleStarted == false, "Presale is under processing now");

        require(
            block.timestamp < endTimeStamp,
            "Update endtime in the future"
        );
        presaleStarted = true;
    }

    function updateEndTimeStamp(uint256 _endTimeStamp) public onlyDeployer {
        require(
            block.timestamp < _endTimeStamp,
            "Update endtime in the future"
        );
        endTimeStamp = _endTimeStamp;
    }

    function updateStartTimeStamp(uint256 _startTimeStamp) public onlyDeployer {
        require(_startTimeStamp > 0, "Invalid Value");
        startTimeStamp = _startTimeStamp;
    }

    function addToBlacklist(address _account) public onlyDeployer {
        require(_account != address(0), "Invalid address");
        require(!blacklisted[_account], "Address already blacklisted");
        blacklisted[_account] = true;
        blacklistedAddresses.push(_account);
        emit AddressBlacklisted(_account);
    }

    function addBulkToBlacklist(address[] calldata _accounts) public onlyDeployer {
        require(_accounts.length > 0, "Empty array");
        require(_accounts.length <= 100, "Too many addresses"); // Gas limit protection

        uint256 addedCount = 0;
        for (uint256 i = 0; i < _accounts.length; i++) {
            address account = _accounts[i];
            if (account != address(0) && !blacklisted[account]) {
                blacklisted[account] = true;
                blacklistedAddresses.push(account);
                addedCount++;
                emit AddressBlacklisted(account);
            }
        }

        emit BulkBlacklisted(_accounts, addedCount);
    }

    function removeFromBlacklist(address _account) public onlyDeployer {
        require(blacklisted[_account], "Address not blacklisted");
        blacklisted[_account] = false;

        // Remove from array
        for (uint256 i = 0; i < blacklistedAddresses.length; i++) {
            if (blacklistedAddresses[i] == _account) {
                blacklistedAddresses[i] = blacklistedAddresses[blacklistedAddresses.length - 1];
                blacklistedAddresses.pop();
                break;
            }
        }

        emit AddressUnblacklisted(_account);
    }

    function removeBulkFromBlacklist(address[] calldata _accounts) public onlyDeployer {
        require(_accounts.length > 0, "Empty array");
        require(_accounts.length <= 100, "Too many addresses"); // Gas limit protection

        uint256 removedCount = 0;
        for (uint256 i = 0; i < _accounts.length; i++) {
            address account = _accounts[i];
            if (blacklisted[account]) {
                blacklisted[account] = false;
                removedCount++;

                // Remove from array
                for (uint256 j = 0; j < blacklistedAddresses.length; j++) {
                    if (blacklistedAddresses[j] == account) {
                        blacklistedAddresses[j] = blacklistedAddresses[blacklistedAddresses.length - 1];
                        blacklistedAddresses.pop();
                        break;
                    }
                }

                emit AddressUnblacklisted(account);
            }
        }

        emit BulkUnblacklisted(_accounts, removedCount);
    }

    function isBlacklisted(address _account) public view returns (bool) {
        return blacklisted[_account];
    }

    function getBlacklistedAddresses() public view returns (address[] memory) {
        return blacklistedAddresses;
    }

    function getBlacklistedCount() public view returns (uint256) {
        return blacklistedAddresses.length;
    }

    function getBlacklistedAddressesPaginated(uint256 _offset, uint256 _limit)
        public
        view
        returns (address[] memory)
    {
        require(_offset < blacklistedAddresses.length, "Offset out of bounds");

        uint256 end = _offset + _limit;
        if (end > blacklistedAddresses.length) {
            end = blacklistedAddresses.length;
        }

        uint256 length = end - _offset;
        address[] memory result = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            result[i] = blacklistedAddresses[_offset + i];
        }

        return result;
    }

    function clearBlacklist() public onlyDeployer {
        uint256 count = blacklistedAddresses.length;
        for (uint256 i = 0; i < count; i++) {
            blacklisted[blacklistedAddresses[i]] = false;
        }
        delete blacklistedAddresses;
    }

    function getCurrentTokenPrice() public view returns (uint256) {
        uint256 currentStep = totalCap / (500 * 10 ** (3 + 18));
        uint256 tokenPrice = INITIAL_TOKEN_PRICE + currentStep * 20;
        return tokenPrice;
    }

    function calculateRemainingTime() public view returns (uint256) {
        require(block.timestamp < endTimeStamp, "Presale is ended");
        return (endTimeStamp - block.timestamp);
    }

    function buyTokenWithUSDT(uint256 _usdtAmount, address _referrer) public {
        require(!blacklisted[msg.sender], "Address is blacklisted");
        if (block.timestamp >= endTimeStamp) presaleStarted = false;

        require(block.timestamp > startTimeStamp, "Presale is not started");
        require(presaleStarted == true, "Presale is ended");
        require(0 < _usdtAmount, "Unavailable amount of token to buy");

        uint256 currentTokenPrice = getCurrentTokenPrice();
        uint256 tokenAmount = (_usdtAmount * 10 ** 4) / currentTokenPrice;

        totalCap = totalCap + _usdtAmount;
        require(usdt.allowance(msg.sender, address(this)) >= _usdtAmount, "Insufficient allowance");
        bool success = usdt.transferFrom(msg.sender, address(COLLECT_WALLET), _usdtAmount);
        require(success , "Transfer failed");

        balances[msg.sender] += tokenAmount;

        // Handle referral
        _processReferral(_referrer, tokenAmount);

        emit TokenBuyWithUSDT(msg.sender, _usdtAmount);
    }

    function buyTokenWithUSDC(uint256 _usdcAmount, address _referrer) public {
        require(!blacklisted[msg.sender], "Address is blacklisted");
        if (block.timestamp >= endTimeStamp) presaleStarted = false;

        require(block.timestamp > startTimeStamp, "Presale is not started");
        require(presaleStarted == true, "Presale is ended");
        require(0 < _usdcAmount, "Unavailable amount of token to buy");

        uint256 currentTokenPrice = getCurrentTokenPrice();
        // USDC has 6 decimals, so we need to normalize to 18 decimals for calculation
        // Convert USDC amount (6 decimals) to 18 decimals equivalent
        uint256 normalizedAmount = _usdcAmount * 10 ** 12;
        uint256 tokenAmount = (normalizedAmount * 10 ** 4) / currentTokenPrice;

        // Add to totalCap in 18 decimal format for consistency
        totalCap = totalCap + normalizedAmount;
        require(usdc.allowance(msg.sender, address(this)) >= _usdcAmount, "Insufficient allowance");
        bool success = usdc.transferFrom(msg.sender, address(COLLECT_WALLET), _usdcAmount);
        require(success , "Transfer failed");

        balances[msg.sender] += tokenAmount;

        // Handle referral
        _processReferral(_referrer, tokenAmount);

        emit TokenBuyWithUSDC(msg.sender, _usdcAmount);
    }

    function buyTokenWithETH(address _referrer) public payable {
        require(!blacklisted[msg.sender], "Address is blacklisted");
        if (block.timestamp >= endTimeStamp) presaleStarted = false;

        require(block.timestamp > startTimeStamp, "Presale is not started");
        require(presaleStarted == true, "Presale is ended");
        require(0 < msg.value, "Unavailable amount of token to buy");

        address WETH = router.WETH();
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = MAINNET_USDT;
        uint256[] memory amounts = router.swapExactETHForTokens{
            value: msg.value
        }(0, path, address(this), block.timestamp + 15 minutes);
        uint256 usdAmount = amounts[1];
        usdt.transfer(address(COLLECT_WALLET), usdt.balanceOf(address(this)));

        uint256 currentTokenPrice = getCurrentTokenPrice();
        uint256 tokenAmount = (usdAmount * 10 ** 4) / currentTokenPrice;
        totalCap += usdAmount;
        balances[msg.sender] += tokenAmount;

        // Handle referral
        _processReferral(_referrer, tokenAmount);

        emit TokenBuyWithETH(msg.sender, usdAmount);
    }

    function getBalance () public view returns (uint256){
        return balances[msg.sender];
    }

    function claimToken (uint256 _amount) public {
        require(!blacklisted[msg.sender], "Address is blacklisted");
        require(tokenLaunched == true, "Token not launched yet!");
        require(_amount > 0, "Invalid claim amount");

        // Calculate available balance (total - staked)
        uint256 availableBalance = balances[msg.sender] - stakedBalance[msg.sender];
        require(availableBalance >= _amount , "Invalid claim amount or tokens are staked");

        require(pshiba.balanceOf(address(this)) >= _amount, "Insufficient amount of pshiba in contract");
        pshiba.transfer(msg.sender, _amount);
        balances[msg.sender] -= _amount;

        emit TokenClaimed(msg.sender, _amount);
    }

    // ============ NEW FUNCTIONS (V2) ============

    // Launch management
    function setLaunchDate(uint256 _launchDate) external onlyDeployer {
        require(_launchDate > block.timestamp, "Launch date must be in future");
        launchDate = _launchDate;
        emit LaunchDateSet(_launchDate);
    }

    function launchToken() external onlyDeployer {
        require(!tokenLaunched, "Token already launched");
        tokenLaunched = true;
        if (launchDate == 0) {
            launchDate = block.timestamp;
        }
        emit TokenLaunched(launchDate);
    }

    // Referral system
    function _processReferral(address _referrer, uint256 _tokenAmount) internal {
        // Only set referrer on first purchase and if valid
        if (referrer[msg.sender] == address(0) && _referrer != address(0) && _referrer != msg.sender) {
            referrer[msg.sender] = _referrer;
            referrals[_referrer].push(msg.sender);
            emit ReferralRegistered(msg.sender, _referrer);
        }

        // Give bonus to referrer if they exist
        if (referrer[msg.sender] != address(0)) {
            address userReferrer = referrer[msg.sender];
            uint256 bonus = (_tokenAmount * referralBonusPercent) / 100;
            referralBonus[userReferrer] += bonus;
            totalReferralEarnings[userReferrer] += bonus;
            emit ReferralBonusEarned(userReferrer, msg.sender, bonus);
        }
    }

    function setReferralBonusPercent(uint256 _percent) external onlyDeployer {
        require(_percent <= 20, "Bonus too high"); // Max 20%
        referralBonusPercent = _percent;
    }

    function claimReferralBonus() external {
        require(!blacklisted[msg.sender], "Address is blacklisted");
        require(tokenLaunched == true, "Token not launched yet!");
        uint256 bonus = referralBonus[msg.sender];
        require(bonus > 0, "No referral bonus to claim");

        require(pshiba.balanceOf(address(this)) >= bonus, "Insufficient PSHIBA in contract");

        referralBonus[msg.sender] = 0;
        pshiba.transfer(msg.sender, bonus);

        emit BonusClaimed(msg.sender, bonus);
    }

    // Staking system (only after token launch)
    function stakeTokens(uint256 _amount, uint256 _period) external {
        require(!blacklisted[msg.sender], "Address is blacklisted");
        require(tokenLaunched == true, "Token not launched yet!");
        require(_period == 7 || _period == 14 || _period == 21, "Invalid staking period");
        require(_amount > 0, "Invalid stake amount");

        // Check available balance (not already staked)
        uint256 availableBalance = balances[msg.sender] - stakedBalance[msg.sender];
        require(availableBalance >= _amount, "Insufficient available balance");

        // Check if user already has an active stake
        require(stakes[msg.sender].amount == 0 || stakes[msg.sender].claimed, "Already have active stake");

        uint256 unlockTime = block.timestamp + (_period * 1 days);

        stakes[msg.sender] = StakeInfo({
            amount: _amount,
            stakingPeriod: _period,
            stakeStartTime: block.timestamp,
            unlockTime: unlockTime,
            claimed: false
        });

        stakedBalance[msg.sender] += _amount;
        totalStaked += _amount;

        emit TokensStaked(msg.sender, _amount, _period, unlockTime);
    }

    function unstakeTokens() external {
        require(!blacklisted[msg.sender], "Address is blacklisted");
        StakeInfo storage stake = stakes[msg.sender];
        require(stake.amount > 0, "No active stake");
        require(!stake.claimed, "Already unstaked");
        require(block.timestamp >= stake.unlockTime, "Staking period not completed");

        uint256 amount = stake.amount;
        stake.claimed = true;
        stakedBalance[msg.sender] -= amount;
        totalStaked -= amount;

        // Tokens remain in balances, just no longer staked
        emit TokensUnstaked(msg.sender, amount);
    }

    // View functions for dashboard
    function getUserDashboard(address _user) external view returns (
        uint256 totalBalance,        // Total PSHIBA purchased
        uint256 availableBalance,    // Not staked, can claim
        uint256 stakedAmount,        // Currently staked
        uint256 referralEarnings,    // Referral bonus available
        uint256 stakeUnlockTime,     // When can unstake
        bool canClaim,               // Is token launched
        bool canUnstake,             // Is stake period over
        uint256 referredCount        // How many people referred
    ) {
        totalBalance = balances[_user];
        stakedAmount = stakedBalance[_user];
        availableBalance = totalBalance - stakedAmount;
        referralEarnings = referralBonus[_user];

        StakeInfo memory stake = stakes[_user];
        stakeUnlockTime = stake.unlockTime;

        canClaim = tokenLaunched;
        canUnstake = stake.amount > 0 && !stake.claimed && block.timestamp >= stake.unlockTime;
        referredCount = referrals[_user].length;
    }

    function getStakeInfo(address _user) external view returns (
        uint256 amount,
        uint256 stakingPeriod,
        uint256 stakeStartTime,
        uint256 unlockTime,
        bool claimed,
        uint256 remainingTime
    ) {
        StakeInfo memory stake = stakes[_user];
        amount = stake.amount;
        stakingPeriod = stake.stakingPeriod;
        stakeStartTime = stake.stakeStartTime;
        unlockTime = stake.unlockTime;
        claimed = stake.claimed;

        if (block.timestamp < unlockTime) {
            remainingTime = unlockTime - block.timestamp;
        } else {
            remainingTime = 0;
        }
    }

    function getReferralInfo(address _user) external view returns (
        address userReferrer,
        uint256 bonusEarned,
        uint256 totalEarnings,
        address[] memory referredUsers,
        uint256 referredCount
    ) {
        userReferrer = referrer[_user];
        bonusEarned = referralBonus[_user];
        totalEarnings = totalReferralEarnings[_user];
        referredUsers = referrals[_user];
        referredCount = referrals[_user].length;
    }

    // Available balance (not staked)
    function getAvailableBalance(address _user) external view returns (uint256) {
        return balances[_user] - stakedBalance[_user];
    }
}
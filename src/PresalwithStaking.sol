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
    event TokensStaked(address indexed user, uint256 amount, uint256 duration, uint256 unlockDate);
    event StakedTokensClaimed(address indexed user, uint256 amount);

    mapping (address=>uint256) public balances;
    mapping (address=>bool) public blacklisted;
    address[] private blacklistedAddresses;

    uint256 public launchDate;
    bool public tokenLaunched;

    // Staking structures
    struct StakeInfo {
        uint256 amount;
        uint256 stakeDuration; // in days (1, 7, 14, or 28)
        uint256 stakeStartTime;
        uint256 unlockDate;
        bool claimed;
    }

    mapping(address => StakeInfo[]) public userStakes;
    mapping(address => uint256) public totalStakedAmount;

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
        tokenLaunched = false;
        launchDate = 0;

        deployer = msg.sender;
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

    function buyTokenWithUSDT(uint256 _usdtAmount) public {
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

        emit TokenBuyWithUSDT(msg.sender, _usdtAmount);
    }

    function buyTokenWithUSDC(uint256 _usdcAmount) public {
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

        emit TokenBuyWithUSDC(msg.sender, _usdcAmount);
    }

    function buyTokenWithETH() public payable {
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

        emit TokenBuyWithETH(msg.sender, usdAmount);
    }

    function getBalance () public view returns (uint256){
        return balances[msg.sender];
    }

    function claimTokenRequest (uint256 _amount) public {
        require(!blacklisted[msg.sender], "Address is blacklisted");
        require(tokenLaunched == true, "Token not launched yet!");
        require(_amount > 0, "Invalid claim amount");

        require(balances[msg.sender] >= _amount , "Invalid claim amount");

        require(pshiba.balanceOf(address(this)) >= _amount, "Insufficient amount of pshiba in contract");
        balances[msg.sender] -= _amount;

        emit TokenClaimed(msg.sender, _amount);
    }

    function claimTokenConfirmed (uint256 _amount, address _to) public onlyDeployer {
        require(_amount > 0, "Invalid claim amount");
        require(_to != address(0), "Invalid address");

        require(pshiba.balanceOf(address(this)) >= _amount, "Insufficient amount of pshiba in contract");
        pshiba.transfer(_to, _amount);

        emit TokenClaimed(_to, _amount);
    }

    // Staking Functions
    function stakeTokens(uint256 _amount, uint256 _durationInDays) public {
        require(!blacklisted[msg.sender], "Address is blacklisted");
        require(_amount > 0, "Amount must be greater than 0");
        require(_durationInDays == 1 || _durationInDays == 7 || _durationInDays == 14 || _durationInDays == 28, "Duration must be 1, 7, 14, or 28 days");
        require(balances[msg.sender] >= _amount, "Insufficient balance");

        // Transfer tokens from balance to staking
        balances[msg.sender] -= _amount;
        totalStakedAmount[msg.sender] += _amount;

        uint256 unlockDate;

        // If token NOT launched yet: unlock date = launchDate + duration
        // If token already launched: unlock date = now + duration
        if (!tokenLaunched) {
            require(launchDate > 0, "Launch date not set yet");
            unlockDate = launchDate + (_durationInDays * 1 days);
        } else {
            unlockDate = block.timestamp + (_durationInDays * 1 days);
        }

        // Create new stake
        userStakes[msg.sender].push(StakeInfo({
            amount: _amount,
            stakeDuration: _durationInDays,
            stakeStartTime: block.timestamp,
            unlockDate: unlockDate,
            claimed: false
        }));

        emit TokensStaked(msg.sender, _amount, _durationInDays, unlockDate);
    }

    function claimStakedTokens(uint256 _stakeIndex) public {
        require(!blacklisted[msg.sender], "Address is blacklisted");
        require(_stakeIndex < userStakes[msg.sender].length, "Invalid stake index");

        StakeInfo storage stake = userStakes[msg.sender][_stakeIndex];
        require(!stake.claimed, "Tokens already claimed");
        require(block.timestamp >= stake.unlockDate, "Tokens are still locked");
        require(pshiba.balanceOf(address(this)) >= stake.amount, "Insufficient tokens in contract");

        stake.claimed = true;
        totalStakedAmount[msg.sender] -= stake.amount;

        bool success = pshiba.transfer(msg.sender, stake.amount);
        require(success, "Transfer failed");

        emit StakedTokensClaimed(msg.sender, stake.amount);
    }

    function claimAllUnlockedStakes() public {
        require(!blacklisted[msg.sender], "Address is blacklisted");

        uint256 totalClaimable = 0;
        StakeInfo[] storage stakes = userStakes[msg.sender];

        for (uint256 i = 0; i < stakes.length; i++) {
            if (!stakes[i].claimed && block.timestamp >= stakes[i].unlockDate) {
                totalClaimable += stakes[i].amount;
                stakes[i].claimed = true;
            }
        }

        require(totalClaimable > 0, "No unlocked stakes available");
        require(pshiba.balanceOf(address(this)) >= totalClaimable, "Insufficient tokens in contract");

        totalStakedAmount[msg.sender] -= totalClaimable;

        bool success = pshiba.transfer(msg.sender, totalClaimable);
        require(success, "Transfer failed");

        emit StakedTokensClaimed(msg.sender, totalClaimable);
    }

    function getUserStakes(address _user) public view returns (StakeInfo[] memory) {
        return userStakes[_user];
    }

    function getUserStakeCount(address _user) public view returns (uint256) {
        return userStakes[_user].length;
    }

    function getTotalStakedAmount(address _user) public view returns (uint256) {
        return totalStakedAmount[_user];
    }

    function getClaimableStakedAmount(address _user) public view returns (uint256) {
        uint256 claimable = 0;
        StakeInfo[] memory stakes = userStakes[_user];

        for (uint256 i = 0; i < stakes.length; i++) {
            if (!stakes[i].claimed && block.timestamp >= stakes[i].unlockDate) {
                claimable += stakes[i].amount;
            }
        }

        return claimable;
    }

    function getLockedStakedAmount(address _user) public view returns (uint256) {
        uint256 locked = 0;
        StakeInfo[] memory stakes = userStakes[_user];

        for (uint256 i = 0; i < stakes.length; i++) {
            if (!stakes[i].claimed && block.timestamp < stakes[i].unlockDate) {
                locked += stakes[i].amount;
            }
        }

        return locked;
    }

    function getAvailableBalance(address _user) public view returns (uint256) {
        return balances[_user];
    }

    // Launch management
    function setLaunchDate(uint256 _launchDate) external onlyDeployer {
        require(_launchDate > block.timestamp, "Launch date must be in future");
        launchDate = _launchDate;
    }

    function launchToken() external onlyDeployer {
        require(!tokenLaunched, "Token already launched");
        tokenLaunched = true;
        if (launchDate == 0) {
            launchDate = block.timestamp;
        }
    }
}
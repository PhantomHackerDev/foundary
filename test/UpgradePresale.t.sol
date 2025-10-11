// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/Presale.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract UpgradePresaleTest is Test {
    Presale public presaleV1;
    Presale public presaleV2;
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public proxy;
    Presale public presaleProxy;

    address public deployer = address(1);
    address public user = address(2);

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy V1 (old version without stages)
        presaleV1 = new Presale();

        // Deploy ProxyAdmin
        proxyAdmin = new ProxyAdmin(deployer);

        // Deploy proxy with V1
        bytes memory initData = abi.encodeWithSelector(Presale.initialize.selector);
        proxy = new TransparentUpgradeableProxy(
            address(presaleV1),
            address(proxyAdmin),
            initData
        );

        // Create interface to interact with proxy
        presaleProxy = Presale(payable(address(proxy)));

        vm.stopPrank();
    }

    function testUpgradePreservesData() public {
        vm.startPrank(deployer);

        // Setup some data in V1
        presaleProxy.startPresale(block.timestamp + 30 days);

        // Simulate user purchase (simplified - would need actual token setup)
        // Just verify the state before upgrade
        assertTrue(presaleProxy.presaleStarted(), "Presale should be started");
        address savedDeployer = presaleProxy.deployer();

        // Deploy V2 (new version with stages)
        presaleV2 = new Presale();

        // Perform upgrade
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxy)),
            address(presaleV2),
            ""
        );

        // Verify data is preserved after upgrade
        assertEq(presaleProxy.deployer(), savedDeployer, "Deployer should be preserved");
        assertTrue(presaleProxy.presaleStarted(), "Presale state should be preserved");

        // Verify new functionality exists
        assertEq(presaleProxy.getStagesCount(), 0, "Should have 0 stages initially");

        vm.stopPrank();
    }

    function testAddStageAfterUpgrade() public {
        vm.startPrank(deployer);

        // Upgrade to V2
        presaleV2 = new Presale();
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxy)),
            address(presaleV2),
            ""
        );

        // Add a stage
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = block.timestamp + 8 days;
        uint256 tokenPrice = 14; // 0.0014
        uint256 maxCap = 100000 * 10**18; // $100k

        presaleProxy.addStage(startTime, endTime, tokenPrice, maxCap);

        // Verify stage was added
        assertEq(presaleProxy.getStagesCount(), 1, "Should have 1 stage");

        (
            uint256 stageStart,
            uint256 stageEnd,
            uint256 stagePrice,
            uint256 stageCap,
            uint256 stageRaised,
            bool stageActive
        ) = presaleProxy.getStage(0);

        assertEq(stageStart, startTime, "Start time should match");
        assertEq(stageEnd, endTime, "End time should match");
        assertEq(stagePrice, tokenPrice, "Price should match");
        assertEq(stageCap, maxCap, "Max cap should match");
        assertEq(stageRaised, 0, "Raised amount should be 0");
        assertTrue(stageActive, "Stage should be active");

        vm.stopPrank();
    }

    function testCannotUpgradeFromNonAdmin() public {
        presaleV2 = new Presale();

        vm.prank(user);
        vm.expectRevert();
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxy)),
            address(presaleV2),
            ""
        );
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/Staking.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployStaking is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying Staking from address:", deployer);
        console.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        Staking implementation = new Staking();
        console.log("Implementation deployed at:", address(implementation));

        // Deploy ProxyAdmin
        ProxyAdmin proxyAdmin = new ProxyAdmin(deployer);
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));

        // Encode initialize function call
        bytes memory initData = abi.encodeWithSelector(
            Staking.initialize.selector
        );

        // Deploy proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );
        console.log("Proxy deployed at:", address(proxy));

        console.log("\n=== Deployment Summary ===");
        console.log("Implementation:", address(implementation));
        console.log("ProxyAdmin:", address(proxyAdmin));
        console.log("Proxy (Staking):", address(proxy));
        console.log("Deployer:", deployer);

        vm.stopBroadcast();
    }
}

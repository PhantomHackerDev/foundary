// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/Presale.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradePresale is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // These addresses come from your initial deployment
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        address proxyAdminAddress = vm.envAddress("PROXY_ADMIN_ADDRESS");

        console.log("Upgrading from address:", deployer);
        console.log("Proxy address:", proxyAddress);
        console.log("ProxyAdmin address:", proxyAdminAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        Presale newImplementation = new Presale();
        console.log("New implementation deployed at:", address(newImplementation));

        // Upgrade the proxy to point to new implementation
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(proxyAddress),
            address(newImplementation),
            "" // Empty bytes for no additional call
        );

        console.log("\n=== Upgrade Summary ===");
        console.log("Proxy:", proxyAddress);
        console.log("Old Implementation: [check on explorer]");
        console.log("New Implementation:", address(newImplementation));
        console.log("ProxyAdmin:", proxyAdminAddress);

        vm.stopBroadcast();
    }
}

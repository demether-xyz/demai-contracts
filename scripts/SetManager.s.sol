// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/VaultFactory.sol";

contract SetManager is Script {
    // UPDATE THESE CONSTANTS BEFORE RUNNING
    address constant VAULT_FACTORY_ADDRESS = 0x5C97F0a08a1c8a3Ed6C1E1dB2f7Ce08a4BFE53C7; // VaultFactory PROXY address (from latest deployment)
    address constant NEW_MANAGER_ADDRESS = 0x55b3d73e525227A7F0b25e28e17c1E94006A25dd; // Update with the new manager address

    function run() external {
        console.log("=== Setting VaultFactory Manager ===");

        // Get the deployer's private key and derive the address
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer Address:");
        console.logAddress(deployer);
        console.log("Chain ID:");
        console.logUint(block.chainid);

        // Use constant addresses
        address vaultFactoryAddress = VAULT_FACTORY_ADDRESS;
        console.log("VaultFactory Address:");
        console.logAddress(vaultFactoryAddress);

        address newManager = NEW_MANAGER_ADDRESS;
        console.log("New Manager Address:");
        console.logAddress(newManager);

        // Connect to the VaultFactory
        VaultFactory vaultFactory = VaultFactory(vaultFactoryAddress);

        // Verify deployer is the owner
        address currentOwner = vaultFactory.owner();
        console.log("Current Owner:");
        console.logAddress(currentOwner);

        if (currentOwner != deployer) {
            console.log("ERROR: Deployer is not the owner of the VaultFactory");
            revert("Deployer is not the owner");
        }

        // Get current manager
        address currentManager = vaultFactory.authorizedManager();
        console.log("Current Manager:");
        console.logAddress(currentManager);

        vm.startBroadcast(deployerPrivateKey);

        // Set the new manager
        console.log("\n--- Setting New Manager ---");
        vaultFactory.setManager(newManager);

        vm.stopBroadcast();

        // Verify the change
        console.log("\n--- Verifying Manager Change ---");
        address updatedManager = vaultFactory.authorizedManager();
        console.log("Updated Manager:");
        console.logAddress(updatedManager);

        if (updatedManager == newManager) {
            console.log("SUCCESS: Manager has been updated successfully");
        } else {
            console.log("ERROR: Manager update failed");
            revert("Manager update failed");
        }

        console.log("\n=== Manager Set Complete ===");
        console.log("Previous Manager: ", currentManager);
        console.log("New Manager:      ", newManager);
        console.log("VaultFactory:     ", vaultFactoryAddress);
    }
}

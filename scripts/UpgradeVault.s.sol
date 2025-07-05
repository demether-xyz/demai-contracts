// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/Vault.sol";
import "../src/VaultFactory.sol";

contract UpgradeVault is Script {
    function run() external {
        console.log("=== Vault Implementation Upgrade ===");

        // Get the deployer's private key and derive the address
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get the existing proxy address from environment or deployment file
        address existingProxy = 0x5C97F0a08a1c8a3Ed6C1E1dB2f7Ce08a4BFE53C7;

        console.log("Deployer Address:");
        console.logAddress(deployer);
        console.log("Deployer Balance:");
        console.logUint(deployer.balance);
        console.log("Chain ID:");
        console.logUint(block.chainid);
        console.log("Existing VaultFactory Proxy:");
        console.logAddress(existingProxy);

        // Wrap existing proxy in VaultFactory interface
        VaultFactory existingFactory = VaultFactory(existingProxy);

        // Verify deployer is the owner
        address currentOwner = existingFactory.owner();
        console.log("Current Factory Owner:");
        console.logAddress(currentOwner);

        require(currentOwner == deployer, "Deployer is not the factory owner");

        // Get current state before upgrade
        console.log("\n--- Current Vault State ---");
        address currentVaultImpl = existingFactory.getImplementation();
        console.log("Current Vault Implementation:");
        console.logAddress(currentVaultImpl);
       
        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy new Vault implementation
        console.log("\n--- Deploying New Vault Implementation ---");
        Vault newVaultImplementation = new Vault();
        address newVaultImplAddress = address(newVaultImplementation);
        console.log("New Vault Implementation deployed at:");
        console.logAddress(newVaultImplAddress);

        // Step 2: Upgrade the beacon to the new implementation
        console.log("\n--- Upgrading Vault Beacon ---");
        existingFactory.upgradeBeacon(newVaultImplAddress);

        vm.stopBroadcast();

        // Step 3: Verify upgrade
        console.log("\n--- Verifying Upgrade ---");
        address updatedVaultImpl = existingFactory.getImplementation();
        console.log("Updated Vault Implementation:");
        console.logAddress(updatedVaultImpl);
        require(updatedVaultImpl == newVaultImplAddress, "Vault implementation upgrade failed");

        // Step 4: Output upgrade summary
        console.log("\n=== Upgrade Summary ===");
        console.log("VaultFactory Proxy:           ", existingProxy);
        console.log("Previous Vault Implementation:", currentVaultImpl);
        console.log("New Vault Implementation:     ", newVaultImplAddress);
        console.log("Owner:                        ", deployer);
        console.log("=== Upgrade Complete ===");

        // Save upgrade info to a file
        string memory upgradeInfo = string(
            abi.encodePacked(
                "Chain ID: ",
                vm.toString(block.chainid),
                "\n",
                "VaultFactory Proxy: ",
                vm.toString(existingProxy),
                "\n",
                "New Vault Implementation: ",
                vm.toString(newVaultImplAddress),
                "\n",
                "Owner: ",
                vm.toString(deployer),
                "\n",
                "Block Number: ",
                vm.toString(block.number),
                "\n",
                "Timestamp: ",
                vm.toString(block.timestamp),
                "\n",
                "Upgrade Type: Vault Implementation"
            )
        );

        vm.writeFile("deployments/latest-vault-upgrade.txt", upgradeInfo);
        console.log("\nUpgrade info saved to: deployments/latest-vault-upgrade.txt");
    }
} 
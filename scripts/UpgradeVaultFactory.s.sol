// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/Vault.sol";
import "../src/VaultFactory.sol";

contract UpgradeVaultFactory is Script {
    function run() external {
        console.log("=== VaultFactory Upgrade ===");

        // Get the deployer's private key and derive the address
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get the existing proxy address from environment or deployment file
        address existingProxy = vm.envAddress("VAULT_FACTORY_PROXY");

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
        console.log("\n--- Current Factory State ---");
        console.log("Current Implementation:");
        console.logAddress(existingFactory.getImplementation());
        console.log("Current Beacon:");
        console.logAddress(existingFactory.getBeacon());
        console.log("Total Vaults:");
        console.logUint(existingFactory.getTotalVaults());
        console.log("Factory Paused Status:");
        console.logBool(existingFactory.paused());

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy new VaultFactory implementation
        console.log("\n--- Deploying New VaultFactory Implementation ---");
        VaultFactory newVaultFactoryImplementation = new VaultFactory();
        console.log("New VaultFactory Implementation deployed at:");
        console.logAddress(address(newVaultFactoryImplementation));

        // Step 2: Upgrade the proxy to the new implementation
        console.log("\n--- Upgrading VaultFactory Proxy ---");
        existingFactory.upgradeToAndCall(
            address(newVaultFactoryImplementation),
            "" // No additional call data needed
        );

        vm.stopBroadcast();

        // Step 3: Verify upgrade
        console.log("\n--- Verifying Upgrade ---");
        console.log("Updated Implementation:");
        console.logAddress(existingFactory.getImplementation());
        console.log("Factory Owner (should remain same):");
        console.logAddress(existingFactory.owner());
        console.log("Beacon Address (should remain same):");
        console.logAddress(existingFactory.getBeacon());
        console.log("Total Vaults (should remain same):");
        console.logUint(existingFactory.getTotalVaults());
        console.log("Factory Paused Status (should remain same):");
        console.logBool(existingFactory.paused());

        // Step 4: Output upgrade summary
        console.log("\n=== Upgrade Summary ===");
        console.log("VaultFactory Proxy:           ", existingProxy);
        console.log("New Implementation:           ", address(newVaultFactoryImplementation));
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
                "New VaultFactory Implementation: ",
                vm.toString(address(newVaultFactoryImplementation)),
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
                "Upgrade Type: VaultFactory Implementation"
            )
        );

        vm.writeFile("deployments/latest-upgrade.txt", upgradeInfo);
        console.log("\nUpgrade info saved to: deployments/latest-upgrade.txt");
    }

    /**
     * @dev Alternative upgrade function that also upgrades the vault implementation
     * @dev Call this if you want to upgrade both factory and vault implementations
     */
    function upgradeWithNewVaultImplementation() external {
        console.log("=== VaultFactory + Vault Implementation Upgrade ===");

        // Get the deployer's private key and derive the address
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get the existing proxy address from environment or deployment file
        address existingProxy = vm.envAddress("VAULT_FACTORY_PROXY");

        console.log("Deployer Address:");
        console.logAddress(deployer);
        console.log("Existing VaultFactory Proxy:");
        console.logAddress(existingProxy);

        // Wrap existing proxy in VaultFactory interface
        VaultFactory existingFactory = VaultFactory(existingProxy);

        // Verify deployer is the owner
        require(existingFactory.owner() == deployer, "Deployer is not the factory owner");

        console.log("\n--- Current State ---");
        console.log("Current Factory Implementation:");
        console.logAddress(existingFactory.getImplementation());
        console.log("Current Vault Implementation:");
        console.logAddress(existingFactory.getImplementation());

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy new Vault implementation
        console.log("\n--- Deploying New Vault Implementation ---");
        Vault newVaultImplementation = new Vault();
        console.log("New Vault Implementation deployed at:");
        console.logAddress(address(newVaultImplementation));

        // Step 2: Deploy new VaultFactory implementation
        console.log("\n--- Deploying New VaultFactory Implementation ---");
        VaultFactory newVaultFactoryImplementation = new VaultFactory();
        console.log("New VaultFactory Implementation deployed at:");
        console.logAddress(address(newVaultFactoryImplementation));

        // Step 3: Upgrade the factory proxy
        console.log("\n--- Upgrading VaultFactory Proxy ---");
        existingFactory.upgradeToAndCall(address(newVaultFactoryImplementation), "");

        // Step 4: Upgrade the vault beacon to new implementation
        console.log("\n--- Upgrading Vault Beacon ---");
        existingFactory.upgradeBeacon(address(newVaultImplementation));

        vm.stopBroadcast();

        // Step 5: Verify upgrades
        console.log("\n--- Verifying Upgrades ---");
        console.log("Updated Factory Implementation:");
        console.logAddress(existingFactory.getImplementation());
        console.log("Updated Vault Implementation:");
        console.logAddress(existingFactory.getImplementation());

        console.log("\n=== Full Upgrade Complete ===");
        console.log("New Factory Implementation:   ", address(newVaultFactoryImplementation));
        console.log("New Vault Implementation:     ", address(newVaultImplementation));
    }
}

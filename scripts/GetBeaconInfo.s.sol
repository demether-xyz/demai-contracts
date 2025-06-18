// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/VaultFactory.sol";

contract GetBeaconInfo is Script {
    function run() external view {
        console.log("=== Getting Beacon Information ===");

        // VaultFactory proxy address from latest deployment
        address vaultFactoryProxy = 0x6680952dc4Cf017eb31CB98c2112CA38171982d3;

        console.log("Chain ID:");
        console.logUint(block.chainid);
        console.log("VaultFactory Proxy Address:");
        console.logAddress(vaultFactoryProxy);

        // Connect to the deployed VaultFactory
        VaultFactory vaultFactory = VaultFactory(vaultFactoryProxy);

        // Get beacon address
        address beaconAddress = vaultFactory.getBeacon();
        console.log("\n--- Beacon Information ---");
        console.log("Beacon Address:");
        console.logAddress(beaconAddress);

        // Get current implementation from beacon
        address currentImplementation = vaultFactory.getImplementation();
        console.log("Current Vault Implementation:");
        console.logAddress(currentImplementation);

        // Get creation code for BeaconProxy
        bytes memory creationCode = vaultFactory.getBeaconProxyCreationCode();
        console.log("\n--- Creation Code Information ---");
        console.log("BeaconProxy Creation Code Length:");
        console.logUint(creationCode.length);
        console.log("BeaconProxy Creation Code Hash:");
        console.logBytes32(keccak256(creationCode));

        // Output creation code as hex string
        console.log("\nBeaconProxy Creation Code (Hex):");
        console.logBytes(creationCode);

        // Additional factory information
        console.log("\n--- Factory Status ---");
        console.log("Factory Owner:");
        console.logAddress(vaultFactory.owner());
        console.log("Factory Paused:");
        console.logBool(vaultFactory.paused());
        console.log("Total Vaults Deployed:");
        console.logUint(vaultFactory.getTotalVaults());

        // Example: Predict a vault address
        address exampleUser = 0x55b3d73e525227A7F0b25e28e17c1E94006A25dd;
        address predictedVault = vaultFactory.predictVaultAddress(exampleUser);
        console.log("\n--- Example Vault Prediction ---");
        console.log("Example User:");
        console.logAddress(exampleUser);
        console.log("Predicted Vault Address:");
        console.logAddress(predictedVault);

        console.log("\n=== Beacon Info Complete ===");
    }
}

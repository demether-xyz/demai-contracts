// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/VaultFactory.sol";

contract PredictAddress is Script {
    function run() external view {
        address factoryAddress = 0x5C97F0a08a1c8a3Ed6C1E1dB2f7Ce08a4BFE53C7;
        address userAddress = 0x55b3d73e525227A7F0b25e28e17c1E94006A25dd;

        VaultFactory factory = VaultFactory(factoryAddress);
        address predictedVault = factory.predictVaultAddress(userAddress);

        console.log("Predicted Vault Address:", predictedVault);
    }
}

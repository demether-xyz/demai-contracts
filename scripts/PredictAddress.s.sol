// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/VaultFactory.sol";

contract PredictVaultAddress is Script {
    function run() external view {
        address factoryAddress = 0x516D43C6398aea419806b9f3Ae84701b0c0486a3;
        address userAddress = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

        VaultFactory factory = VaultFactory(factoryAddress);
        address predictedVault = factory.predictVaultAddress(userAddress);

        console.log("Predicted Vault Address:", predictedVault);
    }
}

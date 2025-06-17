// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

contract VerifySetup is Script {
    function run() external {
        console.log("=== Deployment Setup Verification ===");

        // Print contract name
        console.log("Contract Name: VerifySetup");

        // Print chain information
        console.log("Chain ID:");
        console.logUint(block.chainid);
        console.log("Block Number:");
        console.logUint(block.number);
        console.log("Block Timestamp:");
        console.logUint(block.timestamp);

        // Print deployer information
        try vm.envAddress("DEPLOYER_ADDRESS") returns (address deployer) {
            console.log("Deployer Address:");
            console.logAddress(deployer);
            console.log("Deployer Balance:");
            console.logUint(deployer.balance);
        } catch {
            console.log("DEPLOYER_ADDRESS not found in environment");
        }

        // Print RPC information (this will show the RPC being used)
        console.log("Current Block Hash:");
        console.logBytes32(blockhash(block.number - 1));

        // Try to read some environment variables
        try vm.envString("INFURA_API_KEY") returns (string memory infuraKey) {
            console.log("Infura API Key (first 10 chars):", substring(infuraKey, 0, 10));
        } catch {
            console.log("INFURA_API_KEY not found in environment");
        }

        try vm.envString("PRIVATE_KEY") returns (string memory) {
            console.log("Private Key: Found and loaded");
        } catch {
            console.log("PRIVATE_KEY not found in environment");
        }

        console.log("=== Verification Complete ===");
        console.log("If you see this message, the script is running successfully!");
    }

    // Helper function to get substring
    function substring(string memory str, uint startIndex, uint length) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (startIndex >= strBytes.length || length == 0) {
            return "";
        }

        uint endIndex = startIndex + length;
        if (endIndex > strBytes.length) {
            endIndex = strBytes.length;
        }

        bytes memory result = new bytes(endIndex - startIndex);
        for (uint i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/Vault.sol";
import "../src/VaultFactory.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

// Minimal contract for deterministic proxy address.
// Its address is what matters for CREATE2 determinism. It is never called.
contract DummyImplementation {}

contract DeployVaultFactory is Script {
    // Fixed salts for deterministic deployment across all chains
    bytes32 public constant VAULT_IMPL_SALT = keccak256("DEMAI_VAULT_IMPL_V1");
    bytes32 public constant REAL_FACTORY_IMPL_SALT = keccak256("DEMAI_REAL_FACTORY_IMPL_V1");
    bytes32 public constant FACTORY_PROXY_SALT = keccak256("DEMAI_FACTORY_PROXY_V1");

    function isDeployed(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    function deployIfNotExists(uint256 value, bytes32 salt, bytes memory bytecode) internal returns (address) {
        address create2Deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        address predicted = Create2.computeAddress(salt, keccak256(bytecode), create2Deployer);
        if (isDeployed(predicted)) {
            console.log("Contract already exists at:", predicted);
            return predicted;
        }
        return Create2.deploy(value, salt, bytecode);
    }

    function run() external {
        console.log("=== Deterministic VaultFactory Deployment ===");

        bytes memory vaultBytecode = type(Vault).creationCode;
        bytes memory realFactoryBytecode = type(VaultFactory).creationCode;

        uint256 deployerPrivateKey;
        if (block.chainid == 31337) {
            // Anvil/Hardhat local chain
            // Use a default Anvil private key for local testing
            deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        } else {
            deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        }

        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer Address:", deployer);
        console.log("Deployer Balance:", deployer.balance);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        console.log("--- Deploying Vault Implementation ---");
        address vaultImplementation = deployIfNotExists(0, VAULT_IMPL_SALT, vaultBytecode);
        console.log("Vault Implementation deployed at:", vaultImplementation);

        console.log("--- Deploying Real VaultFactory Implementation ---");
        address realFactoryImpl = deployIfNotExists(0, REAL_FACTORY_IMPL_SALT, realFactoryBytecode);
        console.log("Real Factory Implementation deployed at:", realFactoryImpl);

        // Deploy proxy using the real implementation but with empty init data
        // We will initialize it in a separate call.
        console.log("--- Deploying VaultFactory Proxy ---");
        bytes memory proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(realFactoryImpl, "") // No init data yet
        );
        address vaultFactoryProxy = deployIfNotExists(0, FACTORY_PROXY_SALT, proxyBytecode);
        console.log("VaultFactory Proxy deployed at:", vaultFactoryProxy);

        // Now initialize the proxy
        console.log("--- Initializing Proxy ---");
        bytes memory initData = abi.encodeWithSignature("initialize(address,address)", deployer, vaultImplementation);
        (bool success, ) = vaultFactoryProxy.call(initData);
        require(success, "Proxy initialization failed");

        console.log("Proxy initialized!");

        vm.stopBroadcast();

        console.log("--- Verifying Final Deployment ---");
        // Foundry uses the standard CREATE2 deployer contract for deterministic deployments
        // This is the Arachnid CREATE2 deployer at address 0x4e59b44847b379578588920cA78FbF26c0B4956C
        address create2Deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

        address predictedVaultImpl = Create2.computeAddress(VAULT_IMPL_SALT, keccak256(vaultBytecode), create2Deployer);
        address predictedRealFactoryImpl = Create2.computeAddress(REAL_FACTORY_IMPL_SALT, keccak256(realFactoryBytecode), create2Deployer);

        bytes memory newProxyBytecode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(realFactoryImpl, ""));
        address predictedFactoryProxy = Create2.computeAddress(FACTORY_PROXY_SALT, keccak256(newProxyBytecode), create2Deployer);

        console.log("--- Post-Broadcast Verification ---");
        VaultFactory vaultFactory = VaultFactory(vaultFactoryProxy);
        console.log("VaultFactory Owner:", vaultFactory.owner());
        console.log("Vault Implementation in Beacon:", vaultFactory.getImplementation());
        console.log("Beacon Address:", vaultFactory.getBeacon());

        console.log("--- Address Verification ---");
        console.log("Predicted Vault Implementation:   ", predictedVaultImpl);
        console.log("Actual Vault Implementation:     ", vaultImplementation);
        console.log("Predicted Real Factory Impl:    ", predictedRealFactoryImpl);
        console.log("Actual Real Factory Impl:       ", realFactoryImpl);
        console.log("Predicted Factory Proxy:         ", predictedFactoryProxy);
        console.log("Actual Factory Proxy:            ", vaultFactoryProxy);

        require(predictedVaultImpl == vaultImplementation, "Vault implementation address mismatch");
        require(predictedRealFactoryImpl == realFactoryImpl, "Real factory implementation address mismatch");
        require(predictedFactoryProxy == vaultFactoryProxy, "Factory proxy address mismatch");
        console.log("All addresses match predictions!");

        console.log("=== Deployment Complete ===");
        console.log("VaultFactory Proxy:", vaultFactoryProxy);
        console.log("Deployer/Owner:", deployer);

        // Save deployment addresses to chain-specific files
        string memory timestamp = vm.toString(block.timestamp);
        string memory chainId = vm.toString(block.chainid);

        string memory deploymentInfo = string(
            abi.encodePacked(
                "Chain ID: ",
                chainId,
                "\n",
                "Vault Implementation: ",
                vm.toString(vaultImplementation),
                "\n",
                "Real Factory Implementation: ",
                vm.toString(realFactoryImpl),
                "\n",
                "VaultFactory Proxy: ",
                vm.toString(vaultFactoryProxy),
                "\n",
                "Owner: ",
                vm.toString(deployer),
                "\n",
                "Block Number: ",
                vm.toString(block.number),
                "\n",
                "Timestamp: ",
                timestamp,
                "\n",
                "---"
            )
        );

        // Create timestamped deployment file for this specific deployment
        string memory timestampedFile = string(abi.encodePacked("deployments/chain-", chainId, "-deployment-", timestamp, ".txt"));
        vm.writeFile(timestampedFile, deploymentInfo);
        console.log("Timestamped deployment saved to:", timestampedFile);

        // Update/create chain-specific latest deployment file
        string memory latestFile = string(abi.encodePacked("deployments/chain-", chainId, "-latest.txt"));
        vm.writeFile(latestFile, deploymentInfo);
        console.log("Latest deployment for chain saved to:", latestFile);

        // Append to master deployment history file
        string memory historyFile = "deployments/deployment-history.txt";
        string memory historyEntry = string(abi.encodePacked("\n=== Deployment ", timestamp, " ===\n", deploymentInfo, "\n"));

        // Try to read existing history and append, or create new if it doesn't exist
        try vm.readFile(historyFile) returns (string memory existingHistory) {
            string memory updatedHistory = string(abi.encodePacked(existingHistory, historyEntry));
            vm.writeFile(historyFile, updatedHistory);
        } catch {
            // File doesn't exist, create it with header
            string memory newHistory = string(abi.encodePacked("=== DeMai Vault Factory Deployment History ===", historyEntry));
            vm.writeFile(historyFile, newHistory);
        }
        console.log("Deployment appended to history:", historyFile);

        // Keep the original latest-deployment.txt for backward compatibility
        vm.writeFile("deployments/latest-deployment.txt", deploymentInfo);
        console.log("Backward compatible file updated:", "deployments/latest-deployment.txt");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/Vault.sol";
import "../src/VaultFactory.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployVaultFactory is Script {
    function run() external {
        console.log("=== VaultFactory Deployment ===");

        // Get the deployer's private key and derive the address
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer Address:");
        console.logAddress(deployer);
        console.log("Deployer Balance:");
        console.logUint(deployer.balance);
        console.log("Chain ID:");
        console.logUint(block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy the Vault implementation contract
        console.log("\n--- Deploying Vault Implementation ---");
        Vault vaultImplementation = new Vault();
        console.log("Vault Implementation deployed at:");
        console.logAddress(address(vaultImplementation));

        // Step 2: Deploy the VaultFactory implementation
        console.log("\n--- Deploying VaultFactory Implementation ---");
        VaultFactory vaultFactoryImplementation = new VaultFactory();
        console.log("VaultFactory Implementation deployed at:");
        console.logAddress(address(vaultFactoryImplementation));

        // Step 3: Prepare initialization data for VaultFactory
        bytes memory initData = abi.encodeWithSelector(
            VaultFactory.initialize.selector,
            deployer, // owner
            address(vaultImplementation) // vault implementation
        );

        // Step 4: Deploy VaultFactory proxy
        console.log("\n--- Deploying VaultFactory Proxy ---");
        ERC1967Proxy vaultFactoryProxy = new ERC1967Proxy(address(vaultFactoryImplementation), initData);

        console.log("VaultFactory Proxy deployed at:");
        console.logAddress(address(vaultFactoryProxy));

        // Wrap proxy in VaultFactory interface for easier interaction
        VaultFactory vaultFactory = VaultFactory(address(vaultFactoryProxy));

        vm.stopBroadcast();

        // Step 5: Verify deployment
        console.log("\n--- Verifying Deployment ---");
        console.log("VaultFactory Owner:");
        console.logAddress(vaultFactory.owner());
        console.log("Vault Implementation in Beacon:");
        console.logAddress(vaultFactory.getImplementation());
        console.log("Beacon Address:");
        console.logAddress(vaultFactory.getBeacon());
        console.log("Factory Paused Status:");
        console.logBool(vaultFactory.paused());
        console.log("Total Vaults:");
        console.logUint(vaultFactory.getTotalVaults());

        // Step 6: Output deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Vault Implementation:     ", address(vaultImplementation));
        console.log("VaultFactory Implementation:", address(vaultFactoryImplementation));
        console.log("VaultFactory Proxy:       ", address(vaultFactoryProxy));
        console.log("Deployer/Owner:           ", deployer);
        console.log("=== Deployment Complete ===");

        // Save deployment addresses to a file (optional)
        string memory deploymentInfo = string(
            abi.encodePacked(
                "Chain ID: ",
                vm.toString(block.chainid),
                "\n",
                "Vault Implementation: ",
                vm.toString(address(vaultImplementation)),
                "\n",
                "VaultFactory Implementation: ",
                vm.toString(address(vaultFactoryImplementation)),
                "\n",
                "VaultFactory Proxy: ",
                vm.toString(address(vaultFactoryProxy)),
                "\n",
                "Owner: ",
                vm.toString(deployer),
                "\n",
                "Block Number: ",
                vm.toString(block.number),
                "\n",
                "Timestamp: ",
                vm.toString(block.timestamp)
            )
        );

        vm.writeFile("deployments/latest-deployment.txt", deploymentInfo);
        console.log("\nDeployment info saved to: deployments/latest-deployment.txt");
    }
}

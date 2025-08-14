// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {
    BalancerValidatorManager,
    BalancerValidatorManagerSettings
} from "../../src/contracts/ValidatorManager/BalancerValidatorManager.sol";
import {PoASecurityModule} from
    "../../src/contracts/ValidatorManager/SecurityModule/PoASecurityModule.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

import {ValidatorManagerSettings} from
    "../../src/interfaces/ValidatorManager/IBalancerValidatorManager.sol";
import {ICMInitializable} from "@avalabs/icm-contracts/utilities/ICMInitializable.sol";

import {PoAManager} from "@avalabs/icm-contracts/validator-manager/PoAManager.sol";
import {
    ValidatorManager as VM2,
    ValidatorManagerSettings as VM2Settings
} from "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";
import {
    Validator,
    ValidatorStatus
} from "@avalabs/icm-contracts/validator-manager/interfaces/IACP99Manager.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Script, console} from "forge-std/Script.sol";

/**
 * @title MigratePoAToBalancer
 * @notice Script to migrate validators from a PoAManager setup to BalancerValidatorManager with PoASecurityModule
 * @dev This script:
 *      1. Extracts active validators from an existing ValidatorManager
 *      2. Deploys a new BalancerValidatorManager with these validators pre-registered
 *      3. Sets up a PoASecurityModule to manage them
 */
contract MigratePoAToBalancer is Script {
    error NoActiveValidatorsFound();
    error ValidatorExtractionFailed();

    /**
     * @notice Extracts active validator node IDs from an existing ValidatorManager
     * @param existingValidatorManager The address of the existing ValidatorManager
     * @param validatorNodeIds An array of known validator node IDs to check
     * @return activeValidators Array of active validator node IDs
     */
    function extractActiveValidators(
        address existingValidatorManager,
        bytes[] memory validatorNodeIds
    ) public view returns (bytes[] memory activeValidators) {
        VM2 vm2 = VM2(existingValidatorManager);

        // Count active validators first
        uint256 activeCount = 0;
        for (uint256 i = 0; i < validatorNodeIds.length; i++) {
            bytes32 validationID = vm2.getNodeValidationID(validatorNodeIds[i]);

            // Check if validation ID exists (non-zero)
            if (validationID != bytes32(0)) {
                try vm2.getValidator(validationID) returns (Validator memory validator) {
                    // Check if validator is active
                    if (validator.status == ValidatorStatus.Active) {
                        activeCount++;
                    }
                } catch {
                    // Skip if getValidator fails
                    continue;
                }
            }
        }

        if (activeCount == 0) {
            revert NoActiveValidatorsFound();
        }

        // Now collect the active validators
        activeValidators = new bytes[](activeCount);
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < validatorNodeIds.length; i++) {
            bytes32 validationID = vm2.getNodeValidationID(validatorNodeIds[i]);

            if (validationID != bytes32(0)) {
                try vm2.getValidator(validationID) returns (Validator memory validator) {
                    if (validator.status == ValidatorStatus.Active) {
                        activeValidators[currentIndex] = validatorNodeIds[i];
                        currentIndex++;
                    }
                } catch {
                    continue;
                }
            }
        }

        return activeValidators;
    }

    /**
     * @notice Main migration function
     * @param existingValidatorManager Address of the existing ValidatorManager
     * @param existingPoAManager Address of the existing PoAManager (optional, for ownership transfer)
     * @param knownValidatorNodeIds Array of known validator node IDs to check for active status
     * @param securityModuleMaxWeight Maximum weight for the PoA security module
     * @return balancer The deployed BalancerValidatorManager address
     * @return securityModule The deployed PoASecurityModule address
     * @return newVMAddress The new ValidatorManager address
     */
    function run(
        address existingValidatorManager,
        address existingPoAManager,
        bytes[] calldata knownValidatorNodeIds,
        uint64 securityModuleMaxWeight
    ) external returns (address balancer, address securityModule, address newVMAddress) {
        console.log("Starting PoA to Balancer migration...");
        console.log("Existing ValidatorManager:", existingValidatorManager);

        // Extract active validators from the existing ValidatorManager
        bytes[] memory activeValidators =
            extractActiveValidators(existingValidatorManager, knownValidatorNodeIds);

        console.log("Found active validators:", activeValidators.length);

        // Get configuration
        HelperConfig helperConfig = new HelperConfig();
        (
            uint256 proxyAdminOwnerKey,
            uint256 validatorManagerOwnerKey,
            bytes32 subnetID,
            uint64 churnPeriodSeconds,
            uint8 maximumChurnPercentage
        ) = helperConfig.activeNetworkConfig();

        address proxyAdminOwnerAddress = vm.addr(proxyAdminOwnerKey);
        address validatorManagerOwnerAddress = vm.addr(validatorManagerOwnerKey);

        vm.startBroadcast(proxyAdminOwnerKey);

        // 1) Deploy new V2 VM (proxy)
        VM2Settings memory vmSettings = VM2Settings({
            admin: validatorManagerOwnerAddress,
            subnetID: subnetID,
            churnPeriodSeconds: churnPeriodSeconds,
            maximumChurnPercentage: maximumChurnPercentage
        });

        VM2 vmImpl = new VM2(ICMInitializable.Allowed);
        newVMAddress = UnsafeUpgrades.deployTransparentProxy(
            address(vmImpl), proxyAdminOwnerAddress, abi.encodeCall(VM2.initialize, (vmSettings))
        );

        console.log("Deployed new ValidatorManager:", newVMAddress);

        // 2) Initialize validator set in the new VM
        // Note: In a real migration, you would need the proper ConversionData and messageIndex
        // This is a placeholder - the actual initialization would come from P-Chain conversion
        console.log(
            "Note: New ValidatorManager needs validator set initialization via P-Chain conversion"
        );

        // 3) Deploy Balancer implementation
        BalancerValidatorManager balancerImpl = new BalancerValidatorManager();

        // 3) Deploy Balancer proxy without initialization
        balancer =
            UnsafeUpgrades.deployTransparentProxy(address(balancerImpl), proxyAdminOwnerAddress, "");

        console.log("Deployed BalancerValidatorManager:", balancer);

        // 4) Deploy PoASecurityModule
        securityModule = address(new PoASecurityModule(balancer, validatorManagerOwnerAddress));
        console.log("Deployed PoASecurityModule:", securityModule);

        vm.stopBroadcast();

        // 5) Transfer VM ownership to Balancer proxy
        vm.startBroadcast(validatorManagerOwnerKey);
        VM2(newVMAddress).transferOwnership(balancer);
        vm.stopBroadcast();

        // 6) Initialize the Balancer with migrated validators
        vm.startBroadcast(proxyAdminOwnerKey);
        BalancerValidatorManagerSettings memory balancerSettings = BalancerValidatorManagerSettings({
            baseSettings: ValidatorManagerSettings({
                subnetID: subnetID,
                churnPeriodSeconds: churnPeriodSeconds,
                maximumChurnPercentage: maximumChurnPercentage
            }),
            initialOwner: validatorManagerOwnerAddress,
            initialSecurityModule: securityModule,
            initialSecurityModuleMaxWeight: securityModuleMaxWeight,
            migratedValidators: activeValidators // Pass the extracted active validators
        });

        BalancerValidatorManager(balancer).initialize(balancerSettings, newVMAddress);
        console.log(
            "Initialized BalancerValidatorManager with",
            activeValidators.length,
            "migrated validators"
        );

        vm.stopBroadcast();

        // 7) Optional: If PoAManager exists, transfer its ValidatorManager ownership
        if (existingPoAManager != address(0)) {
            console.log("Transferring ownership from PoAManager to new setup...");
            // Note: This would need to be called by the PoAManager owner
            // PoAManager(existingPoAManager).transferValidatorManagerOwnership(newBalancer);
            console.log("Note: PoAManager owner must manually transfer ValidatorManager ownership");
        }

        console.log("\nMigration completed successfully!");
        console.log("- BalancerValidatorManager:", balancer);
        console.log("- PoASecurityModule:", securityModule);
        console.log("- New ValidatorManager:", newVMAddress);
        console.log("- Migrated validators:", activeValidators.length);

        return (balancer, securityModule, newVMAddress);
    }

    /**
     * @notice Alternative run function that automatically discovers validators
     * @dev This requires events or additional on-chain data to discover all validators
     */
    function runWithAutoDiscovery(
        address existingValidatorManager,
        address existingPoAManager,
        uint64 securityModuleMaxWeight
    ) external returns (address balancer, address securityModule, address newVMAddress) {
        // This would require querying events or having an enumerable validator set
        // For now, this is a placeholder for future enhancement
        revert("Auto-discovery not yet implemented - please provide validator node IDs");
    }
}

// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {ValidatorManager} from "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";
import {
    Validator,
    ValidatorStatus
} from "@avalabs/icm-contracts/validator-manager/interfaces/IACP99Manager.sol";
import {Script, console} from "forge-std/Script.sol";

/**
 * @title ExtractValidators
 * @notice Utility script to extract and display validator information from an existing ValidatorManager
 * @dev This script helps identify active validators that need to be migrated
 */
contract ExtractValidators is Script {
    /**
     * @notice Checks a list of known validator node IDs and returns their status
     * @param validatorManager Address of the ValidatorManager to query
     * @param nodeIds Array of node IDs to check
     */
    function run(address validatorManager, bytes[] calldata nodeIds) external view {
        console.log("Extracting validator information from:", validatorManager);
        console.log("Checking");
        console.log(nodeIds.length);
        console.log("node IDs...\n");

        ValidatorManager validatorMgr = ValidatorManager(validatorManager);

        uint256 activeCount = 0;
        uint256 inactiveCount = 0;
        uint256 notFoundCount = 0;

        for (uint256 i = 0; i < nodeIds.length; i++) {
            console.log("Node ID", i, ":");
            console.logBytes(nodeIds[i]);

            bytes32 validationID = validatorMgr.getNodeValidationID(nodeIds[i]);

            if (validationID == bytes32(0)) {
                console.log("  Status: NOT FOUND (no validation ID)");
                notFoundCount++;
            } else {
                console.log("  Validation ID:", vm.toString(validationID));

                try validatorMgr.getValidator(validationID) returns (Validator memory validator) {
                    if (validator.status == ValidatorStatus.Active) {
                        console.log("  Status: ACTIVE");
                        console.log("  Weight:", validator.weight);
                        console.log("  Start time:", validator.startTime);
                        activeCount++;
                    } else if (validator.status == ValidatorStatus.Completed) {
                        console.log("  Status: COMPLETED");
                        console.log("  End time:", validator.endTime);
                        inactiveCount++;
                    } else if (validator.status == ValidatorStatus.PendingAdded) {
                        console.log("  Status: PENDING ADDED");
                        inactiveCount++;
                    } else if (validator.status == ValidatorStatus.PendingRemoved) {
                        console.log("  Status: PENDING REMOVED");
                        inactiveCount++;
                    } else {
                        console.log("  Status: UNKNOWN");
                        inactiveCount++;
                    }
                } catch {
                    console.log("  Status: ERROR (could not fetch validator data)");
                    notFoundCount++;
                }
            }
            console.log("");
        }

        console.log("Summary:");
        console.log("- Active validators:", activeCount);
        console.log("- Inactive validators:", inactiveCount);
        console.log("- Not found:", notFoundCount);
        console.log("- Total checked:", nodeIds.length);

        if (activeCount > 0) {
            console.log("\nActive validators found! These should be included in the migration.");
        } else {
            console.log("\nNo active validators found in the provided list.");
        }
    }

    /**
     * @notice Extracts only active validator node IDs and formats them for use
     * @param validatorManager Address of the ValidatorManager to query
     * @param nodeIds Array of node IDs to check
     * @return activeNodeIds Array containing only active validator node IDs
     */
    function extractActive(
        address validatorManager,
        bytes[] calldata nodeIds
    ) external view returns (bytes[] memory activeNodeIds) {
        ValidatorManager validatorMgr = ValidatorManager(validatorManager);

        // First pass: count active validators
        uint256 activeCount = 0;
        for (uint256 i = 0; i < nodeIds.length; i++) {
            bytes32 validationID = validatorMgr.getNodeValidationID(nodeIds[i]);
            if (validationID != bytes32(0)) {
                try validatorMgr.getValidator(validationID) returns (Validator memory validator) {
                    if (validator.status == ValidatorStatus.Active) {
                        activeCount++;
                    }
                } catch {}
            }
        }

        // Second pass: collect active validator node IDs
        activeNodeIds = new bytes[](activeCount);
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < nodeIds.length; i++) {
            bytes32 validationID = validatorMgr.getNodeValidationID(nodeIds[i]);
            if (validationID != bytes32(0)) {
                try validatorMgr.getValidator(validationID) returns (Validator memory validator) {
                    if (validator.status == ValidatorStatus.Active) {
                        activeNodeIds[currentIndex] = nodeIds[i];
                        currentIndex++;
                    }
                } catch {}
            }
        }

        console.log("Extracted", activeCount, "active validators");
        return activeNodeIds;
    }

    /**
     * @notice Extracts node IDs that are Active OR PendingAdded (weight > 0)
     * @dev Use this for Balancer migration to match l1TotalWeight().
     */
    function extractActiveOrPendingAdded(
        address validatorManager,
        bytes[] calldata nodeIds
    ) external view returns (bytes[] memory selectedNodeIds) {
        ValidatorManager validatorMgr = ValidatorManager(validatorManager);

        uint256 count;
        for (uint256 i = 0; i < nodeIds.length; i++) {
            bytes32 vid = validatorMgr.getNodeValidationID(nodeIds[i]);
            if (vid == bytes32(0)) {
                continue;
            }
            try validatorMgr.getValidator(vid) returns (Validator memory v) {
                if (
                    (v.status == ValidatorStatus.Active || v.status == ValidatorStatus.PendingAdded)
                        && v.weight > 0
                ) {
                    count++;
                }
            } catch {}
        }

        selectedNodeIds = new bytes[](count);
        uint256 j;
        for (uint256 i = 0; i < nodeIds.length; i++) {
            bytes32 vid = validatorMgr.getNodeValidationID(nodeIds[i]);
            if (vid == bytes32(0)) {
                continue;
            }
            try validatorMgr.getValidator(vid) returns (Validator memory v) {
                if (
                    (v.status == ValidatorStatus.Active || v.status == ValidatorStatus.PendingAdded)
                        && v.weight > 0
                ) {
                    selectedNodeIds[j++] = nodeIds[i];
                }
            } catch {}
        }
    }
}

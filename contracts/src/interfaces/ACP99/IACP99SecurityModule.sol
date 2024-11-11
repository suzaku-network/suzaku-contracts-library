// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

/*
 * @title IACP99SecurityModule
 * @author ADDPHO
 * @notice The IACP99SecurityModule interface is the interface for the ACP99 security modules.
 * @custom:security-contact security@suzaku.network
 */
interface IACP99SecurityModule {
    /**
     * @notice Information about a validator registration
     * @param nodeID The NodeID of the validator node
     * @param validationID The ValidationID of the validation
     * @param weight The initial weight assigned to the validator
     * @param startTime The timestamp when the validation started
     */
    struct ValidatorRegistrationInfo {
        bytes32 nodeID;
        bytes32 validationID;
        uint64 weight;
        uint64 startTime;
    }

    /**
     * @notice Information about a validator's uptime
     * @param activeSeconds The total number of seconds the validator was active
     * @param uptimeSeconds The total number of seconds the validator was online
     * @param activeWeightSeconds The total weight x seconds the validator was active
     * @param uptimeWeightSeconds The total weight x seconds the validator was online
     */
    struct ValidatorUptimeInfo {
        uint64 activeSeconds;
        uint64 uptimeSeconds;
        uint256 activeWeightSeconds;
        uint256 uptimeWeightSeconds;
    }

    /**
     * @notice Information about a change in a validator's weight
     * @param nodeID The NodeID of the validator node
     * @param validationID The ValidationID of the validation
     * @param nonce A sequential number to order weight changes
     * @param newWeight The new weight assigned to the validator
     * @param uptime The uptime information for the validator
     */
    struct ValidatorWeightChangeInfo {
        bytes32 nodeID;
        bytes32 validationID;
        uint64 nonce;
        uint64 newWeight;
        ValidatorUptimeInfo uptimeInfo;
    }

    error ACP99SecurityModule__ZeroAddressManager();
    error ACP99SecurityModule__OnlyManager(address sender, address manager);

    /// @notice Get the address of the ACP99Manager contract secured by this module
    function getManagerAddress() external view returns (address);

    /**
     * @notice Handle a validator registration
     * @param validatorInfo The information about the validator
     */
    function handleValidatorRegistration(
        ValidatorRegistrationInfo memory validatorInfo
    ) external;

    /**
     * @notice Handle a validator weight change
     * @param weightChangeInfo The information about the validator weight change
     */
    function handleValidatorWeightChange(
        ValidatorWeightChangeInfo memory weightChangeInfo
    ) external;
}

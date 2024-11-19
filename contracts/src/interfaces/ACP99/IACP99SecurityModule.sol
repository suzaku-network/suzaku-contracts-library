// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {IACP99Manager, ValidatorUptimeInfo} from "./IACP99Manager.sol";

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

/*
 * @title IACP99SecurityModule
 * @author ADDPHO
 * @notice The IACP99SecurityModule interface is the interface for the ACP99 security modules.
 * @custom:security-contact security@suzaku.network
 */
interface IACP99SecurityModule {
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

// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {IBalancerValidatorManager} from
    "../../../interfaces/ValidatorManager/IBalancerValidatorManager.sol";
// IPoAValidatorManager doesn't exist in v2.1 - removed import
import {ConversionData} from "@avalabs/icm-contracts/validator-manager/interfaces/IACP99Manager.sol";

import {ValidatorRegistrationInput} from
    "../../../interfaces/ValidatorManager/IBalancerValidatorManager.sol";
import {Ownable} from "@openzeppelin/contracts@5.0.2/access/Ownable.sol";

/**
 * @dev PoA-style security module for the Balancer Validator Manager.
 * Allows owner-only control over validator management operations.
 *
 * @custom:security-contact security@suzaku.network
 */
contract PoASecurityModule is Ownable {
    error ZeroAddress();

    IBalancerValidatorManager public immutable balancerValidatorManager;

    constructor(
        address balancerValidatorManagerAddress,
        address initialOwner
    ) Ownable(initialOwner) {
        if (balancerValidatorManagerAddress == address(0)) {
            revert ZeroAddress();
        }

        balancerValidatorManager = IBalancerValidatorManager(balancerValidatorManagerAddress);
    }

    /// @notice Initializes the validator set by delegating to the Balancer
    function initializeValidatorSet(
        ConversionData calldata conversionData,
        uint32 messageIndex
    ) external {
        balancerValidatorManager.initializeValidatorSet(conversionData, messageIndex);
    }

    /// @notice Resends the register validator message
    function resendRegisterValidatorMessage(
        bytes32 validationID
    ) external {
        balancerValidatorManager.resendRegisterValidatorMessage(validationID);
    }

    /// @notice Initiates validator registration (owner only)
    function initializeValidatorRegistration(
        ValidatorRegistrationInput calldata registrationInput,
        uint64 weight
    ) external onlyOwner returns (bytes32 validationID) {
        return balancerValidatorManager.initializeValidatorRegistration(registrationInput, weight);
    }

    /// @notice Completes validator registration
    function completeValidatorRegistration(
        uint32 messageIndex
    ) external {
        balancerValidatorManager.completeValidatorRegistration(messageIndex);
    }

    /// @notice Initiates validator removal (owner only)
    function initializeEndValidation(
        bytes32 validationID
    ) external onlyOwner {
        balancerValidatorManager.initializeEndValidation(validationID);
    }

    /// @notice Resends the end validator message
    function resendEndValidatorMessage(
        bytes32 validationID
    ) external {
        balancerValidatorManager.resendEndValidatorMessage(validationID);
    }

    /// @notice Completes validator removal
    function completeEndValidation(
        uint32 messageIndex
    ) external {
        balancerValidatorManager.completeEndValidation(messageIndex);
    }
}

// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {IBalancerValidatorManager} from
    "../../../interfaces/ValidatorManager/IBalancerValidatorManager.sol";
import {IPoAValidatorManager} from
    "@avalabs/icm-contracts/validator-manager/interfaces/IPoAValidatorManager.sol";
import {
    ConversionData,
    IValidatorManager,
    ValidatorRegistrationInput
} from "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManager.sol";
import {Ownable} from "@openzeppelin/contracts@5.0.2/access/Ownable.sol";

/**
 * @dev Implementation of the {IPoAValidatorManager} interface.
 *
 * @custom:security-contact https://github.com/ava-labs/teleporter/blob/main/SECURITY.md
 */
contract PoASecurityModule is IPoAValidatorManager, Ownable {
    error ZeroAddress();

    IBalancerValidatorManager public immutable balancerValidatorManager;

    constructor(address balancerValidatorManager_, address initialOwner) Ownable(initialOwner) {
        if (balancerValidatorManager_ == address(0)) {
            revert ZeroAddress();
        }

        balancerValidatorManager = IBalancerValidatorManager(balancerValidatorManager_);
    }

    /// @inheritdoc IValidatorManager
    function initializeValidatorSet(
        ConversionData calldata conversionData,
        uint32 messageIndex
    ) external onlyOwner {
        balancerValidatorManager.initializeValidatorSet(conversionData, messageIndex);
    }

    /// @inheritdoc IValidatorManager
    function resendRegisterValidatorMessage(
        bytes32 validationID
    ) external onlyOwner {
        balancerValidatorManager.resendRegisterValidatorMessage(validationID);
    }

    /// @inheritdoc IPoAValidatorManager
    function initializeValidatorRegistration(
        ValidatorRegistrationInput calldata registrationInput,
        uint64 weight
    ) external onlyOwner returns (bytes32 validationID) {
        return balancerValidatorManager.initializeValidatorRegistration(registrationInput, weight);
    }

    /// @inheritdoc IValidatorManager
    function completeValidatorRegistration(
        uint32 messageIndex
    ) external onlyOwner {
        balancerValidatorManager.completeValidatorRegistration(messageIndex);
    }

    /// @inheritdoc IPoAValidatorManager
    function initializeEndValidation(
        bytes32 validationID
    ) external override onlyOwner {
        balancerValidatorManager.initializeEndValidation(validationID);
    }

    /// @inheritdoc IValidatorManager
    function resendEndValidatorMessage(
        bytes32 validationID
    ) external onlyOwner {
        balancerValidatorManager.resendEndValidatorMessage(validationID);
    }

    /// @inheritdoc IValidatorManager
    function completeEndValidation(
        uint32 messageIndex
    ) external {
        balancerValidatorManager.completeEndValidation(messageIndex);
    }
}

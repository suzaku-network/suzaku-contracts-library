// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {
    IValidatorManager,
    ValidatorManagerSettings,
    ValidatorRegistrationInput
} from "@avalabs/teleporter/validator-manager/interfaces/IValidatorManager.sol";

/**
 * @dev Balancer Validator Manager settings, used to initialize the Balancer Validator Manager
 */
struct BalancerValidatorManagerSettings {
    ValidatorManagerSettings baseSettings;
    address initialOwner;
    address initialSecurityModule;
    uint64 initialSecurityModuleMaxWeight;
    bytes[] migratedValidators;
}

/**
 * @title IBalancerValidatorManager
 * @author ADDPHO
 * @notice Interface for Balancer Validator Manager contracts
 * @custom:security-contact security@suzaku.network
 */
interface IBalancerValidatorManager is IValidatorManager {
    /**
     * @notice Emitted when a security module is registered, updated, or removed (maxWeight = 0)
     * @param securityModule The address of the security module
     * @param maxWeight The maximum total weight allowed for validators managed by this module
     */
    event SetupSecurityModule(address indexed securityModule, uint64 maxWeight);

    error BalancerValidatorManager__SecurityModuleAlreadyRegistered(address securityModule);
    error BalancerValidatorManager__SecurityModuleNotRegistered(address securityModule);
    error BalancerValidatorManager__SecurityModuleMaxWeightExceeded(
        address securityModule, uint64 weight, uint64 maxWeight
    );
    error BalancerValidatorManager__SecurityModuleNewMaxWeightLowerThanCurrentWeight(
        address securityModule, uint64 newMaxWeight, uint64 currentWeight
    );
    error BalancerValidatorManager__NewWeightIsZero();
    error BalancerValidatorManager__ValidatorNotBelongingToSecurityModule(
        bytes32 validationID, address securityModule
    );
    error BalancerValidatorManager__PendingWeightUpdate(bytes32 validationID);
    error BalancerValidatorManager__NoPendingWeightUpdate(bytes32 validationID);
    error BalancerValidatorManager__InvalidNonce(uint64 nonce);

    /**
     * @notice Returns the ValidatorManager churn period in seconds
     * @return churnPeriodSeconds The churn period in seconds
     */
    function getChurnPeriodSeconds() external view returns (uint64 churnPeriodSeconds);

    /**
     * @notice Returns the list of registered security modules
     * @return securityModules The list of registered security modules
     */
    function getSecurityModules() external view returns (address[] memory securityModules);

    /**
     * @notice Returns the weight associated with a security module
     * @param securityModule The address of the security module
     * @return weight The weight of the security module
     */
    function getSecurityModuleWeights(
        address securityModule
    ) external view returns (uint64 weight, uint64 maxWeight);

    /**
     * @notice Returns whether a validator has a pending weight update
     * @param validationID The ID of the validator
     * @return Whether the validator has a pending weight update
     */
    function isValidatorPendingWeightUpdate(
        bytes32 validationID
    ) external view returns (bool);

    /**
     * @notice Registers a new security module with a maximum weight limit
     * @param securityModule The address of the security module to register
     * @param maxWeight The maximum total weight allowed for validators managed by this module
     */
    function setupSecurityModule(address securityModule, uint64 maxWeight) external;

    /**
     * @notice Begins the validator registration process, and sets the {weight} of the validator.
     * @param registrationInput The inputs for a validator registration.
     * @param weight The weight of the validator being registered.
     * @return validationID The ID of the validator registration.
     */
    function initializeValidatorRegistration(
        ValidatorRegistrationInput calldata registrationInput,
        uint64 weight
    ) external returns (bytes32 validationID);

    /**
     * @notice Begins the process of ending an active validation period. The validation period must have been previously
     * started by a successful call to {completeValidatorRegistration} with the given validationID.
     * @param validationID The ID of the validation period being ended.
     */
    function initializeEndValidation(
        bytes32 validationID
    ) external;

    /**
     * @notice Initiates a weight update for a validator
     * @param validationID The ID of the validation period being updated
     * @param newWeight The new weight to set for the validator
     */
    function initializeValidatorWeightUpdate(bytes32 validationID, uint64 newWeight) external;

    /**
     * @notice Completes a pending validator weight update after P-Chain confirmation
     * @param validationID The ID of the validation period being updated
     * @param messageIndex The index of the Warp message containing the weight update confirmation
     */
    function completeValidatorWeightUpdate(bytes32 validationID, uint32 messageIndex) external;
}

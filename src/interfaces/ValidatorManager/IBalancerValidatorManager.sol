// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {
    ValidatorChurnPeriod,
    ValidatorManagerSettings
} from "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";
import {
    PChainOwner,
    Validator
} from "@avalabs/icm-contracts/validator-manager/interfaces/IACP99Manager.sol";
import {IValidatorManager} from
    "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManager.sol";

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
    event SetUpSecurityModule(address indexed securityModule, uint64 maxWeight);

    error BalancerValidatorManager__MigratedValidatorsTotalWeightMismatch(
        uint64 migratedValidatorsTotalWeight, uint64 currentL1TotalWeight
    );
    error BalancerValidatorManager__SecurityModuleAlreadyRegistered(address securityModule);
    error BalancerValidatorManager__SecurityModuleNotRegistered(address securityModule);
    error BalancerValidatorManager__SecurityModuleMaxWeightExceeded(
        address securityModule, uint64 weight, uint64 maxWeight
    );
    error BalancerValidatorManager__SecurityModuleNewMaxWeightLowerThanCurrentWeight(
        address securityModule, uint64 newMaxWeight, uint64 currentWeight
    );
    error BalancerValidatorManager__InitialSecurityModuleMaxWeightLowerThanTotalWeight(
        address securityModule, uint64 initialMaxWeight, uint64 totalWeight
    );
    error BalancerValidatorManager__NewWeightIsZero();
    error BalancerValidatorManager__ValidatorNotBelongingToSecurityModule(
        bytes32 validationID, address securityModule
    );
    error BalancerValidatorManager__PendingWeightUpdate(bytes32 validationID);
    error BalancerValidatorManager__NoPendingWeightUpdate(bytes32 validationID);
    error BalancerValidatorManager__InvalidNonce(uint64 nonce);
    error BalancerValidatorManager__ValidatorAlreadyMigrated(bytes32 validationID);

    /**
     * @notice Returns the maximum churn rate per churn period (in percentage)
     * @return maximumChurnPercentage The maximum churn percentage
     */
    function getMaximumChurnPercentage() external view returns (uint64 maximumChurnPercentage);

    /**
     * @notice Returns the current churn period
     * @return churnPeriod The current churn period
     */
    function getCurrentChurnPeriod()
        external
        view
        returns (ValidatorChurnPeriod memory churnPeriod);

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
    function setUpSecurityModule(address securityModule, uint64 maxWeight) external;

    /**
     * @notice Begins the validator registration process through a security module
     * @dev Can only be called by registered security modules
     * @param nodeID The nodeID of the validator being registered.
     * @param blsPublicKey The BLS public key of the validator.
     * @param remainingBalanceOwner The P-Chain owner for the remaining balance.
     * @param disableOwner The P-Chain owner that can disable the validator.
     * @param weight The weight of the validator being registered.
     * @return validationID The ID of the validator registration.
     */
    function initiateValidatorRegistrationWithSecurityModule(
        bytes memory nodeID,
        bytes memory blsPublicKey,
        PChainOwner memory remainingBalanceOwner,
        PChainOwner memory disableOwner,
        uint64 weight
    ) external returns (bytes32 validationID);

    /**
     * @notice Begins the process of ending an active validation period through a security module
     * @dev Can only be called by the security module that registered the validator
     * @param validationID The ID of the validation period being ended.
     * @return validator The validator that is being removed
     */
    function initiateValidatorRemovalWithSecurityModule(
        bytes32 validationID
    ) external returns (Validator memory validator);

    /**
     * @notice Initiates a weight update for a validator through a security module
     * @dev Can only be called by the security module that registered the validator
     * @param validationID The ID of the validation period being updated
     * @param newWeight The new weight to set for the validator
     * @return nonce The nonce of the weight update message
     * @return messageID The ID of the weight update message sent to P-Chain
     */
    function initiateValidatorWeightUpdateWithSecurityModule(
        bytes32 validationID,
        uint64 newWeight
    ) external returns (uint64 nonce, bytes32 messageID);

    /**
     * @notice Completes validator removal. Can only be called by the security module that registered the validator
     * @param messageIndex The index of the Warp message
     * @return validationID The ID of the removed validator
     */
    function completeValidatorRemovalWithSecurityModule(
        uint32 messageIndex
    ) external returns (bytes32 validationID);

    /**
     * @notice Completes validator registration. Can only be called by the security module that initiated the registration
     * @param messageIndex The index of the Warp message
     * @return validationID The ID of the registered validator
     */
    function completeValidatorRegistrationWithSecurityModule(
        uint32 messageIndex
    ) external returns (bytes32 validationID);

    /**
     * @notice Completes a pending validator weight update after P-Chain confirmation
     * @dev Can only be called by the security module that registered the validator
     * @param validationID The ID of the validation period being updated
     * @param messageIndex The index of the Warp message containing the weight update confirmation
     */
    function completeValidatorWeightUpdateWithSecurityModule(
        bytes32 validationID,
        uint32 messageIndex
    ) external;

    /**
     * @notice Resends a pending validator weight update message to the P-Chain
     * @param validationID The ID of the validation period being updated
     */
    function resendValidatorWeightUpdate(
        bytes32 validationID
    ) external;

    /**
     * @notice Resends a pending validator registration message to the P-Chain
     * @dev Can only be called by the security module that initiated the registration
     * @param validationID The ID of the validation period being registered
     */
    function resendRegisterValidatorMessageWithSecurityModule(
        bytes32 validationID
    ) external;

    /**
     * @notice Resends a validator removal message to the P-Chain
     * @dev Can only be called by the security module that registered the validator
     * @param validationID The ID of the validation period being removed
     */
    function resendValidatorRemovalMessageWithSecurityModule(
        bytes32 validationID
    ) external;
}

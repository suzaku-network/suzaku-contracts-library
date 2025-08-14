// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {IValidatorManager} from
    "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManager.sol";

import {ValidatorChurnPeriod} from "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";

import {
    PChainOwner,
    Validator
} from "@avalabs/icm-contracts/validator-manager/interfaces/IACP99Manager.sol";

/**
 * @dev Struct for validator registration inputs (v1 compatibility)
 */
struct ValidatorRegistrationInput {
    bytes nodeID;
    bytes blsPublicKey;
    uint64 registrationExpiry;
    PChainOwner remainingBalanceOwner;
    PChainOwner disableOwner;
}

/**
 * @dev Validator Manager settings (v1 compatibility structure)
 */
struct ValidatorManagerSettings {
    bytes32 subnetID;
    uint64 churnPeriodSeconds;
    uint8 maximumChurnPercentage;
}

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
    error BalancerValidatorManager__ZeroValidatorManagerAddress();
    error BalancerValidatorManager__ValidatorManagerNotOwnedByBalancer();
    error BalancerValidatorManager__InitialSecurityModuleRequiredForMigration();
    error BalancerValidatorManager__MigratedValidatorsRequired();
    error BalancerValidatorManager__InvalidWarpMessage();
    error BalancerValidatorManager__InconsistentNonce();

    /**
     * @notice Returns the ValidatorManager churn period in seconds
     * @return churnPeriodSeconds The churn period in seconds
     */
    function getChurnPeriodSeconds() external view returns (uint64 churnPeriodSeconds);

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
     * @notice Returns the security module that manages a validator
     * @param validationID The ID of the validator
     * @return The security module address (address(0) if unassigned)
     */
    function getValidatorSecurityModule(
        bytes32 validationID
    ) external view returns (address);

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
     * @notice Resends a pending validator weight update message to the P-Chain
     * @param validationID The ID of the validation period being updated
     */
    function resendValidatorWeightUpdate(
        bytes32 validationID
    ) external;

    /**
     * @notice Resends a validator registration message
     * @param validationID The ID of the validation period
     */
    function resendRegisterValidatorMessage(
        bytes32 validationID
    ) external;
}

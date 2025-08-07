// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {
    BalancerValidatorManagerSettings,
    IBalancerValidatorManager
} from "../../interfaces/ValidatorManager/IBalancerValidatorManager.sol";

import {ICMInitializable} from "@avalabs/icm-contracts/utilities/ICMInitializable.sol";
import {
    ValidatorChurnPeriod,
    ValidatorManager,
    ValidatorManagerSettings
} from "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";
import {ValidatorMessages} from "@avalabs/icm-contracts/validator-manager/ValidatorMessages.sol";
import {
    IACP99Manager,
    PChainOwner,
    Validator,
    ValidatorStatus
} from "@avalabs/icm-contracts/validator-manager/interfaces/IACP99Manager.sol";
import {IValidatorManager} from
    "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManager.sol";

import {EnumerableMap} from "@openzeppelin/contracts@5.0.2/utils/structs/EnumerableMap.sol";

/**
 * @title BalancerValidatorManager
 * @author ADDPHO
 * @notice The Balancer Validator Manager contract allows to balance the weight of an L1 between multiple security modules.
 * @custom:security-contact security@suzaku.network
 * @custom:oz-upgrades-unsafe-allow external-library-linking
 * @custom:oz-upgrades-from PoAValidatorManager
 */
contract BalancerValidatorManager is IBalancerValidatorManager, ValidatorManager {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    /// @custom:storage-location erc7201:suzaku.storage.BalancerValidatorManager
    struct BalancerValidatorManagerStorage {
        /// @notice The registered security modules along with their maximum weight
        EnumerableMap.AddressToUintMap securityModules;
        /// @notice The total weight of all validators for a given security module
        mapping(address securityModule => uint64 weight) securityModuleWeight;
        /// @notice The security module to which each validator belongs
        mapping(bytes32 validationID => address securityModule) validatorSecurityModule;
        /// @notice Validators pending weight updates
        mapping(bytes32 validationID => bytes32 messageID) validatorPendingWeightUpdate;
    }

    // keccak256(abi.encode(uint256(keccak256("suzaku.storage.BalancerValidatorManager")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 public constant BALANCER_VALIDATOR_MANAGER_STORAGE_LOCATION =
        0x9d2d7650aa35ca910e5b713f6b3de6524a06fbcb31ffc9811340c6f331a23400;

    // solhint-disable func-name-mixedcase, ordering
    function _getBalancerValidatorManagerStorage()
        private
        pure
        returns (BalancerValidatorManagerStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := BALANCER_VALIDATOR_MANAGER_STORAGE_LOCATION
        }
    }

    modifier onlySecurityModule() {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();

        if (!$.securityModules.contains(msg.sender)) {
            revert BalancerValidatorManager__SecurityModuleNotRegistered(msg.sender);
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() ValidatorManager(ICMInitializable.Allowed) {
        _disableInitializers();
    }

    /**
     * @notice Initialize the Balancer Validator Manager
     * @dev This function is reinitializer(2) because it is upgrated from PoAValidatorManager
     * https://github.com/ava-labs/icm-contracts/blob/validator-manager-v1.0.0/contracts/validator-manager/PoAValidatorManager.sol
     * @param settings The settings for the Balancer Validator Manager
     */
    function initialize(
        BalancerValidatorManagerSettings calldata settings
    ) external reinitializer(2) {
        __BalancerValidatorManager_init(settings);
    }

    function __BalancerValidatorManager_init(
        BalancerValidatorManagerSettings calldata settings
    ) internal onlyInitializing {
        __ValidatorManager_init(settings.baseSettings);
        // __Ownable_init already called by __ValidatorManager_init with settings.baseSettings.admin
        __BalancerValidatorManager_init_unchained(
            settings.initialSecurityModule,
            settings.initialSecurityModuleMaxWeight,
            settings.migratedValidators
        );
    }

    function __BalancerValidatorManager_init_unchained(
        address initialSecurityModule,
        uint64 initialSecurityModuleMaxWeight,
        bytes[] calldata migratedValidators
    ) internal onlyInitializing {
        ValidatorManager.ValidatorManagerStorage storage vms = _getValidatorManagerStorage();

        // Ensure initial security module max weight is sufficient
        if (initialSecurityModuleMaxWeight < vms._churnTracker.totalWeight) {
            revert BalancerValidatorManager__InitialSecurityModuleMaxWeightLowerThanTotalWeight(
                initialSecurityModule, initialSecurityModuleMaxWeight, vms._churnTracker.totalWeight
            );
        }

        _setUpSecurityModule(initialSecurityModule, initialSecurityModuleMaxWeight);
        _migrateValidators(initialSecurityModule, migratedValidators);
    }

    // solhint-enable func-name-mixedcase

    /// @inheritdoc IBalancerValidatorManager
    function setUpSecurityModule(address securityModule, uint64 maxWeight) external onlyOwner {
        _setUpSecurityModule(securityModule, maxWeight);
    }

    /// @inheritdoc IBalancerValidatorManager
    function initiateValidatorRegistrationWithSecurityModule(
        bytes memory nodeID,
        bytes memory blsPublicKey,
        PChainOwner memory remainingBalanceOwner,
        PChainOwner memory disableOwner,
        uint64 weight
    ) external override onlySecurityModule returns (bytes32 validationID) {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();

        validationID = _initiateValidatorRegistration(
            nodeID, blsPublicKey, remainingBalanceOwner, disableOwner, weight
        );

        // Update the security module weight
        uint64 newSecurityModuleWeight = $.securityModuleWeight[msg.sender] + weight;
        _updateSecurityModuleWeight(msg.sender, newSecurityModuleWeight);

        $.validatorSecurityModule[validationID] = msg.sender;

        return validationID;
    }

    /// @inheritdoc IBalancerValidatorManager
    function initiateValidatorRemovalWithSecurityModule(
        bytes32 validationID
    ) external override onlySecurityModule returns (Validator memory validator) {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();

        // Ensure the validator weight is not being updated
        if ($.validatorPendingWeightUpdate[validationID] != 0) {
            revert BalancerValidatorManager__PendingWeightUpdate(validationID);
        }

        _checkValidatorSecurityModule(validationID, msg.sender);

        // Get validator before state mutation
        validator = getValidator(validationID);

        _initiateValidatorRemoval(validationID);

        // Update the security module weight
        uint64 newSecurityModuleWeight = $.securityModuleWeight[msg.sender] - validator.weight;
        _updateSecurityModuleWeight(msg.sender, newSecurityModuleWeight);

        return validator;
    }

    /* -------------------------------------------------------------------------- */
    /*  INTERNAL helpers – clone the base logic without `onlyOwner`               */
    /* -------------------------------------------------------------------------- */

    // copy body of ValidatorManager.completeValidatorRegistration
    function _completeRegistrationInternal(
        uint32 messageIndex
    ) internal returns (bytes32) {
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();
        (bytes32 validationID, bool validRegistration) = ValidatorMessages
            .unpackL1ValidatorRegistrationMessage(_getPChainWarpMessage(messageIndex).payload);

        if (!validRegistration) {
            revert UnexpectedRegistrationStatus(validRegistration);
        }
        // The initial validator set must have been set already to have pending register validation messages.
        if ($._pendingRegisterValidationMessages[validationID].length == 0) {
            revert InvalidValidationID(validationID);
        }
        if ($._validationPeriods[validationID].status != ValidatorStatus.PendingAdded) {
            revert InvalidValidatorStatus($._validationPeriods[validationID].status);
        }

        delete $._pendingRegisterValidationMessages[validationID];
        $._validationPeriods[validationID].status = ValidatorStatus.Active;
        $._validationPeriods[validationID].startTime = uint64(block.timestamp);
        emit CompletedValidatorRegistration(validationID, $._validationPeriods[validationID].weight);

        return validationID;
    }

    // copy body of ValidatorManager.completeValidatorRemoval
    function _completeRemovalInternal(
        uint32 messageIndex
    ) internal returns (bytes32 validationID, Validator memory validator) {
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();

        // Get the Warp message.
        (bytes32 _validationID, bool registered) = ValidatorMessages
            .unpackL1ValidatorRegistrationMessage(_getPChainWarpMessage(messageIndex).payload);
        if (registered) {
            revert UnexpectedRegistrationStatus(registered);
        }

        validationID = _validationID;
        validator = $._validationPeriods[validationID];

        // The validation status is PendingRemoved if validator removal was initiated with a call to {initiateValidatorRemoval}.
        // The validation status is PendingAdded if the validator was never registered on the P-Chain.
        // The initial validator set must have been set already to have pending validation messages.
        if (
            validator.status != ValidatorStatus.PendingRemoved
                && validator.status != ValidatorStatus.PendingAdded
        ) {
            revert InvalidValidatorStatus(validator.status);
        }

        if (validator.status == ValidatorStatus.PendingRemoved) {
            validator.status = ValidatorStatus.Completed;
        } else {
            // Remove the validator's weight from the total tracked weight, but don't track it as churn.
            $._churnTracker.totalWeight -= validator.weight;
            validator.status = ValidatorStatus.Invalidated;
        }
        // Remove the validator from the registered validators mapping.
        delete $._registeredValidators[validator.nodeID];

        // Update the validator.
        $._validationPeriods[validationID] = validator;

        // Emit event.
        emit CompletedValidatorRemoval(validationID);

        return (validationID, validator);
    }

    function completeValidatorRemovalWithSecurityModule(
        uint32 messageIndex
    ) external override onlySecurityModule returns (bytes32) {
        // auth: caller must match validator's module (reuse existing check)
        (bytes32 vid,) = ValidatorMessages.unpackL1ValidatorRegistrationMessage(
            _getPChainWarpMessage(messageIndex).payload
        );
        _checkValidatorSecurityModule(vid, msg.sender);

        (bytes32 validationID, Validator memory validator) = _completeRemovalInternal(messageIndex);

        // weight bookkeeping (existing code)
        if (validator.status == ValidatorStatus.Invalidated) {
            BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
            _updateSecurityModuleWeight(
                $.validatorSecurityModule[validationID],
                $.securityModuleWeight[msg.sender] - validator.weight
            );
        }
        return validationID;
    }

    function completeValidatorRegistrationWithSecurityModule(
        uint32 messageIndex
    ) external override onlySecurityModule returns (bytes32) {
        // auth: caller must match validator's module (reuse existing check)
        (bytes32 vid,) = ValidatorMessages.unpackL1ValidatorRegistrationMessage(
            _getPChainWarpMessage(messageIndex).payload
        );
        _checkValidatorSecurityModule(vid, msg.sender);
        return _completeRegistrationInternal(messageIndex);
    }

    /// @inheritdoc IBalancerValidatorManager
    function initiateValidatorWeightUpdateWithSecurityModule(
        bytes32 validationID,
        uint64 newWeight
    ) external override onlySecurityModule returns (uint64, bytes32) {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();

        // Check that the newWeight is greater than zero
        if (newWeight == 0) {
            revert BalancerValidatorManager__NewWeightIsZero();
        }

        // Get validator and ensure it's active
        Validator memory validator = getValidator(validationID);
        if (validator.status != ValidatorStatus.Active) {
            revert InvalidValidatorStatus(validator.status);
        }
        if ($.validatorPendingWeightUpdate[validationID] != 0) {
            revert BalancerValidatorManager__PendingWeightUpdate(validationID);
        }

        _checkValidatorSecurityModule(validationID, msg.sender);
        uint64 oldWeight = validator.weight;
        (uint64 nonce, bytes32 messageID) = _initiateValidatorWeightUpdate(validationID, newWeight);

        // Update the security module weight
        uint64 newSecurityModuleWeight = $.securityModuleWeight[msg.sender] + newWeight - oldWeight;
        _updateSecurityModuleWeight(msg.sender, newSecurityModuleWeight);

        $.validatorPendingWeightUpdate[validationID] = messageID;

        return (nonce, messageID);
    }

    /// @inheritdoc IBalancerValidatorManager
    function completeValidatorWeightUpdateWithSecurityModule(
        bytes32 validationID,
        uint32 messageIndex
    ) external override {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();

        // Verify the caller is the security module that registered this validator
        _checkValidatorSecurityModule(validationID, msg.sender);

        // Check that validator has a pending weight update
        if ($.validatorPendingWeightUpdate[validationID] == 0) {
            revert BalancerValidatorManager__NoPendingWeightUpdate(validationID);
        }

        // Call parent implementation to handle the weight update
        (bytes32 returnedValidationID,) = completeValidatorWeightUpdate(messageIndex);
        if (returnedValidationID != validationID) {
            revert InvalidValidationID(returnedValidationID);
        }

        // Clear the pending weight update
        delete $.validatorPendingWeightUpdate[validationID];
    }

    function resendValidatorWeightUpdate(
        bytes32 validationID
    ) external {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        Validator memory validator = getValidator(validationID);

        if (validator.status != ValidatorStatus.Active) {
            revert InvalidValidatorStatus(validator.status);
        }
        if ($.validatorPendingWeightUpdate[validationID] == 0) {
            revert BalancerValidatorManager__NoPendingWeightUpdate(validationID);
        }

        if (validator.sentNonce == 0) {
            revert InvalidValidationID(validationID);
        }

        // Submit the message to the Warp precompile.
        WARP_MESSENGER.sendWarpMessage(
            ValidatorMessages.packL1ValidatorWeightMessage(
                validationID, validator.sentNonce, validator.weight
            )
        );
    }

    function resendRegisterValidatorMessageWithSecurityModule(
        bytes32 validationID
    ) external override onlySecurityModule {
        _checkValidatorSecurityModule(validationID, msg.sender);

        // Check that the validator is pending registration
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();
        if ($._pendingRegisterValidationMessages[validationID].length == 0) {
            revert InvalidValidationID(validationID);
        }

        WARP_MESSENGER.sendWarpMessage($._pendingRegisterValidationMessages[validationID]);
    }

    function resendValidatorRemovalMessageWithSecurityModule(
        bytes32 validationID
    ) external override onlySecurityModule {
        _checkValidatorSecurityModule(validationID, msg.sender);
        Validator memory validator = getValidator(validationID);

        // Check that the validator is pending removal
        if (validator.status != ValidatorStatus.PendingRemoved) {
            revert InvalidValidatorStatus(validator.status);
        }

        WARP_MESSENGER.sendWarpMessage(
            ValidatorMessages.packL1ValidatorWeightMessage(validationID, validator.sentNonce, 0)
        );
    }

    /// @inheritdoc IBalancerValidatorManager
    function getMaximumChurnPercentage() external view returns (uint64 maximumChurnPercentage) {
        (, maximumChurnPercentage,) = getChurnTracker();
        return maximumChurnPercentage;
    }

    /// @inheritdoc IBalancerValidatorManager
    function getCurrentChurnPeriod()
        external
        view
        returns (ValidatorChurnPeriod memory churnPeriod)
    {
        (,, churnPeriod) = getChurnTracker();
        return churnPeriod;
    }

    /// @inheritdoc IBalancerValidatorManager
    function getSecurityModules() external view returns (address[] memory securityModules) {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();

        return $.securityModules.keys();
    }

    /// @inheritdoc IBalancerValidatorManager
    function getSecurityModuleWeights(
        address securityModule
    ) external view returns (uint64 weight, uint64 maxWeight) {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();

        weight = $.securityModuleWeight[securityModule];
        maxWeight = uint64($.securityModules.get(securityModule));

        return (weight, maxWeight);
    }

    /// @inheritdoc IBalancerValidatorManager
    function isValidatorPendingWeightUpdate(
        bytes32 validationID
    ) external view returns (bool) {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();

        return $.validatorPendingWeightUpdate[validationID] != 0;
    }

    function _checkValidatorSecurityModule(
        bytes32 validationID,
        address securityModule
    ) internal view {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();

        // If the validator has no associated security module, it is an initial validator
        // and can be managed by any security module
        if ($.validatorSecurityModule[validationID] == address(0)) {
            return;
        } else if ($.validatorSecurityModule[validationID] != securityModule) {
            revert BalancerValidatorManager__ValidatorNotBelongingToSecurityModule(
                validationID, securityModule
            );
        }
    }

    function _setUpSecurityModule(address securityModule, uint64 maxWeight) internal {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        uint64 currentWeight = $.securityModuleWeight[securityModule];

        if (maxWeight < currentWeight) {
            revert BalancerValidatorManager__SecurityModuleNewMaxWeightLowerThanCurrentWeight(
                securityModule, maxWeight, currentWeight
            );
        }

        if (maxWeight == 0) {
            if (!$.securityModules.remove(securityModule)) {
                revert BalancerValidatorManager__SecurityModuleNotRegistered(securityModule);
            }
        } else {
            $.securityModules.set(securityModule, uint256(maxWeight));
        }

        emit SetUpSecurityModule(securityModule, maxWeight);
    }

    function _updateSecurityModuleWeight(address securityModule, uint64 weight) internal {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        uint64 maxWeight = uint64($.securityModules.get(securityModule));

        if (weight > maxWeight) {
            revert BalancerValidatorManager__SecurityModuleMaxWeightExceeded(
                securityModule, weight, maxWeight
            );
        }

        $.securityModuleWeight[securityModule] = weight;
    }

    function _migrateValidators(
        address initialSecurityModule,
        bytes[] calldata migratedValidators
    ) internal {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();

        // Add the migrated validators to the initial security module
        uint64 migratedValidatorsTotalWeight = 0;
        for (uint256 i = 0; i < migratedValidators.length; i++) {
            bytes32 validationID = getNodeValidationID(migratedValidators[i]);

            // Ensure validator hasn't already been migrated
            if ($.validatorSecurityModule[validationID] != address(0)) {
                revert BalancerValidatorManager__ValidatorAlreadyMigrated(validationID);
            }

            Validator memory validator = getValidator(validationID);
            $.validatorSecurityModule[validationID] = initialSecurityModule;
            migratedValidatorsTotalWeight += validator.weight;
        }

        // Check that the migrated validators total weight equals the current L1 total weight
        uint64 totalWeight = l1TotalWeight();
        if (migratedValidatorsTotalWeight != totalWeight) {
            revert BalancerValidatorManager__MigratedValidatorsTotalWeightMismatch(
                migratedValidatorsTotalWeight, totalWeight
            );
        }

        // Update the initial security module weight directly since we've already validated the max weight
        $.securityModuleWeight[initialSecurityModule] = migratedValidatorsTotalWeight;
    }
}

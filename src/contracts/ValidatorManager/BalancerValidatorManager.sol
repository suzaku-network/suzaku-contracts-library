// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {
    BalancerValidatorManagerSettings,
    IBalancerValidatorManager
} from "../../interfaces/ValidatorManager/IBalancerValidatorManager.sol";
import {ValidatorManager} from "@avalabs/teleporter/validator-manager/ValidatorManager.sol";
import {ValidatorMessages} from "@avalabs/teleporter/validator-manager/ValidatorMessages.sol";
import {
    IValidatorManager,
    Validator,
    ValidatorManagerSettings,
    ValidatorRegistrationInput,
    ValidatorStatus
} from "@avalabs/teleporter/validator-manager/interfaces/IValidatorManager.sol";
import {OwnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable@5.0.2/access/OwnableUpgradeable.sol";
import {EnumerableMap} from "@openzeppelin/contracts@5.0.2/utils/structs/EnumerableMap.sol";

/**
 * @title BalancerValidatorManager
 * @author ADDPHO
 * @notice The Balancer Validator Manager contract allows to balance the weight of an L1 between multiple security modules.
 * @custom:oz-upgrades-unsafe-allow external-library-linking
 * @custom:oz-upgrades-from PoAValidatorManager
 */
contract BalancerValidatorManager is
    IBalancerValidatorManager,
    ValidatorManager,
    OwnableUpgradeable
{
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    /// @custom:storage-location erc7201:suzaku.storage.BalancerValidatorManager
    struct BalancerValidatorManagerStorage {
        /// @notice The total weight of the validators on the L1
        // TODO: Reenable this once this issue is fixed: https://github.com/ava-labs/teleporter/issues/645
        // uint256 l1TotalWeight;
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
    constructor() {
        _disableInitializers();
    }

    function initialize(
        BalancerValidatorManagerSettings calldata settings
    ) external reinitializer(2) {
        __BalancerValidatorManager_init(settings);
    }

    function __BalancerValidatorManager_init(
        BalancerValidatorManagerSettings calldata settings
    ) internal onlyInitializing {
        __ValidatorManager_init(settings.baseSettings);
        __Ownable_init(settings.initialOwner);
        __BalancerValidatorManager_init_unchained(
            settings.initialSecurityModule,
            settings.initialSecurityModuleMaxWeight,
            settings.migratedValidators
        );
    }

    // solhint-disable-next-line no-empty-blocks
    function __BalancerValidatorManager_init_unchained(
        address initialSecurityModule,
        uint64 initialSecurityModuleMaxWeight,
        bytes[] calldata migratedValidators
    ) internal onlyInitializing {
        _setupSecurityModule(initialSecurityModule, initialSecurityModuleMaxWeight);
        _migrateValidators(migratedValidators);
    }

    // solhint-enable func-name-mixedcase

    /// @inheritdoc IBalancerValidatorManager
    function setupSecurityModule(address securityModule, uint64 maxWeight) external onlyOwner {
        _setupSecurityModule(securityModule, maxWeight);
    }

    /// @inheritdoc IBalancerValidatorManager
    function initializeValidatorRegistration(
        ValidatorRegistrationInput calldata registrationInput,
        uint64 weight
    ) external onlySecurityModule returns (bytes32 validationID) {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();

        validationID = _initializeValidatorRegistration(registrationInput, weight);

        // Update the security module weight
        uint64 newSecurityModuleWeight = $.securityModuleWeight[msg.sender] + weight;
        _updateSecurityModuleWeight(msg.sender, newSecurityModuleWeight);

        $.validatorSecurityModule[validationID] = msg.sender;
    }

    /// @inheritdoc IBalancerValidatorManager
    function initializeEndValidation(
        bytes32 validationID
    ) external onlySecurityModule {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        Validator memory validator = getValidator(validationID);

        // Ensure the validator weight is not being updated
        if ($.validatorPendingWeightUpdate[validationID] != 0) {
            revert BalancerValidatorManager__PendingWeightUpdate(validationID);
        }

        _checkValidatorSecurityModule(validationID, msg.sender);
        _initializeEndValidation(validationID);

        // If the validator is not an initial validator, update the security module weight
        if ($.validatorSecurityModule[validationID] != address(0)) {
            // Update the security module weight
            uint64 newSecurityModuleWeight = $.securityModuleWeight[msg.sender] - validator.weight;
            _updateSecurityModuleWeight(msg.sender, newSecurityModuleWeight);
        }
    }

    /// @inheritdoc IValidatorManager
    function completeEndValidation(
        uint32 messageIndex
    ) external {
        _completeEndValidation(messageIndex);
    }

    /// @inheritdoc IBalancerValidatorManager
    function initializeValidatorWeightUpdate(
        bytes32 validationID,
        uint64 newWeight
    ) external onlySecurityModule {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();

        // Check that the newWeight is greater than zero
        if (newWeight == 0) {
            revert BalancerValidatorManager__NewWeightIsZero();
        }

        // Ensure the validation period is active and that the validator is not already being updated
        // The initial validator set must have been set already to have active validators.
        Validator memory validator = getValidator(validationID);
        if (validator.status != ValidatorStatus.Active) {
            revert InvalidValidatorStatus(validator.status);
        }
        if ($.validatorPendingWeightUpdate[validationID] != 0) {
            revert BalancerValidatorManager__PendingWeightUpdate(validationID);
        }

        _checkValidatorSecurityModule(validationID, msg.sender);
        uint64 oldWeight = getValidator(validationID).weight;
        (, bytes32 messageID) = _setValidatorWeight(validationID, newWeight);

        // Update the security module weight
        uint64 newSecurityModuleWeight = $.securityModuleWeight[msg.sender] + newWeight - oldWeight;
        _updateSecurityModuleWeight(msg.sender, newSecurityModuleWeight);

        $.validatorPendingWeightUpdate[validationID] = messageID;
    }

    /// @inheritdoc IBalancerValidatorManager
    function completeValidatorWeightUpdate(bytes32 validationID, uint32 messageIndex) external {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        Validator memory validator = getValidator(validationID);

        // Check that the validator is active and being updated
        if (validator.status != ValidatorStatus.Active) {
            revert InvalidValidatorStatus(validator.status);
        }
        if ($.validatorPendingWeightUpdate[validationID] == 0) {
            revert BalancerValidatorManager__NoPendingWeightUpdate(validationID);
        }

        // Unpack the Warp message
        (bytes32 messageValidationID, uint64 nonce,) = ValidatorMessages
            .unpackL1ValidatorWeightMessage(_getPChainWarpMessage(messageIndex).payload);

        if (validationID != messageValidationID) {
            revert InvalidValidationID(validationID);
        }
        if (validator.messageNonce < nonce) {
            revert BalancerValidatorManager__InvalidNonce(nonce);
        }

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

        if (validator.messageNonce == 0) {
            revert InvalidValidationID(validationID);
        }

        // Submit the message to the Warp precompile.
        WARP_MESSENGER.sendWarpMessage(
            ValidatorMessages.packL1ValidatorWeightMessage(
                validationID, validator.messageNonce, validator.weight
            )
        );
    }

    /// @inheritdoc IBalancerValidatorManager
    function getChurnPeriodSeconds() external view returns (uint64 churnPeriodSeconds) {
        return _getChurnPeriodSeconds();
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

    function _setupSecurityModule(address securityModule, uint64 maxWeight) internal {
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

        emit SetupSecurityModule(securityModule, maxWeight);
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
        bytes[] calldata migratedValidators
    ) internal {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();

        // Add the migrated validators to the initial security module
        uint64 migratedValidatorsTotalWeight = 0;
        for (uint256 i = 0; i < migratedValidators.length; i++) {
            bytes32 validationID = registeredValidators(migratedValidators[i]);
            Validator memory validator = getValidator(validationID);
            $.validatorSecurityModule[validationID] = $.securityModules.keys()[0];
            migratedValidatorsTotalWeight += validator.weight;
        }

        // Update the initial security module weight
        _updateSecurityModuleWeight($.securityModules.keys()[0], migratedValidatorsTotalWeight);

        // TODO: Check that the migrated validators total weight equals the current L1 total weight
        // Can only be done once this issue is fixed: https://github.com/ava-labs/teleporter/issues/645
    }
}

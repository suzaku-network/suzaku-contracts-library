// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {
    BalancerValidatorManagerSettings,
    IBalancerValidatorManager
} from "../../interfaces/ValidatorManager/IBalancerValidatorManager.sol";

import {
    ConversionData,
    PChainOwner,
    Validator,
    ValidatorStatus
} from "@avalabs/icm-contracts/validator-manager/interfaces/IACP99Manager.sol";

import {
    ValidatorChurnPeriod,
    ValidatorRegistrationInput
} from "../../interfaces/ValidatorManager/IBalancerValidatorManager.sol";

import {ValidatorManager} from "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";

import {ValidatorMessages} from "@avalabs/icm-contracts/validator-manager/ValidatorMessages.sol";
import {
    IWarpMessenger,
    WarpMessage
} from "@avalabs/subnet-evm-contracts@1.2.2/contracts/interfaces/IWarpMessenger.sol";

import {OwnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable@5.0.2/access/OwnableUpgradeable.sol";
import {EnumerableMap} from "@openzeppelin/contracts@5.0.2/utils/structs/EnumerableMap.sol";

contract BalancerValidatorManager is IBalancerValidatorManager, OwnableUpgradeable {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    IWarpMessenger internal constant WARP_MESSENGER =
        IWarpMessenger(0x0200000000000000000000000000000000000005);

    /// @custom:storage-location erc7201:suzaku.storage.BalancerValidatorManager
    struct BalancerValidatorManagerStorage {
        EnumerableMap.AddressToUintMap securityModules;
        mapping(address securityModule => uint64 weight) securityModuleWeight;
        mapping(bytes32 validationID => address securityModule) validatorSecurityModule;
        mapping(bytes32 validationID => uint64 weight) registrationInitWeight;
    }

    // keccak256(abi.encode(uint256(keccak256("suzaku.storage.BalancerValidatorManager")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 public constant BALANCER_VALIDATOR_MANAGER_STORAGE_LOCATION =
        0x9d2d7650aa35ca910e5b713f6b3de6524a06fbcb31ffc9811340c6f331a23400;

    // solhint-disable func-name-mixedcase
    function _getBalancerValidatorManagerStorage()
        private
        pure
        returns (BalancerValidatorManagerStorage storage $)
    {
        assembly {
            $.slot := BALANCER_VALIDATOR_MANAGER_STORAGE_LOCATION
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Underlying ValidatorManager (composed, owned by this Balancer)
    ValidatorManager internal VALIDATOR_MANAGER;

    /// @notice Initialize the Balancer wrapper and bind it to a ValidatorManager address.
    /// @dev The ValidatorManager must have been deployed & will have its ownership transferred to this contract by scripts.
    function initialize(
        BalancerValidatorManagerSettings calldata settings,
        address VALIDATOR_MANAGERAddress
    ) external initializer {
        __Ownable_init(settings.initialOwner);
        if (VALIDATOR_MANAGERAddress == address(0)) {
            revert BalancerValidatorManager__ZeroValidatorManagerAddress();
        }
        VALIDATOR_MANAGER = ValidatorManager(VALIDATOR_MANAGERAddress);
        if (VALIDATOR_MANAGER.owner() != address(this)) {
            revert BalancerValidatorManager__ValidatorManagerNotOwnedByBalancer();
        }

        // Ensure initial cap is sufficient (mirror old semantics)
        uint64 totalWeight = VALIDATOR_MANAGER.l1TotalWeight();

        // Migration requirement: if VM2 already has weight, require migration
        if (totalWeight > 0) {
            if (settings.initialSecurityModule == address(0)) {
                revert BalancerValidatorManager__InitialSecurityModuleRequiredForMigration();
            }
            if (settings.migratedValidators.length == 0) {
                revert BalancerValidatorManager__MigratedValidatorsRequired();
            }
        }

        if (settings.initialSecurityModule != address(0)) {
            if (settings.initialSecurityModuleMaxWeight < totalWeight) {
                revert BalancerValidatorManager__InitialSecurityModuleMaxWeightLowerThanTotalWeight(
                    settings.initialSecurityModule,
                    settings.initialSecurityModuleMaxWeight,
                    totalWeight
                );
            }
            _setUpSecurityModule(
                settings.initialSecurityModule, settings.initialSecurityModuleMaxWeight
            );
        }

        // Optional migration (old _migrateValidators behavior)
        if (settings.migratedValidators.length > 0) {
            BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
            uint64 migratedValidatorsTotalWeight = 0;
            for (uint256 i = 0; i < settings.migratedValidators.length; i++) {
                bytes32 validationID =
                    VALIDATOR_MANAGER.getNodeValidationID(settings.migratedValidators[i]);
                if ($.validatorSecurityModule[validationID] != address(0)) {
                    revert BalancerValidatorManager__ValidatorAlreadyMigrated(validationID);
                }
                $.validatorSecurityModule[validationID] = settings.initialSecurityModule;
                migratedValidatorsTotalWeight += VALIDATOR_MANAGER.getValidator(validationID).weight;
            }
            if (migratedValidatorsTotalWeight != totalWeight) {
                revert BalancerValidatorManager__MigratedValidatorsTotalWeightMismatch(
                    migratedValidatorsTotalWeight, totalWeight
                );
            }
            $.securityModuleWeight[settings.initialSecurityModule] = migratedValidatorsTotalWeight;
        }
    }

    function setUpSecurityModule(address securityModule, uint64 maxWeight) external onlyOwner {
        _setUpSecurityModule(securityModule, maxWeight);
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

    function _updateSecurityModuleWeight(address securityModule, uint64 newWeight) internal {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        uint64 maxWeight = uint64($.securityModules.get(securityModule));
        if (newWeight > maxWeight) {
            revert BalancerValidatorManager__SecurityModuleMaxWeightExceeded(
                securityModule, newWeight, maxWeight
            );
        }
        $.securityModuleWeight[securityModule] = newWeight;
    }

    modifier onlySecurityModule() {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        if (!$.securityModules.contains(msg.sender)) {
            revert BalancerValidatorManager__SecurityModuleNotRegistered(msg.sender);
        }
        _;
    }

    function _requireOwned(bytes32 validationID, address securityModule) internal view {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        if (
            $.validatorSecurityModule[validationID] != address(0)
                && $.validatorSecurityModule[validationID] != securityModule
        ) {
            revert BalancerValidatorManager__ValidatorNotBelongingToSecurityModule(
                validationID, securityModule
            );
        }
    }

    function _checkValidatorSecurityModule(
        bytes32 validationID,
        address securityModule
    ) internal view {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        if ($.validatorSecurityModule[validationID] == address(0)) {
            return;
        } else if ($.validatorSecurityModule[validationID] != securityModule) {
            revert BalancerValidatorManager__ValidatorNotBelongingToSecurityModule(
                validationID, securityModule
            );
        }
    }

    function _hasPendingWeightMsg(
        bytes32 validationID
    ) internal view returns (bool) {
        Validator memory validator = VALIDATOR_MANAGER.getValidator(validationID);
        return validator.sentNonce > validator.receivedNonce; // explicit and clear
    }

    // NOTE: tests call this directly (no owner/module restriction)
    function initializeValidatorSet(
        ConversionData calldata conversionData,
        uint32 messageIndex
    ) external {
        VALIDATOR_MANAGER.initializeValidatorSet(conversionData, messageIndex);
    }

    function completeValidatorRegistration(
        uint32 messageIndex
    ) external returns (bytes32) {
        bytes32 validationID = VALIDATOR_MANAGER.completeValidatorRegistration(messageIndex);
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        delete $.registrationInitWeight[validationID];
        return validationID;
    }

    function resendValidatorWeightUpdate(
        bytes32 validationID
    ) external {
        Validator memory validator = VALIDATOR_MANAGER.getValidator(validationID);
        if (validator.status != ValidatorStatus.Active) {
            revert InvalidValidatorStatus(validator.status);
        }
        if (!_hasPendingWeightMsg(validationID)) {
            revert BalancerValidatorManager__NoPendingWeightUpdate(validationID);
        }
        if (validator.sentNonce == 0) {
            revert InvalidValidationID(validationID);
        }

        WARP_MESSENGER.sendWarpMessage(
            ValidatorMessages.packL1ValidatorWeightMessage(
                validationID, validator.sentNonce, validator.weight
            )
        );
    }

    function resendRegisterValidatorMessage(
        bytes32 validationID
    ) external {
        VALIDATOR_MANAGER.resendRegisterValidatorMessage(validationID);
    }

    function getChurnPeriodSeconds() external view returns (uint64) {
        return VALIDATOR_MANAGER.getChurnPeriodSeconds();
    }

    function getMaximumChurnPercentage() external view returns (uint64) {
        (, uint8 maximumChurnPercentage,) = VALIDATOR_MANAGER.getChurnTracker();
        return uint64(maximumChurnPercentage);
    }

    function getCurrentChurnPeriod()
        external
        view
        returns (ValidatorChurnPeriod memory churnPeriod)
    {
        (,, churnPeriod) = VALIDATOR_MANAGER.getChurnTracker();
    }

    function getSecurityModules() external view returns (address[] memory securityModules) {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        return $.securityModules.keys();
    }

    function getSecurityModuleWeights(
        address securityModule
    ) external view returns (uint64 weight, uint64 maxWeight) {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        weight = $.securityModuleWeight[securityModule];
        maxWeight = uint64($.securityModules.get(securityModule));
    }

    function getValidatorSecurityModule(
        bytes32 validationID
    ) external view returns (address) {
        return _getBalancerValidatorManagerStorage().validatorSecurityModule[validationID];
    }

    function isValidatorPendingWeightUpdate(
        bytes32 validationID
    ) external view returns (bool) {
        return _hasPendingWeightMsg(validationID);
    }

    function getValidator(
        bytes32 validationID
    ) external view returns (Validator memory) {
        return VALIDATOR_MANAGER.getValidator(validationID);
    }

    function getNodeValidationID(
        bytes calldata nodeID
    ) external view returns (bytes32) {
        return VALIDATOR_MANAGER.getNodeValidationID(nodeID);
    }

    function initiateValidatorRegistration(
        bytes memory nodeID,
        bytes memory blsPublicKey,
        PChainOwner memory remainingBalanceOwner,
        PChainOwner memory disableOwner,
        uint64 weight
    ) external onlySecurityModule returns (bytes32 validationID) {
        validationID = VALIDATOR_MANAGER.initiateValidatorRegistration(
            nodeID, blsPublicKey, remainingBalanceOwner, disableOwner, weight
        );

        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        $.validatorSecurityModule[validationID] = msg.sender;
        $.registrationInitWeight[validationID] = weight;
        _updateSecurityModuleWeight(msg.sender, $.securityModuleWeight[msg.sender] + weight);
    }

    function initiateValidatorRemoval(
        bytes32 validationID
    ) external onlySecurityModule {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();

        _checkValidatorSecurityModule(validationID, msg.sender);

        Validator memory validator = VALIDATOR_MANAGER.getValidator(validationID);
        if (validator.status != ValidatorStatus.Active) {
            revert InvalidValidatorStatus(validator.status);
        }
        // avoid starting removal while a weight update is in-flight
        if (_hasPendingWeightMsg(validationID)) {
            revert BalancerValidatorManager__PendingWeightUpdate(validationID);
        }

        VALIDATOR_MANAGER.initiateValidatorRemoval(validationID);
        _updateSecurityModuleWeight(
            msg.sender, $.securityModuleWeight[msg.sender] - validator.weight
        );
    }

    function completeValidatorRemoval(
        uint32 messageIndex
    ) external returns (bytes32 validationID) {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        validationID = VALIDATOR_MANAGER.completeValidatorRemoval(messageIndex);

        // Case A (normal removal): we already freed the weight in initiateValidatorRemoval() → nothing to do.
        // Case B (expired-before-activation): no initiateValidatorRemoval() happened, so undo the init add once.
        uint64 registrationWeight = $.registrationInitWeight[validationID];
        if (registrationWeight != 0) {
            address securityModule = $.validatorSecurityModule[validationID];
            uint64 weight = $.securityModuleWeight[securityModule];
            uint64 updatedWeight = (weight > registrationWeight) ? (weight - registrationWeight) : 0;
            _updateSecurityModuleWeight(securityModule, updatedWeight);
            delete $.registrationInitWeight[validationID];
        }
        delete $.validatorSecurityModule[validationID];
    }

    function initiateValidatorWeightUpdate(
        bytes32 validationID,
        uint64 newWeight
    ) external onlySecurityModule returns (uint64 nonce, bytes32 messageID) {
        if (newWeight == 0) {
            revert BalancerValidatorManager__NewWeightIsZero();
        }

        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        Validator memory validator = VALIDATOR_MANAGER.getValidator(validationID);

        if (validator.status != ValidatorStatus.Active) {
            revert InvalidValidatorStatus(validator.status);
        }
        // one in-flight update at a time
        if (_hasPendingWeightMsg(validationID)) {
            revert BalancerValidatorManager__PendingWeightUpdate(validationID);
        }

        _checkValidatorSecurityModule(validationID, msg.sender);

        (nonce, messageID) =
            VALIDATOR_MANAGER.initiateValidatorWeightUpdate(validationID, newWeight);

        _updateSecurityModuleWeight(
            msg.sender, $.securityModuleWeight[msg.sender] + newWeight - validator.weight
        );
        // no local pending tracking needed
    }

    function completeValidatorWeightUpdate(
        uint32 messageIndex
    ) external returns (bytes32 validationID, uint64 nonce) {
        // peek at the warp payload to get validationID + received nonce for pre-checks
        (WarpMessage memory warpMessage, bool valid) =
            WARP_MESSENGER.getVerifiedWarpMessage(messageIndex);
        if (!valid) {
            revert BalancerValidatorManager__InvalidWarpMessage();
        }

        (bytes32 vid, uint64 receivedNonce, /*weight*/ ) =
            ValidatorMessages.unpackL1ValidatorWeightMessage(warpMessage.payload);

        // guard: monotonic nonce (block duplicates/stale messages)
        Validator memory validator = VALIDATOR_MANAGER.getValidator(vid);
        if (receivedNonce <= validator.receivedNonce) {
            revert BalancerValidatorManager__NoPendingWeightUpdate(vid);
        }

        // guard: sanity check (VM also checks this)
        if (receivedNonce > validator.sentNonce) {
            revert BalancerValidatorManager__InvalidNonce(receivedNonce);
        }

        // forward to VM (does full verification again) and return its values
        (validationID, nonce) = VALIDATOR_MANAGER.completeValidatorWeightUpdate(messageIndex);

        // double-check consistency with what we decoded
        if (validationID != vid || nonce != receivedNonce) {
            revert BalancerValidatorManager__InconsistentNonce();
        }
    }

    function resendValidatorRemovalMessage(
        bytes32 validationID
    ) external {
        VALIDATOR_MANAGER.resendValidatorRemovalMessage(validationID);
    }

    function migrateFromV1(bytes32 validationID, uint32 receivedNonce) external {
        VALIDATOR_MANAGER.migrateFromV1(validationID, receivedNonce);
    }

    function l1TotalWeight() external view returns (uint64) {
        return VALIDATOR_MANAGER.l1TotalWeight();
    }

    function subnetID() external view returns (bytes32) {
        return VALIDATOR_MANAGER.subnetID();
    }
}

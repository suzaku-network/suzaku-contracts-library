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
    ValidatorManager
} from "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";

import {ValidatorMessages} from "@avalabs/icm-contracts/validator-manager/ValidatorMessages.sol";
import {
    IWarpMessenger,
    WarpMessage
} from "@avalabs/subnet-evm-contracts@1.2.2/contracts/interfaces/IWarpMessenger.sol";

import {ISecurityModule} from "../../interfaces/ValidatorManager/ISecurityModule.sol";
import {OwnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable@5.0.2/access/OwnableUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts@5.0.2/utils/introspection/IERC165.sol";
import {EnumerableMap} from "@openzeppelin/contracts@5.0.2/utils/structs/EnumerableMap.sol";

/**
 * @title BalancerValidatorManager
 * @author ADDPHO
 * @notice The Balancer Validator Manager contract allows to balance the weight of an L1 between multiple security modules.
 * @custom:security-contact security@suzaku.network
 */
contract BalancerValidatorManager is IBalancerValidatorManager, OwnableUpgradeable {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    IWarpMessenger internal constant WARP_MESSENGER =
        IWarpMessenger(0x0200000000000000000000000000000000000005);

    /// @custom:storage-location erc7201:suzaku.storage.BalancerValidatorManager
    struct BalancerValidatorManagerStorage {
        /// @notice The registered security modules along with their maximum weight
        EnumerableMap.AddressToUintMap securityModules;
        /// @notice The total weight of all validators for a given security module
        mapping(address securityModule => uint64 weight) securityModuleWeight;
        /// @notice The security module to which each validator belongs
        mapping(bytes32 validationID => address securityModule) validatorSecurityModule;
        /// @notice Tracks initial weight for registrations in progress (temporary state)
        mapping(bytes32 validationID => uint64 weight) registrationInitWeight;
        /// @notice Number of validators currently assigned to each module (incl. pending removals)
        mapping(address securityModule => uint64 count) securityModuleValidatorCount;
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
    // solhint-enable func-name-mixedcase

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Underlying ValidatorManager (composed, owned by this Balancer)
    ValidatorManager public VALIDATOR_MANAGER;

    /**
     * @notice Initialize the Balancer Validator Manager
     * @param settings The settings for the Balancer Validator Manager
     * @param validatorManagerAddress The address of the ValidatorManager to wrap
     */
    function initialize(
        BalancerValidatorManagerSettings calldata settings,
        address validatorManagerAddress
    ) external initializer {
        __Ownable_init(settings.initialOwner);
        if (validatorManagerAddress == address(0)) {
            revert BalancerValidatorManager__ZeroValidatorManagerAddress();
        }
        VALIDATOR_MANAGER = ValidatorManager(validatorManagerAddress);
        if (VALIDATOR_MANAGER.owner() != address(this)) {
            revert BalancerValidatorManager__ValidatorManagerNotOwnedByBalancer();
        }
        if (!VALIDATOR_MANAGER.isValidatorSetInitialized()) {
            revert BalancerValidatorManager__VMValidatorSetNotInitialized();
        }

        // Get current total weight from ValidatorManager
        uint64 totalWeight = VALIDATOR_MANAGER.l1TotalWeight();

        // Migration requirement: if ValidatorManager already has weight, require migration
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

        // Migrate validators if provided
        if (settings.migratedValidators.length > 0) {
            BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
            uint64 migratedValidatorsTotalWeight = 0;
            for (uint256 i = 0; i < settings.migratedValidators.length; i++) {
                bytes32 validationID =
                    VALIDATOR_MANAGER.getNodeValidationID(settings.migratedValidators[i]);

                // Ensure nodeID exists on ValidatorManager
                if (validationID == bytes32(0)) {
                    revert BalancerValidatorManager__MigratedNodeIDNotFound(
                        settings.migratedValidators[i]
                    );
                }

                if ($.validatorSecurityModule[validationID] != address(0)) {
                    revert BalancerValidatorManager__ValidatorAlreadyMigrated(validationID);
                }

                Validator memory validator = VALIDATOR_MANAGER.getValidator(validationID);
                if (
                    validator.status != ValidatorStatus.Active
                        && validator.status != ValidatorStatus.PendingAdded
                ) {
                    revert BalancerValidatorManager__InvalidValidatorStatus(
                        validationID, validator.status
                    );
                }
                if (validator.weight == 0) {
                    revert BalancerValidatorManager__InvalidValidatorWeight(validationID);
                }

                $.validatorSecurityModule[validationID] = settings.initialSecurityModule;
                $.securityModuleValidatorCount[settings.initialSecurityModule] += 1;

                if (validator.status == ValidatorStatus.PendingAdded) {
                    $.registrationInitWeight[validationID] = validator.weight;
                }

                migratedValidatorsTotalWeight += validator.weight;
            }
            if (migratedValidatorsTotalWeight != totalWeight) {
                revert BalancerValidatorManager__MigratedValidatorsTotalWeightMismatch(
                    migratedValidatorsTotalWeight, totalWeight
                );
            }
            $.securityModuleWeight[settings.initialSecurityModule] = migratedValidatorsTotalWeight;
        }
    }

    /// @inheritdoc IBalancerValidatorManager
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
            // Forbid removal while weight > 0
            if (currentWeight != 0) {
                revert BalancerValidatorManager__CannotRemoveModuleWithWeight(securityModule);
            }
            // Forbid removal while any validator IDs are still owned by this module
            if ($.securityModuleValidatorCount[securityModule] != 0) {
                revert BalancerValidatorManager__CannotRemoveModuleWithAssignedValidators(
                    securityModule, $.securityModuleValidatorCount[securityModule]
                );
            }
            if (!$.securityModules.remove(securityModule)) {
                revert BalancerValidatorManager__SecurityModuleNotRegistered(securityModule);
            }
        } else {
            // require ERC-165 support for the security-module interface
            try IERC165(securityModule).supportsInterface(type(ISecurityModule).interfaceId)
            returns (bool ok) {
                if (!ok) {
                    revert BalancerValidatorManager__SecurityModuleNotRegistered(securityModule);
                }
            } catch {
                revert BalancerValidatorManager__SecurityModuleNotRegistered(securityModule);
            }
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
        uint64 oldWeight = $.securityModuleWeight[securityModule];
        $.securityModuleWeight[securityModule] = newWeight;
        emit SecurityModuleWeightUpdated(securityModule, oldWeight, newWeight, maxWeight);
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
        address owner = $.validatorSecurityModule[validationID];
        if (owner != securityModule) {
            revert BalancerValidatorManager__ValidatorNotBelongingToSecurityModule(
                validationID, securityModule
            );
        }
    }

    function _hasPendingWeightMsg(
        bytes32 validationID
    ) internal view returns (bool) {
        Validator memory validator = VALIDATOR_MANAGER.getValidator(validationID);
        // Only treat Active or PendingRemoved as eligible for "pending".
        if (
            validator.status != ValidatorStatus.Active
                && validator.status != ValidatorStatus.PendingRemoved
        ) {
            return false;
        }
        return validator.sentNonce > validator.receivedNonce;
    }

    function initializeValidatorSet(
        ConversionData calldata conversionData,
        uint32 messageIndex
    ) external {
        VALIDATOR_MANAGER.initializeValidatorSet(conversionData, messageIndex);
    }

    function completeValidatorRegistration(
        uint32 messageIndex
    ) external onlySecurityModule returns (bytes32) {
        bytes32 validationID = VALIDATOR_MANAGER.completeValidatorRegistration(messageIndex);
        _requireOwned(validationID, msg.sender);
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        delete $.registrationInitWeight[validationID];
        return validationID;
    }

    /// @inheritdoc IBalancerValidatorManager
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

        WARP_MESSENGER.sendWarpMessage(
            ValidatorMessages.packL1ValidatorWeightMessage(
                validationID, validator.sentNonce, validator.weight
            )
        );
    }

    /// @inheritdoc IBalancerValidatorManager
    function resendRegisterValidatorMessage(
        bytes32 validationID
    ) external {
        VALIDATOR_MANAGER.resendRegisterValidatorMessage(validationID);
    }

    /// @inheritdoc IBalancerValidatorManager
    function getChurnPeriodSeconds() external view returns (uint64) {
        return VALIDATOR_MANAGER.getChurnPeriodSeconds();
    }

    /// @inheritdoc IBalancerValidatorManager
    function getMaximumChurnPercentage() external view returns (uint64) {
        (, uint8 maximumChurnPercentage,) = VALIDATOR_MANAGER.getChurnTracker();
        return uint64(maximumChurnPercentage);
    }

    /// @inheritdoc IBalancerValidatorManager
    function getCurrentChurnPeriod()
        external
        view
        returns (ValidatorChurnPeriod memory churnPeriod)
    {
        (,, churnPeriod) = VALIDATOR_MANAGER.getChurnTracker();
    }

    /// @inheritdoc IBalancerValidatorManager
    function getSecurityModules() external view returns (address[] memory securityModules) {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        uint256 len = $.securityModules.length();
        securityModules = new address[](len);
        for (uint256 i = 0; i < len; ++i) {
            (address key,) = $.securityModules.at(i);
            securityModules[i] = key;
        }
    }

    /// @inheritdoc IBalancerValidatorManager
    function getSecurityModuleWeights(
        address securityModule
    ) external view returns (uint64 weight, uint64 maxWeight) {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        weight = $.securityModuleWeight[securityModule];
        (bool securityModuleExists, uint256 max) = $.securityModules.tryGet(securityModule);
        maxWeight = securityModuleExists ? uint64(max) : 0;
    }

    /// @inheritdoc IBalancerValidatorManager
    function getValidatorSecurityModule(
        bytes32 validationID
    ) external view returns (address) {
        return _getBalancerValidatorManagerStorage().validatorSecurityModule[validationID];
    }

    /// @inheritdoc IBalancerValidatorManager
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

    /// @inheritdoc IBalancerValidatorManager
    function initiateValidatorRegistration(
        bytes memory nodeID,
        bytes memory blsPublicKey,
        PChainOwner memory remainingBalanceOwner,
        PChainOwner memory disableOwner,
        uint64 weight
    ) external onlySecurityModule returns (bytes32 validationID) {
        if (weight == 0) {
            revert BalancerValidatorManager__NewWeightIsZero();
        }
        validationID = VALIDATOR_MANAGER.initiateValidatorRegistration(
            nodeID, blsPublicKey, remainingBalanceOwner, disableOwner, weight
        );

        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        $.validatorSecurityModule[validationID] = msg.sender;
        $.securityModuleValidatorCount[msg.sender] += 1;
        $.registrationInitWeight[validationID] = weight;
        _updateSecurityModuleWeight(msg.sender, $.securityModuleWeight[msg.sender] + weight);
    }

    /// @inheritdoc IBalancerValidatorManager
    function initiateValidatorRemoval(
        bytes32 validationID
    ) external onlySecurityModule {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();

        _requireOwned(validationID, msg.sender);

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
    ) external onlySecurityModule returns (bytes32 validationID) {
        BalancerValidatorManagerStorage storage $ = _getBalancerValidatorManagerStorage();
        validationID = VALIDATOR_MANAGER.completeValidatorRemoval(messageIndex);
        _requireOwned(validationID, msg.sender);

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
        // Decrement refcount and clear ownership
        address securityModule_ = $.validatorSecurityModule[validationID];
        if (securityModule_ != address(0)) {
            uint64 currentCount = $.securityModuleValidatorCount[securityModule_];
            if (currentCount != 0) {
                $.securityModuleValidatorCount[securityModule_] = currentCount - 1;
            }
        }
        delete $.validatorSecurityModule[validationID];
    }

    /// @inheritdoc IBalancerValidatorManager
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

        _requireOwned(validationID, msg.sender);

        (nonce, messageID) =
            VALIDATOR_MANAGER.initiateValidatorWeightUpdate(validationID, newWeight);

        _updateSecurityModuleWeight(
            msg.sender, $.securityModuleWeight[msg.sender] + newWeight - validator.weight
        );
    }

    /// @inheritdoc IBalancerValidatorManager
    function completeValidatorWeightUpdate(
        uint32 messageIndex
    ) external onlySecurityModule returns (bytes32 validationID, uint64 nonce) {
        // Get warp message to extract validationID and nonce
        (WarpMessage memory warpMessage, bool valid) =
            WARP_MESSENGER.getVerifiedWarpMessage(messageIndex);
        if (!valid) {
            revert BalancerValidatorManager__InvalidWarpMessage();
        }

        (bytes32 vid, uint64 receivedNonce, /*weight*/ ) =
            ValidatorMessages.unpackL1ValidatorWeightMessage(warpMessage.payload);

        _requireOwned(vid, msg.sender);

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

    /// @inheritdoc IBalancerValidatorManager
    function resendValidatorRemovalMessage(
        bytes32 validationID
    ) external {
        VALIDATOR_MANAGER.resendValidatorRemovalMessage(validationID);
    }

    /// @inheritdoc IBalancerValidatorManager
    function transferValidatorManagerOwnership(
        address newOwner
    ) external onlyOwner {
        VALIDATOR_MANAGER.transferOwnership(newOwner);
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

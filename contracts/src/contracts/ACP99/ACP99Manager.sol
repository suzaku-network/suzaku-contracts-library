// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

// Compatible with OpenZeppelin Contracts ^4.9.0

pragma solidity 0.8.25;

import {IACP99Manager} from "../../interfaces/ACP99/IACP99Manager.sol";
import {IACP99SecurityModule} from "../../interfaces/ACP99/IACP99SecurityModule.sol";
import {
    IWarpMessenger,
    WarpMessage
} from "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {
    ConversionData,
    ValidatorMessages
} from "@avalabs/teleporter/validator-manager/ValidatorMessages.sol";
import {
    InitialValidator,
    PChainOwner
} from "@avalabs/teleporter/validator-manager/interfaces/IValidatorManager.sol";
import {Ownable2Step} from "@openzeppelin/contracts@4.9.6/access/Ownable2Step.sol";
import {EnumerableMap} from "@openzeppelin/contracts@4.9.6/utils/structs/EnumerableMap.sol";

/**
 * @title ACP99Manager
 * @author ADDPHO
 * @notice The ACP99Manager contract is responsible for managing the validator set of an L1.
 * It is meant to be used as the Validator Manager address in the `ConvertSubnetToL1Tx`.
 * @custom:security-contact security@suzaku.network
 */
contract ACP99Manager is Ownable2Step, IACP99Manager {
    using EnumerableMap for EnumerableMap.Bytes32ToBytes32Map;

    bytes32 private constant P_CHAIN_ID_HEX = bytes32(0);
    address private constant WARP_MESSENGER_ADDR = 0x0200000000000000000000000000000000000005;

    /// @notice The WarpMessenger contract
    IWarpMessenger private immutable warpMessenger;

    /// @notice The ID of the Subnet tied to this manager
    bytes32 public immutable subnetID;

    /// @notice The address of the security module attached to this manager
    IACP99SecurityModule private securityModule;

    /// @notice Whether the validator set has been initialized
    bool public initializedValidatorSet;

    /**
     * @notice The active validators of the L1
     * @notice NodeID => validationID
     */
    // mapping(bytes32 => bytes32) public activeValidators;
    EnumerableMap.Bytes32ToBytes32Map private activeValidators;

    /// @notice The total weight of the current L1 validator set
    uint64 public l1TotalWeight;

    /// @notice The list of validationIDs associated with a validator of the L1
    mapping(bytes32 nodeID => bytes32[] validationIDs) private l1ValidatorValidations;

    /// @notice The validation corresponding to each validationID
    mapping(bytes32 validationID => Validation validation) private l1Validations;

    /// @notice The registration message corresponding to a validationID such that it can be re-sent
    mapping(bytes32 validationID => bytes messageBytes) public pendingRegisterValidationMessages;

    modifier onlySecurityModule() {
        if (msg.sender != address(securityModule)) {
            revert ACP99Manager__OnlySecurityModule(msg.sender, address(securityModule));
        }
        _;
    }

    constructor(bytes32 subnetID_, address securityModule_) Ownable2Step() {
        if (securityModule_ == address(0)) {
            revert ACP99Manager__ZeroAddressSecurityModule();
        }

        warpMessenger = IWarpMessenger(WARP_MESSENGER_ADDR);
        subnetID = subnetID_;
        securityModule = IACP99SecurityModule(securityModule_);
    }

    /// @inheritdoc IACP99Manager
    function setSecurityModule(
        address securityModule_
    ) external onlyOwner {
        if (securityModule_ == address(0)) {
            revert ACP99Manager__ZeroAddressSecurityModule();
        }

        securityModule = IACP99SecurityModule(securityModule_);
        emit SetSecurityModule(securityModule_);
    }

    /// @inheritdoc IACP99Manager
    function initializeValidatorSet(
        ConversionData calldata conversionData,
        uint32 messageIndex
    ) external {
        if (initializedValidatorSet) {
            revert ACP99Manager__ValidatorSetAlreadyInitialized();
        }
        // Check that the blockchainID and validator manager address in the ConversionData correspond to this contract.
        if (conversionData.validatorManagerBlockchainID != warpMessenger.getBlockchainID()) {
            revert ACP99Manager__InvalidManagerBlockchainID(
                conversionData.validatorManagerBlockchainID, warpMessenger.getBlockchainID()
            );
        }
        if (address(conversionData.validatorManagerAddress) != address(this)) {
            revert ACP99Manager__InvalidManagerAddress(
                conversionData.validatorManagerAddress, address(this)
            );
        }

        uint256 numInitialValidators = conversionData.initialValidators.length;

        uint64 totalWeight;
        for (uint32 i; i < numInitialValidators; ++i) {
            InitialValidator memory initialValidator = conversionData.initialValidators[i];
            bytes memory nodeID = initialValidator.nodeID;

            if (activeValidators.contains(bytes32(nodeID))) {
                revert ACP99Manager__NodeAlreadyValidator(nodeID);
            }

            // Validation ID of the initial validators is the sha256 hash of the
            // Subnet ID and the index of the initial validator.
            bytes32 validationID = sha256(abi.encodePacked(conversionData.subnetID, i));

            // Save the initial validator as an active validator.

            activeValidators.set(bytes32(nodeID), validationID);
            Validation storage validation = l1Validations[validationID];
            validation.status = ValidationStatus.Active;
            validation.nodeID = bytes32(nodeID);
            validation.periods.push(
                IACP99Manager.ValidationPeriod({
                    weight: initialValidator.weight,
                    startTime: uint64(block.timestamp),
                    endTime: 0,
                    uptimeSeconds: 0
                })
            );
            totalWeight += initialValidator.weight;

            emit RegisterInitialValidator(bytes32(nodeID), validationID, initialValidator.weight);
        }
        l1TotalWeight = totalWeight;

        // Verify that the sha256 hash of the Subnet ConversionData matches with the Warp message's ConversionID.
        WarpMessage memory warpMessage = _getPChainWarpMessage(messageIndex);
        // Parse the Warp message into SubnetToL1ConversionMessage
        bytes32 messageConversionID =
            ValidatorMessages.unpackSubnetToL1ConversionMessage(warpMessage.payload);
        bytes memory encodedConversion = ValidatorMessages.packConversionData(conversionData);
        bytes32 conversionID = sha256(encodedConversion);
        if (conversionID != messageConversionID) {
            revert ACP99Manager__InvalidConversionID(conversionID, messageConversionID);
        }

        initializedValidatorSet = true;
    }

    /// @inheritdoc IACP99Manager
    function initiateValidatorRegistration(
        bytes memory nodeID,
        bytes memory blsPublicKey,
        uint64 registrationExpiry,
        PChainOwner memory remainingBalanceOwner,
        PChainOwner memory disableOwner,
        uint64 weight
    ) external onlySecurityModule returns (bytes32) {
        // Ensure the registration expiry is in a valid range.
        if (registrationExpiry < block.timestamp || registrationExpiry > block.timestamp + 2 days) {
            revert ACP99Manager__InvalidExpiry(registrationExpiry, block.timestamp);
        }

        // Ensure the nodeID is not the zero address, and is not already an active validator.
        if (bytes32(nodeID) == bytes32(0)) {
            revert ACP99Manager__ZeroNodeID();
        }
        if (activeValidators.contains(bytes32(nodeID))) {
            revert ACP99Manager__NodeAlreadyValidator(nodeID);
        }

        // Ensure the signature is the proper length. The EVM does not provide an Ed25519 precompile to
        // validate the signature, but the P-Chain will validate the signature. If the signature is invalid,
        // the P-Chain will reject the registration, and the stake can be returned to the staker after the registration
        // expiry has passed.
        if (blsPublicKey.length != 48) {
            revert ACP99Manager__InvalidSignatureLength(blsPublicKey.length);
        }

        _validatePChainOwner(remainingBalanceOwner);
        _validatePChainOwner(disableOwner);

        (bytes32 validationID, bytes memory registrationMessage) = ValidatorMessages
            .packRegisterL1ValidatorMessage(
            ValidatorMessages.ValidationPeriod({
                subnetID: subnetID,
                nodeID: nodeID,
                blsPublicKey: blsPublicKey,
                registrationExpiry: registrationExpiry,
                remainingBalanceOwner: remainingBalanceOwner,
                disableOwner: disableOwner,
                weight: weight
            })
        );

        pendingRegisterValidationMessages[validationID] = registrationMessage;
        Validation storage validation = l1Validations[validationID];
        validation.status = ValidationStatus.Registering;
        validation.nodeID = bytes32(nodeID);
        validation.periods.push(
            ValidationPeriod({weight: weight, startTime: 0, endTime: 0, uptimeSeconds: 0})
        );
        l1ValidatorValidations[bytes32(nodeID)].push(validationID);

        bytes32 registrationMessageID = warpMessenger.sendWarpMessage(registrationMessage);

        emit InitiateValidatorRegistration(
            bytes32(nodeID), validationID, registrationMessageID, registrationExpiry, weight
        );

        return validationID;
    }

    /// @inheritdoc IACP99Manager
    function resendValidatorRegistrationMessage(
        bytes32 validationID
    ) external returns (bytes32) {
        if (
            pendingRegisterValidationMessages[validationID].length == 0
                || l1Validations[validationID].status != ValidationStatus.Registering
        ) {
            revert ACP99Manager__InvalidValidationID(validationID);
        }

        return warpMessenger.sendWarpMessage(pendingRegisterValidationMessages[validationID]);
    }

    /// @inheritdoc IACP99Manager
    function completeValidatorRegistration(
        uint32 messageIndex
    ) external {
        WarpMessage memory warpMessage = _getPChainWarpMessage(messageIndex);

        (bytes32 validationID, bool validRegistration) =
            ValidatorMessages.unpackL1ValidatorRegistrationMessage(warpMessage.payload);
        if (!validRegistration) {
            revert ACP99Manager__InvalidRegistration();
        }
        Validation storage validation = l1Validations[validationID];

        if (
            pendingRegisterValidationMessages[validationID].length == 0
                || validation.status != ValidationStatus.Registering
        ) {
            revert ACP99Manager__InvalidValidationID(validationID);
        }

        delete pendingRegisterValidationMessages[validationID];

        validation.status = ValidationStatus.Active;
        uint64 startTime = uint64(block.timestamp);
        validation.periods[0].startTime = startTime;
        activeValidators.set(validation.nodeID, validationID);
        l1TotalWeight += validation.periods[0].weight;

        // Notify the SecurityModule of the validator registration
        securityModule.handleValidatorRegistration(
            IACP99SecurityModule.ValidatorRegistrationInfo({
                nodeID: validation.nodeID,
                validationID: validationID,
                weight: validation.periods[0].weight,
                startTime: startTime
            })
        );

        emit CompleteValidatorRegistration(
            validation.nodeID, validationID, validation.periods[0].weight
        );
    }

    /// @inheritdoc IACP99Manager
    function updateUptime(
        bytes memory nodeID,
        uint32 messageIndex
    ) external returns (IACP99Manager.ValidatorUptimeInfo memory) {
        bytes32 validationID = activeValidators.get(bytes32(nodeID));
        Validation storage validation = l1Validations[validationID];

        _updateValidationUptime(validationID, validation, messageIndex);

        return _getValidationUptimeInfo(validation, validation.periods.length - 1);
    }

    /// @inheritdoc IACP99Manager
    function initiateValidatorWeightUpdate(
        bytes memory nodeID,
        uint64 weight,
        bool includesUptimeProof,
        uint32 messageIndex
    ) external onlySecurityModule {
        if (!activeValidators.contains(bytes32(nodeID))) {
            revert ACP99Manager__NodeIDNotActiveValidator(nodeID);
        }

        bytes32 validationID = activeValidators.get(bytes32(nodeID));
        Validation storage validation = l1Validations[validationID];

        // Verify the uptime proof if it is included
        if (includesUptimeProof) {
            _updateValidationUptime(validationID, validation, messageIndex);
        }

        uint256 validationPeriodIndex = validation.periods.length - 1;
        ValidationPeriod storage currentPeriod = validation.periods[validationPeriodIndex];
        currentPeriod.endTime = uint64(block.timestamp);

        if (weight > 0) {
            validation.status = ValidationStatus.Updating;
            // The startTime is set to 0 to indicate that the period is not yet started
            validation.periods.push(
                ValidationPeriod({weight: weight, startTime: 0, endTime: 0, uptimeSeconds: 0})
            );
        } else {
            // If the weight is 0, the validator is being removed
            validation.status = ValidationStatus.Removing;
            activeValidators.remove(validation.nodeID);
        }

        bytes memory setValidatorWeightPayload = ValidatorMessages.packL1ValidatorWeightMessage(
            validationID, uint64(validation.periods.length), weight
        );
        bytes32 setValidatorWeightMessageID =
            warpMessenger.sendWarpMessage(setValidatorWeightPayload);

        emit InitiateValidatorWeightUpdate(
            bytes32(nodeID), validationID, setValidatorWeightMessageID, weight
        );
    }

    /// @inheritdoc IACP99Manager
    function completeValidatorWeightUpdate(
        uint32 messageIndex
    ) external {
        WarpMessage memory warpMessage = _getPChainWarpMessage(messageIndex);
        (bytes32 validationID, uint64 nonce, uint64 weight) =
            ValidatorMessages.unpackL1ValidatorWeightMessage(warpMessage.payload);
        Validation storage validation = l1Validations[validationID];
        if (
            validation.status != ValidationStatus.Updating
                && validation.status != ValidationStatus.Removing
        ) {
            revert ACP99Manager__InvalidValidationID(validationID);
        }

        if (weight == 0) {
            if (nonce != (validation.periods.length)) {
                revert ACP99Manager__InvalidSetL1ValidatorWeightNonce(
                    nonce, uint64(validation.periods.length)
                );
            }
            validation.status = ValidationStatus.Completed;
            l1TotalWeight -= validation.periods[nonce - 1].weight;
        } else {
            if (nonce != (validation.periods.length - 1)) {
                revert ACP99Manager__InvalidSetL1ValidatorWeightNonce(
                    nonce, uint64(validation.periods.length - 1)
                );
            }
            validation.status = ValidationStatus.Active;
            validation.periods[nonce].startTime = uint64(block.timestamp);
            l1TotalWeight += validation.periods[nonce].weight - validation.periods[nonce - 1].weight;
        }

        _notifySecurityModuleValidatorWeightUpdate(validationID, nonce, weight);

        emit CompleteValidatorWeightUpdate(validation.nodeID, validationID, nonce, weight);
    }

    function _validatePChainOwner(
        PChainOwner memory pChainOwner
    ) internal pure {
        // If threshold is 0, addresses must be empty.
        if (pChainOwner.threshold == 0 && pChainOwner.addresses.length != 0) {
            revert ACP99Manager__InvalidPChainOwnerThreshold(
                pChainOwner.threshold, pChainOwner.addresses.length
            );
        }
        // Threshold must be less than or equal to the number of addresses.
        if (pChainOwner.threshold > pChainOwner.addresses.length) {
            revert ACP99Manager__InvalidPChainOwnerThreshold(
                pChainOwner.threshold, pChainOwner.addresses.length
            );
        }
        // Addresses must be sorted in ascending order
        for (uint256 i = 1; i < pChainOwner.addresses.length; i++) {
            // Compare current address with the previous one
            if (pChainOwner.addresses[i] < pChainOwner.addresses[i - 1]) {
                revert ACP99Manager__PChainOwnerAddressesNotSorted();
            }
        }
    }

    /// @dev Get the Warp message from the P-Chain and verify that it is valid and from the P-Chain
    function _getPChainWarpMessage(
        uint32 messageIndex
    ) private view returns (WarpMessage memory) {
        (WarpMessage memory warpMessage, bool valid) =
            warpMessenger.getVerifiedWarpMessage(messageIndex);
        if (!valid) {
            revert ACP99Manager__InvalidWarpMessage();
        }

        if (warpMessage.sourceChainID != P_CHAIN_ID_HEX) {
            revert ACP99Manager__InvalidSourceChainID(warpMessage.sourceChainID);
        }
        if (warpMessage.originSenderAddress != address(0)) {
            revert ACP99Manager__InvalidOriginSenderAddress(warpMessage.originSenderAddress);
        }

        return warpMessage;
    }

    function _updateValidationUptime(
        bytes32 validationID,
        Validation storage validation,
        uint32 messageIndex
    ) private {
        (WarpMessage memory warpMessage, bool valid) =
            warpMessenger.getVerifiedWarpMessage(messageIndex);
        if (!valid) {
            revert ACP99Manager__InvalidWarpMessage();
        }

        if (warpMessage.sourceChainID != warpMessenger.getBlockchainID()) {
            revert ACP99Manager__InvalidSourceChainID(warpMessage.sourceChainID);
        }
        if (warpMessage.originSenderAddress != address(0)) {
            revert ACP99Manager__InvalidOriginSenderAddress(warpMessage.originSenderAddress);
        }

        (bytes32 uptimeValidationID, uint64 uptime) =
            ValidatorMessages.unpackValidationUptimeMessage(warpMessage.payload);
        if (uptimeValidationID != validationID) {
            revert ACP99Manager__InvalidUptimeValidationID(uptimeValidationID);
        }

        uint256 validationPeriodIndex = validation.periods.length - 1;
        ValidationPeriod storage currentPeriod = validation.periods[validationPeriodIndex];
        if (validationPeriodIndex > 0) {
            // Compute the uptime of the current period by removing the time difference between the current and previous period
            ValidationPeriod storage previousPeriod = validation.periods[validationPeriodIndex - 1];
            currentPeriod.uptimeSeconds =
                uptime - (currentPeriod.startTime - previousPeriod.startTime);
        } else {
            currentPeriod.uptimeSeconds = uptime;
        }
    }

    function _getValidationUptimeInfo(
        Validation storage validation,
        uint256 nonce
    ) private view returns (IACP99Manager.ValidatorUptimeInfo memory) {
        // Compute the active and uptime seconds of the validator during all periods
        uint64 totalActiveSeconds;
        uint64 totalUptimeSeconds;
        uint256 totalActiveWeightSeconds;
        uint256 totalUptimeWeightSeconds;
        for (uint256 i; i <= nonce; ++i) {
            // If the period is not yet started, skip it
            if (validation.periods[i].startTime == 0) {
                continue;
            }
            // If the period is not yet ended, use the current time as the end time
            uint64 periodEndTime = validation.periods[i].endTime == 0
                ? uint64(block.timestamp)
                : validation.periods[i].endTime;

            uint64 periodDuration = periodEndTime - validation.periods[i].startTime;
            uint64 periodUptimeSeconds = validation.periods[i].uptimeSeconds;
            totalActiveSeconds += periodDuration;
            totalUptimeSeconds += periodUptimeSeconds;
            totalActiveWeightSeconds +=
                uint256(validation.periods[i].weight) * uint256(periodDuration);
            totalUptimeWeightSeconds +=
                uint256(validation.periods[i].weight) * uint256(periodUptimeSeconds);
        }

        IACP99Manager.ValidatorUptimeInfo memory uptimeInfo = IACP99Manager.ValidatorUptimeInfo({
            activeSeconds: totalActiveSeconds,
            uptimeSeconds: totalUptimeSeconds,
            activeWeightSeconds: totalActiveWeightSeconds,
            uptimeWeightSeconds: totalUptimeWeightSeconds
        });

        return uptimeInfo;
    }

    function _notifySecurityModuleValidatorWeightUpdate(
        bytes32 validationID,
        uint64 nonce,
        uint64 weight
    ) private {
        Validation storage validation = l1Validations[validationID];

        IACP99Manager.ValidatorUptimeInfo memory uptimeInfo =
            _getValidationUptimeInfo(validation, nonce - 1);

        IACP99SecurityModule.ValidatorWeightChangeInfo memory validatorWeightChangeInfo =
        IACP99SecurityModule.ValidatorWeightChangeInfo({
            nodeID: validation.nodeID,
            validationID: validationID,
            nonce: nonce,
            newWeight: weight,
            uptimeInfo: uptimeInfo
        });

        securityModule.handleValidatorWeightChange(validatorWeightChangeInfo);
    }

    /// @inheritdoc IACP99Manager
    function getSecurityModule() external view returns (address) {
        return address(securityModule);
    }

    /// @inheritdoc IACP99Manager
    function getValidatorActiveValidation(
        bytes memory nodeID
    ) external view returns (bytes32) {
        if (!activeValidators.contains(bytes32(nodeID))) {
            revert ACP99Manager__NodeIDNotActiveValidator(nodeID);
        }

        return activeValidators.get(bytes32(nodeID));
    }

    /// @inheritdoc IACP99Manager
    function getActiveValidatorSet() external view returns (bytes32[] memory) {
        return activeValidators.keys();
    }

    /// @inheritdoc IACP99Manager
    function getValidation(
        bytes32 validationID
    ) external view returns (Validation memory) {
        return l1Validations[validationID];
    }

    /// @inheritdoc IACP99Manager
    function getValidationUptimeInfo(
        bytes32 validationID
    ) external view returns (IACP99Manager.ValidatorUptimeInfo memory) {
        Validation storage validation = l1Validations[validationID];

        return _getValidationUptimeInfo(validation, validation.periods.length - 1);
    }

    /// @inheritdoc IACP99Manager
    function getValidatorValidations(
        bytes memory nodeID
    ) external view returns (bytes32[] memory) {
        return l1ValidatorValidations[bytes32(nodeID)];
    }
}

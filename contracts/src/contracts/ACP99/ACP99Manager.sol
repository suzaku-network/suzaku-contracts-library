// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

// Compatible with OpenZeppelin Contracts ^4.9.0

pragma solidity 0.8.18;

import {IACP99Manager} from "../../interfaces/ACP99/IACP99Manager.sol";
import {IACP99SecurityModule} from "../../interfaces/ACP99/IACP99SecurityModule.sol";
import {ValidatorMessages} from "./ValidatorMessages.sol";
import {
    IWarpMessenger,
    WarpMessage
} from "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {Ownable2Step} from "@openzeppelin/contracts@4.9.6/access/Ownable2Step.sol";

import {SafeMath} from "@openzeppelin/contracts@4.9.6/utils/math/SafeMath.sol";
import {EnumerableMap} from "@openzeppelin/contracts@4.9.6/utils/structs/EnumerableMap.sol";

/// @custom:security-contact security@suzaku.network
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
     * @notice The active validators of the Subnet
     * @notice NodeID => validationID
     */
    // mapping(bytes32 => bytes32) public activeValidators;
    EnumerableMap.Bytes32ToBytes32Map private activeValidators;

    /// @notice The total weight of the current Subnet validator set
    uint64 public subnetTotalWeight;

    /**
     * @notice The list of validationIDs associated with a validator of the Subnet
     * @notice NodeID => validationID[]
     */
    mapping(bytes32 => bytes32[]) private subnetValidatorValidations;

    /**
     * @notice The validation corresponding to each validationID
     * @notice validationID => SubnetValidation
     */
    mapping(bytes32 => Validation) private subnetValidations;

    /**
     * @notice The registration message corresponding to a validationID such that it can be re-sent
     * @notice validationID => messageBytes
     */
    mapping(bytes32 => bytes) public pendingRegisterValidationMessages;

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
    function setSecurityModule(address securityModule_) external onlyOwner {
        if (securityModule_ == address(0)) {
            revert ACP99Manager__ZeroAddressSecurityModule();
        }

        securityModule = IACP99SecurityModule(securityModule_);
        emit SetSecurityModule(securityModule_);
    }

    /// @inheritdoc IACP99Manager
    function initializeValidatorSet(
        ValidatorMessages.SubnetConversionData calldata subnetConversionData,
        uint32 messageIndex
    ) external {
        if (initializedValidatorSet) {
            revert ACP99Manager__ValidatorSetAlreadyInitialized();
        }
        // Check that the blockchainID and validator manager address in the subnetConversionData correspond to this contract.
        if (subnetConversionData.validatorManagerBlockchainID != warpMessenger.getBlockchainID()) {
            revert ACP99Manager__InvalidManagerBlockchainID(
                subnetConversionData.validatorManagerBlockchainID, warpMessenger.getBlockchainID()
            );
        }
        if (address(subnetConversionData.validatorManagerAddress) != address(this)) {
            revert ACP99Manager__InvalidManagerAddress(
                subnetConversionData.validatorManagerAddress, address(this)
            );
        }

        uint256 numInitialValidators = subnetConversionData.initialValidators.length;

        uint64 totalWeight;
        for (uint32 i; i < numInitialValidators; ++i) {
            ValidatorMessages.InitialValidator memory initialValidator =
                subnetConversionData.initialValidators[i];
            bytes32 nodeID = initialValidator.nodeID;

            if (activeValidators.contains(nodeID)) {
                revert ACP99Manager__NodeAlreadyValidator(nodeID);
            }

            // Validation ID of the initial validators is the sha256 hash of the
            // convert Subnet tx ID and the index of the initial validator.
            bytes32 validationID =
                sha256(abi.encodePacked(subnetConversionData.convertSubnetTxID, i));

            // Save the initial validator as an active validator.

            activeValidators.set(nodeID, validationID);
            Validation storage validation = subnetValidations[validationID];
            validation.status = ValidationStatus.Active;
            validation.nodeID = initialValidator.nodeID;
            validation.startTime = uint64(block.timestamp);
            validation.periods.push(
                IACP99Manager.ValidationPeriod({
                    weight: initialValidator.weight,
                    startTime: uint64(block.timestamp),
                    endTime: 0
                })
            );
            totalWeight += initialValidator.weight;

            emit RegisterInitialValidator(
                initialValidator.nodeID, validationID, initialValidator.weight
            );
        }
        subnetTotalWeight = totalWeight;

        // Verify that the sha256 hash of the Subnet conversion data matches with the Warp message's subnetConversionID.
        WarpMessage memory warpMessage = _getPChainWarpMessage(messageIndex);
        // Parse the Warp message into SubnetConversionMessage
        bytes32 messageSubnetConversionID =
            ValidatorMessages.unpackSubnetConversionMessage(warpMessage.payload);
        bytes memory encodedConversion =
            ValidatorMessages.packSubnetConversionData(subnetConversionData);
        bytes32 subnetConversionID = sha256(encodedConversion);
        if (subnetConversionID != messageSubnetConversionID) {
            revert ACP99Manager__InvalidSubnetConversionID(
                subnetConversionID, messageSubnetConversionID
            );
        }

        initializedValidatorSet = true;
    }

    /// @inheritdoc IACP99Manager
    function initiateValidatorRegistration(
        bytes32 nodeID,
        uint64 weight,
        uint64 registrationExpiry,
        bytes memory blsPublicKey
    ) external onlySecurityModule returns (bytes32) {
        // Ensure the registration expiry is in a valid range.
        if (registrationExpiry < block.timestamp || registrationExpiry > block.timestamp + 2 days) {
            revert ACP99Manager__InvalidExpiry(registrationExpiry, block.timestamp);
        }

        // Ensure the nodeID is not the zero address, and is not already an active validator.
        if (nodeID == bytes32(0)) {
            revert ACP99Manager__ZeroNodeID();
        }
        if (activeValidators.contains(nodeID)) {
            revert ACP99Manager__NodeAlreadyValidator(nodeID);
        }

        // Ensure the signature is the proper length. The EVM does not provide an Ed25519 precompile to
        // validate the signature, but the P-Chain will validate the signature. If the signature is invalid,
        // the P-Chain will reject the registration, and the stake can be returned to the staker after the registration
        // expiry has passed.
        if (blsPublicKey.length != 48) {
            revert ACP99Manager__InvalidSignatureLength(blsPublicKey.length);
        }

        (bytes32 validationID, bytes memory registrationMessage) = ValidatorMessages
            .packRegisterSubnetValidatorMessage(
            ValidatorMessages.ValidationPeriod({
                subnetID: subnetID,
                nodeID: nodeID,
                weight: weight,
                registrationExpiry: registrationExpiry,
                blsPublicKey: blsPublicKey
            })
        );

        pendingRegisterValidationMessages[validationID] = registrationMessage;
        Validation storage validation = subnetValidations[validationID];
        validation.status = ValidationStatus.Registering;
        validation.nodeID = nodeID;
        validation.periods.push(ValidationPeriod({weight: weight, startTime: 0, endTime: 0}));
        subnetValidatorValidations[nodeID].push(validationID);

        bytes32 registrationMessageID = warpMessenger.sendWarpMessage(registrationMessage);

        emit InitiateValidatorRegistration(
            nodeID, validationID, registrationMessageID, weight, registrationExpiry
        );

        return validationID;
    }

    /// @inheritdoc IACP99Manager
    function resendValidatorRegistrationMessage(bytes32 validationID) external returns (bytes32) {
        if (
            pendingRegisterValidationMessages[validationID].length == 0
                || subnetValidations[validationID].status != ValidationStatus.Registering
        ) {
            revert ACP99Manager__InvalidValidationID(validationID);
        }

        return warpMessenger.sendWarpMessage(pendingRegisterValidationMessages[validationID]);
    }

    /// @inheritdoc IACP99Manager
    function completeValidatorRegistration(uint32 messageIndex) external {
        WarpMessage memory warpMessage = _getPChainWarpMessage(messageIndex);

        (bytes32 validationID, bool validRegistration) =
            ValidatorMessages.unpackSubnetValidatorRegistrationMessage(warpMessage.payload);
        if (!validRegistration) {
            revert ACP99Manager__InvalidRegistration();
        }
        Validation storage validation = subnetValidations[validationID];

        if (
            pendingRegisterValidationMessages[validationID].length == 0
                || validation.status != ValidationStatus.Registering
        ) {
            revert ACP99Manager__InvalidValidationID(validationID);
        }

        delete pendingRegisterValidationMessages[validationID];

        validation.status = ValidationStatus.Active;
        validation.startTime = uint64(block.timestamp);
        validation.periods[0].startTime = uint64(block.timestamp);
        activeValidators.set(validation.nodeID, validationID);
        subnetTotalWeight += validation.periods[0].weight;

        // Notify the SecurityModule of the validator registration
        securityModule.handleValidatorRegistration(
            IACP99SecurityModule.ValidatiorRegistrationInfo({
                nodeID: validation.nodeID,
                validationID: validationID,
                weight: validation.periods[0].weight,
                startTime: validation.startTime
            })
        );

        emit CompleteValidatorRegistration(
            validation.nodeID, validationID, validation.periods[0].weight
        );
    }

    /// @inheritdoc IACP99Manager
    function initiateValidatorWeightUpdate(
        bytes32 nodeID,
        uint64 weight,
        bool includesUptimeProof,
        uint32 messageIndex
    ) external onlySecurityModule {
        if (!activeValidators.contains(nodeID)) {
            revert ACP99Manager__NodeIDNotActiveValidator(nodeID);
        }

        bytes32 validationID = activeValidators.get(nodeID);
        Validation storage validation = subnetValidations[validationID];

        // Verify the uptime proof if it is included
        uint64 uptimeSeconds;
        if (includesUptimeProof) {
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
            uptimeSeconds = uptime;
        }

        validation.uptimeSeconds = uptimeSeconds;
        ValidationPeriod storage currentPeriod = validation.periods[validation.periods.length - 1];
        currentPeriod.endTime = uint64(block.timestamp);
        validation.activeSeconds += currentPeriod.endTime - currentPeriod.startTime;

        if (weight > 0) {
            validation.status = ValidationStatus.Updating;
            // The startTime is set to 0 to indicate that the period is not yet started
            validation.periods.push(ValidationPeriod({weight: weight, startTime: 0, endTime: 0}));
        } else {
            // If the weight is 0, the validator is being removed
            validation.status = ValidationStatus.Removing;
            validation.endTime = uint64(block.timestamp);
            activeValidators.remove(validation.nodeID);
        }

        bytes memory setValidatorWeightPayload = ValidatorMessages
            .packSetSubnetValidatorWeightMessage(
            validationID, uint64(validation.periods.length), weight
        );
        bytes32 setValidatorWeightMessageID =
            warpMessenger.sendWarpMessage(setValidatorWeightPayload);

        emit InitiateValidatorWeightUpdate(
            nodeID, validationID, setValidatorWeightMessageID, weight
        );
    }

    /// @inheritdoc IACP99Manager
    function completeValidatorWeightUpdate(uint32 messageIndex) external {
        WarpMessage memory warpMessage = _getPChainWarpMessage(messageIndex);
        (bytes32 validationID, uint64 nonce, uint64 weight) =
            ValidatorMessages.unpackSetSubnetValidatorWeightMessage(warpMessage.payload);
        Validation storage validation = subnetValidations[validationID];
        if (
            validation.status != ValidationStatus.Updating
                && validation.status != ValidationStatus.Removing
        ) {
            revert ACP99Manager__InvalidValidationID(validationID);
        }

        if (weight == 0) {
            if (nonce != (validation.periods.length)) {
                revert ACP99Manager__InvalidSetSubnetValidatorWeightNonce(
                    nonce, uint64(validation.periods.length)
                );
            }
            validation.status = ValidationStatus.Completed;
            subnetTotalWeight -= validation.periods[nonce - 1].weight;
        } else {
            if (nonce != (validation.periods.length - 1)) {
                revert ACP99Manager__InvalidSetSubnetValidatorWeightNonce(
                    nonce, uint64(validation.periods.length - 1)
                );
            }
            validation.status = ValidationStatus.Active;
            validation.periods[nonce].startTime = uint64(block.timestamp);
            subnetTotalWeight +=
                validation.periods[nonce].weight - validation.periods[nonce - 1].weight;
        }

        _notifySecurityModuleValidatorWeightUpdate(validationID, nonce, weight);

        emit CompleteValidatorWeightUpdate(validation.nodeID, validationID, nonce, weight);
    }

    /// @dev Get the Warp message from the P-Chain and verify that it is valid and from the P-Chain
    function _getPChainWarpMessage(uint32 messageIndex) private view returns (WarpMessage memory) {
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

    function _notifySecurityModuleValidatorWeightUpdate(
        bytes32 validationID,
        uint64 nonce,
        uint64 weight
    ) private {
        Validation storage validation = subnetValidations[validationID];

        // Compute the average weight of the validator during all periods
        uint256 averageWeight;
        for (uint256 i = 0; i < nonce; i++) {
            uint64 periodDuration = validation.periods[i].endTime - validation.periods[i].startTime;
            averageWeight += validation.periods[i].weight * periodDuration;
        }
        averageWeight = SafeMath.div(averageWeight, validation.activeSeconds);

        IACP99SecurityModule.ValidatorUptimeInfo memory uptimeInfo = IACP99SecurityModule
            .ValidatorUptimeInfo({
            activeSeconds: validation.activeSeconds,
            uptimeSeconds: validation.uptimeSeconds,
            averageWeight: uint64(averageWeight)
        });

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
    function getValidatorActiveValidation(bytes32 nodeID) external view returns (bytes32) {
        if (!activeValidators.contains(nodeID)) {
            revert ACP99Manager__NodeIDNotActiveValidator(nodeID);
        }

        return activeValidators.get(nodeID);
    }

    /// @inheritdoc IACP99Manager
    function getActiveValidatorSet() external view returns (bytes32[] memory) {
        return activeValidators.keys();
    }

    /// @inheritdoc IACP99Manager
    function getValidation(bytes32 validationID) external view returns (Validation memory) {
        return subnetValidations[validationID];
    }

    /// @inheritdoc IACP99Manager
    function getValidatorValidations(bytes32 nodeID) external view returns (bytes32[] memory) {
        return subnetValidatorValidations[nodeID];
    }
}

// (c) 2024, ADDPHO All rights reserved.
// See the file LICENSE_BUSL for licensing terms.

// SPDX-License-Identifier: BUSL-1.1

// Compatible with OpenZeppelin Contracts ^4.9.0

pragma solidity 0.8.18;

import {IACP99Manager} from "../../interfaces/ACP99/IACP99Manager.sol";
import {SubnetValidatorMessages} from "./SubnetValidatorMessages.sol";
import {
    IWarpMessenger,
    WarpMessage
} from "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {Ownable} from "@openzeppelin/contracts@4.9.6/access/Ownable.sol";
import {EnumerableMap} from "@openzeppelin/contracts@4.9.6/utils/structs/EnumerableMap.sol";

/// @custom:security-contact security@suzaku.network
contract ACP99Manager is Ownable, IACP99Manager {
    using EnumerableMap for EnumerableMap.Bytes32ToBytes32Map;

    bytes32 private constant P_CHAIN_ID_HEX = bytes32(0);
    address private constant WARP_MESSENGER_ADDRESS = 0x0200000000000000000000000000000000000005;

    /// @notice The WarpMessenger contract
    IWarpMessenger private immutable warpMessenger;

    /// @notice The ID of the Subnet tied to this manager
    bytes32 public immutable subnetID;

    /// @notice The address of the security module attached to this manager
    address public securityModule;

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
            revert ACP99Manager__OnlySecurityModule(msg.sender, securityModule);
        }
        _;
    }

    constructor(bytes32 subnetID_, address securityModule_) Ownable() {
        if (securityModule_ == address(0)) {
            revert ACP99Manager__ZeroAddressSecurityModule();
        }

        warpMessenger = IWarpMessenger(WARP_MESSENGER_ADDRESS);
        subnetID = subnetID_;
        securityModule = securityModule_;
    }

    /**
     * @notice Set the address of the security module attached to this manager
     * @param securityModule_ The address of the security module
     */
    function setSecurityModule(address securityModule_) external onlyOwner {
        if (securityModule_ == address(0)) {
            revert ACP99Manager__ZeroAddressSecurityModule();
        }

        securityModule = securityModule_;
        emit SetSecurityModule(securityModule_);
    }

    /// @inheritdoc IACP99Manager
    function initiateValidatorRegistration(
        bytes32 nodeID,
        uint64 weight,
        uint64 registrationExpiry,
        bytes memory signature
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
            revert ACP99Manager__NodeIDAlreadyValidator(nodeID);
        }

        // Ensure the signature is the proper length. The EVM does not provide an Ed25519 precompile to
        // validate the signature, but the P-Chain will validate the signature. If the signature is invalid,
        // the P-Chain will reject the registration, and the stake can be returned to the staker after the registration
        // expiry has passed.
        if (signature.length != 64) {
            revert ACP99Manager__InvalidSignatureLength(signature.length);
        }

        (bytes32 validationID, bytes memory registrationMessage) = SubnetValidatorMessages
            .packRegisterSubnetValidatorMessage(
            SubnetValidatorMessages.ValidationInfo({
                subnetID: subnetID,
                nodeID: nodeID,
                weight: weight,
                registrationExpiry: registrationExpiry,
                signature: signature
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

        (bytes32 validationID, bool validRegistration) =
            SubnetValidatorMessages.unpackSubnetValidatorRegistrationMessage(warpMessage.payload);
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

        // TODO: Notify the SecurityModule of the validator registration

        emit CompleteValidatorRegistration(
            validation.nodeID, validationID, validation.periods[0].weight, uint64(block.timestamp)
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
                SubnetValidatorMessages.unpackValidationUptimeMessage(warpMessage.payload);
            if (uptimeValidationID != validationID) {
                revert ACP99Manager__InvalidUptimeValidationID(uptimeValidationID);
            }
            uptimeSeconds = uptime;
        }

        validation.periods[validation.periods.length - 1].endTime = uint64(block.timestamp);
        validation.uptimeSeconds = uptimeSeconds;

        if (weight > 0) {
            validation.status = ValidationStatus.Updating;
            // The startTime is set to 0 to indicate that the period is not yet started
            validation.periods.push(ValidationPeriod({weight: weight, startTime: 0, endTime: 0}));
        } else {
            // If the weight is 0, the validator is being removed
            validation.status = ValidationStatus.Removing;
            validation.endTime = uint64(block.timestamp);
        }

        bytes memory setValidatorWeightPayload = SubnetValidatorMessages
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
        // Get the Warp message.
        (WarpMessage memory warpMessage, bool valid) =
            warpMessenger.getVerifiedWarpMessage(messageIndex);
        if (!valid) {
            revert ACP99Manager__InvalidWarpMessage();
        }

        (bytes32 validationID, uint64 nonce, uint64 weight) =
            SubnetValidatorMessages.unpackSetSubnetValidatorWeightMessage(warpMessage.payload);
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

            // Remove the validator from the active set
            activeValidators.remove(validation.nodeID);
            subnetTotalWeight -= validation.periods[nonce - 1].weight;
            validation.status = ValidationStatus.Completed;
        } else {
            if (nonce != (validation.periods.length - 1)) {
                revert ACP99Manager__InvalidSetSubnetValidatorWeightNonce(
                    nonce, uint64(validation.periods.length - 1)
                );
            }
            validation.status = ValidationStatus.Active;
            validation.periods[nonce].startTime = uint64(block.timestamp);
        }

        // TODO: Notify the SecurityModule of the validator update

        emit CompleteValidatorWeightUpdate(validation.nodeID, validationID, nonce, weight);
    }

    /// @inheritdoc IACP99Manager
    function getSubnetValidatorActiveValidation(bytes32 nodeID) external view returns (bytes32) {
        return activeValidators.get(nodeID);
    }

    /// @inheritdoc IACP99Manager
    function getSubnetActiveValidatorSet() external view returns (bytes32[] memory) {
        return activeValidators.keys();
    }

    function getSubnetValidation(bytes32 validationID) external view returns (Validation memory) {
        return subnetValidations[validationID];
    }

    /// @inheritdoc IACP99Manager
    function getSubnetValidatorValidations(bytes32 nodeID)
        external
        view
        returns (bytes32[] memory)
    {
        return subnetValidatorValidations[nodeID];
    }
}

// (c) 2024, ADDPHO All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import {IValidatorSetManager} from "../../interfaces/ValidatorSetManager/IValidatorSetManager.sol";
import {SubnetValidatorMessages} from "./SubnetValidatorMessages.sol";
import {
    IWarpMessenger,
    WarpMessage
} from "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {Ownable} from "@openzeppelin/contracts@4.8.1/access/Ownable.sol";

/// @custom:security-contact security@suzaku.network
contract ValidatorSetManager is Ownable, IValidatorSetManager {
    bytes32 private constant P_CHAIN_ID_HEX = bytes32(0);
    address private constant WARP_MESSENGER_ADDRESS = 0x0200000000000000000000000000000000000005;

    /// @notice The WarpMessenger contract
    IWarpMessenger private immutable warpMessenger;

    /// @notice The ID of the Subnet tied to this manager
    bytes32 public immutable subnetID;

    /// @notice The address of the security module attached to this manager
    address public securityModule;

    /// @notice The current Subnet validator set (list of NodeIDs)
    bytes32[] private subnetCurrentValidatorSet;

    /**
     * @notice The active validators of the Subnet
     * @notice NodeID => validationID
     */
    mapping(bytes32 => bytes32) public activeValidators;

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
            revert ValidatorSetManager__OnlySecurityModule(msg.sender, securityModule);
        }
        _;
    }

    constructor(bytes32 subnetID_, address securityModule_) Ownable() {
        warpMessenger = IWarpMessenger(WARP_MESSENGER_ADDRESS);
        subnetID = subnetID_;
        securityModule = securityModule_;
    }

    /**
     * @notice Set the address of the security module attached to this manager
     * @param securityModule_ The address of the security module
     */
    function setSecurityModule(address securityModule_) external onlyOwner {
        securityModule = securityModule_;
        emit SetSecurityModule(securityModule_);
    }

    /// @inheritdoc IValidatorSetManager
    function initiateValidatorRegistration(
        bytes32 nodeID,
        uint64 weight,
        uint64 registrationExpiry,
        bytes memory signature
    ) external onlySecurityModule returns (bytes32) {
        // Ensure the registration expiry is in a valid range.
        if (registrationExpiry < block.timestamp || registrationExpiry > block.timestamp + 2 days) {
            revert ValidatorSetManager__InvalidExpiry(registrationExpiry, block.timestamp);
        }

        // Ensure the nodeID is not the zero address, and is not already an active validator.
        if (nodeID == bytes32(0)) {
            revert ValidatorSetManager__ZeroNodeID();
        }
        if (activeValidators[nodeID] != bytes32(0)) {
            revert ValidatorSetManager__NodeIDAlreadyValidator(nodeID);
        }

        // Ensure the signature is the proper length. The EVM does not provide an Ed25519 precompile to
        // validate the signature, but the P-Chain will validate the signature. If the signature is invalid,
        // the P-Chain will reject the registration, and the stake can be returned to the staker after the registration
        // expiry has passed.
        if (signature.length != 64) {
            revert ValidatorSetManager__InvalidSignatureLength(signature.length);
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
        bytes32 registrationMessageID = warpMessenger.sendWarpMessage(registrationMessage);

        Validation storage validation = subnetValidations[validationID];
        validation.status = ValidationStatus.Registering;
        validation.nodeID = nodeID;
        validation.periods.push(
            ValidationPeriod({weight: weight, startTime: 0, endTime: 0, uptimeSeconds: 0})
        );

        subnetValidatorValidations[nodeID].push(validationID);

        emit InitiateValidatorRegistration(
            nodeID, validationID, registrationMessageID, weight, registrationExpiry
        );

        return validationID;
    }

    /// @inheritdoc IValidatorSetManager
    function resendValidatorRegistrationMessage(bytes32 validationID) external {
        if (
            pendingRegisterValidationMessages[validationID].length == 0
                || subnetValidations[validationID].status != ValidationStatus.Registering
        ) {
            revert ValidatorSetManager__InvalidValidationID(validationID);
        }

        warpMessenger.sendWarpMessage(pendingRegisterValidationMessages[validationID]);
    }

    /// @inheritdoc IValidatorSetManager
    function completeValidatorRegistration(uint32 messageIndex) external {
        (WarpMessage memory warpMessage, bool valid) =
            warpMessenger.getVerifiedWarpMessage(messageIndex);
        if (!valid) {
            revert ValidatorSetManager__InvalidWarpMessage();
        }

        if (warpMessage.sourceChainID != P_CHAIN_ID_HEX) {
            revert ValidatorSetManager__InvalidSourceChainID(warpMessage.sourceChainID);
        }
        if (warpMessage.originSenderAddress != address(0)) {
            revert ValidatorSetManager__InvalidOriginSenderAddress(warpMessage.originSenderAddress);
        }

        (bytes32 validationID, bool validRegistration) =
            SubnetValidatorMessages.unpackSubnetValidatorRegistrationMessage(warpMessage.payload);
        if (!validRegistration) {
            revert ValidatorSetManager__InvalidRegistration();
        }
        if (
            pendingRegisterValidationMessages[validationID].length == 0
                || subnetValidations[validationID].status != ValidationStatus.Registering
        ) {
            revert ValidatorSetManager__InvalidValidationID(validationID);
        }

        delete pendingRegisterValidationMessages[validationID];

        subnetValidations[validationID].status = ValidationStatus.Active;
        subnetValidations[validationID].periods[0].startTime = uint64(block.timestamp);
        activeValidators[subnetValidations[validationID].nodeID] = validationID;
        subnetTotalWeight += subnetValidations[validationID].periods[0].weight;
        subnetCurrentValidatorSet.push(subnetValidations[validationID].nodeID);

        // TODO: Notify the SecurityModule of the validator registration

        emit CompleteValidatorRegistration(
            validationID,
            subnetValidations[validationID].nodeID,
            subnetValidations[validationID].periods[0].weight,
            uint64(block.timestamp)
        );
    }

    /// @inheritdoc IValidatorSetManager
    function initiateValidatorWeightUpdate(
        bytes32 nodeID,
        uint64 weight,
        bool includeUptimeProof,
        uint32 messageIndex
    ) external onlySecurityModule {
        if (activeValidators[nodeID] == bytes32(0)) {
            revert ValidatorSetManager__NodeIDNotActiveValidator(nodeID);
        }

        bytes32 validationID = activeValidators[nodeID];
        Validation storage validation = subnetValidations[validationID];

        // Verify the uptime proof if it is included
        uint64 uptimeSeconds;
        if (includeUptimeProof) {
            (WarpMessage memory warpMessage, bool valid) =
                warpMessenger.getVerifiedWarpMessage(messageIndex);
            if (!valid) {
                revert ValidatorSetManager__InvalidWarpMessage();
            }

            if (warpMessage.sourceChainID != warpMessenger.getBlockchainID()) {
                revert ValidatorSetManager__InvalidSourceChainID(warpMessage.sourceChainID);
            }
            if (warpMessage.originSenderAddress != address(0)) {
                revert ValidatorSetManager__InvalidOriginSenderAddress(
                    warpMessage.originSenderAddress
                );
            }

            (bytes32 uptimeValidationID, uint64 uptime) =
                SubnetValidatorMessages.unpackValidationUptimeMessage(warpMessage.payload);
            if (uptimeValidationID != validationID) {
                revert ValidatorSetManager__InvalidUptimeValidationID(uptimeValidationID);
            }
            uptimeSeconds = uptime - validation.totalUptimeSeconds;
        }

        bytes memory setValidatorWeightPayload = SubnetValidatorMessages
            .packSetSubnetValidatorWeightMessage(
            validationID, uint64(validation.periods.length), weight
        );
        bytes32 setValidatorWeightMessageID =
            warpMessenger.sendWarpMessage(setValidatorWeightPayload);

        validation.periods[validation.periods.length - 1].endTime = uint64(block.timestamp);
        validation.periods[validation.periods.length - 1].uptimeSeconds += int64(uptimeSeconds);
        validation.totalUptimeSeconds += uptimeSeconds;
        validation.status = ValidationStatus.Updating;

        if (weight > 0) {
            // The startTime is set to 0 to indicate that the period is not yet started
            validation.periods.push(
                ValidationPeriod({weight: weight, startTime: 0, endTime: 0, uptimeSeconds: 0})
            );
        }

        emit InitiateValidatorWeightUpdate(
            nodeID, validationID, setValidatorWeightMessageID, weight
        );
    }

    /// @inheritdoc IValidatorSetManager
    function completeValidatorWeightUpdate(uint32 messageIndex) external {
        // Get the Warp message.
        (WarpMessage memory warpMessage, bool valid) =
            warpMessenger.getVerifiedWarpMessage(messageIndex);
        if (!valid) {
            revert ValidatorSetManager__InvalidWarpMessage();
        }

        (bytes32 validationID, uint64 nonce, uint64 weight) =
            SubnetValidatorMessages.unpackSetSubnetValidatorWeightMessage(warpMessage.payload);
        Validation storage validation = subnetValidations[validationID];
        if (validation.status != ValidationStatus.Updating) {
            revert ValidatorSetManager__InvalidValidationID(validationID);
        }

        if (weight == 0) {
            if (nonce != validation.periods.length) {
                revert ValidatorSetManager__InvalidSetSubnetValidatorWeightNonce(
                    nonce, uint64(validation.periods.length)
                );
            }

            // Remove the validator from the active set
            delete activeValidators[validation.nodeID];
            subnetTotalWeight -= validation.periods[validation.periods.length - 1].weight;
            validation.status = ValidationStatus.Completed;
            // Update the current validator set
            for (uint256 i = 0; i < subnetCurrentValidatorSet.length; i++) {
                if (subnetCurrentValidatorSet[i] == validation.nodeID) {
                    subnetCurrentValidatorSet[i] =
                        subnetCurrentValidatorSet[subnetCurrentValidatorSet.length - 1];
                    subnetCurrentValidatorSet.pop();
                    break;
                }
            }
        } else {
            if (nonce != (validation.periods.length - 1)) {
                revert ValidatorSetManager__InvalidSetSubnetValidatorWeightNonce(
                    nonce, uint64(validation.periods.length - 1)
                );
            }

            validation.periods[validation.periods.length - 1].startTime = uint64(block.timestamp);
            // Remove the time between the end of the last period and now from the uptime
            validation.periods[validation.periods.length - 1].uptimeSeconds = int64(
                validation.periods[validation.periods.length - 2].endTime
            ) - int64(uint64(block.timestamp));
        }
    }

    /// @inheritdoc IValidatorSetManager
    function getSubnetCurrentValidatorSet() external view returns (bytes32[] memory) {
        return subnetCurrentValidatorSet;
    }

    function getSubnetValidation(bytes32 validationID) external view returns (Validation memory) {
        return subnetValidations[validationID];
    }

    /// @inheritdoc IValidatorSetManager
    function getSubnetValidatorValidations(bytes32 nodeID)
        external
        view
        returns (bytes32[] memory)
    {
        return subnetValidatorValidations[nodeID];
    }

    // /// @inheritdoc IValidatorSetManager
    // function setSubnetValidatorManager(bytes32 blockchainID, address managerAddress) external {}
}
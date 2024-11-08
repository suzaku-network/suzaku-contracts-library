// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {
    ConversionData,
    ValidatorMessages
} from "@avalabs/teleporter/validator-manager/ValidatorMessages.sol";
import {
    InitialValidator,
    PChainOwner
} from "@avalabs/teleporter/validator-manager/interfaces/IValidatorManager.sol";

/*
 * @title IACP99Manager
 * @author ADDPHO
 * @notice The IACP99Manager interface is the interface for the ACP99Manager contract.
 * @custom:security-contact security@suzaku.network
 */
interface IACP99Manager {
    /// @notice Subnet validation status
    enum ValidationStatus {
        Registering,
        Active,
        Updating,
        Removing,
        Completed,
        Expired
    }

    /**
     * @notice Subnet validation
     * @param status The validation status
     * @param nodeID The NodeID of the validator
     * @param startTime The start time of the validation
     * @param endTime The end time of the validation
     * @param periods The list of validation periods.
     * The index is the nonce associated with the weight update.
     * @param activeSeconds The time during which the validator was active during this validation
     * @param uptimeSeconds The uptime of the validator for this validation
     */
    struct Validation {
        ValidationStatus status;
        bytes32 nodeID;
        ValidationPeriod[] periods;
        uint64 activeSeconds;
        uint64 uptimeSeconds;
    }

    /**
     * @notice Subnet validation period
     * @param weight The weight of the validator during the period
     * @param startTime The start time of the validation period
     * @param endTime The end time of the validation period (only ≠ 0 when the period is over)
     */
    struct ValidationPeriod {
        uint64 weight;
        uint64 startTime;
        uint64 endTime;
    }

    /// @notice Emitted when the security module address is set
    event SetSecurityModule(address indexed securityModule);
    /// @notice Emitted when an initial validator is registered
    event RegisterInitialValidator(
        bytes32 indexed nodeID, bytes32 indexed validationID, uint64 weight
    );
    /// @notice Emitted when a validator registration to the Subnet is initiated
    event InitiateValidatorRegistration(
        bytes32 indexed nodeID,
        bytes32 indexed validationID,
        bytes32 registrationMessageID,
        uint64 registrationExpiry,
        uint64 weight
    );
    /// @notice Emitted when a validator registration to the Subnet is completed
    event CompleteValidatorRegistration(
        bytes32 indexed nodeID, bytes32 indexed validationID, uint64 weight
    );
    /// @notice Emitted when a validator weight update is initiated
    event InitiateValidatorWeightUpdate(
        bytes32 indexed nodeID,
        bytes32 indexed validationID,
        bytes32 weightUpdateMessageID,
        uint64 weight
    );
    /// @notice Emitted when a validator weight update is completed
    event CompleteValidatorWeightUpdate(
        bytes32 indexed nodeID, bytes32 indexed validationID, uint64 nonce, uint64 weight
    );

    error ACP99Manager__ValidatorSetAlreadyInitialized();
    error ACP99Manager__InvalidSubnetConversionID(bytes32 conversionID, bytes32 messageConversionID);
    error ACP99Manager__InvalidManagerBlockchainID(
        bytes32 managerBlockchainID, bytes32 conversionBlockchainID
    );
    error ACP99Manager__InvalidManagerAddress(address managerAddress, address conversionAddress);
    error ACP99Manager__ZeroAddressSecurityModule();
    error ACP99Manager__OnlySecurityModule(address sender, address securityModule);
    error ACP99Manager__InvalidExpiry(uint64 expiry, uint256 timestamp);
    error ACP99Manager__ZeroNodeID();
    error ACP99Manager__NodeAlreadyValidator(bytes nodeID);
    error ACP99Manager__InvalidPChainOwnerThreshold(uint256 threshold, uint256 addressesLength);
    error ACP99Manager__PChainOwnerAddressesNotSorted();
    error ACP99Manager__InvalidSignatureLength(uint256 length);
    error ACP99Manager__InvalidValidationID(bytes32 validationID);
    error ACP99Manager__InvalidWarpMessage();
    error ACP99Manager__InvalidSourceChainID(bytes32 sourceChainID);
    error ACP99Manager__InvalidOriginSenderAddress(address originSenderAddress);
    error ACP99Manager__InvalidRegistration();
    error ACP99Manager__NodeIDNotActiveValidator(bytes nodeID);
    error ACP99Manager__InvalidUptimeValidationID(bytes32 validationID);
    error ACP99Manager__InvalidSetSubnetValidatorWeightNonce(uint64 nonce, uint64 currentNonce);

    /// @notice Get the ID of the Subnet tied to this manager
    function subnetID() external view returns (bytes32);

    /// @notice Get the address of the security module attached to this manager
    function getSecurityModule() external view returns (address);

    /// @notice Get the validation details for a given validation ID
    function getValidation(
        bytes32 validationID
    ) external view returns (Validation memory);

    /// @notice Get a Subnet validator's active validation ID
    function getValidatorActiveValidation(
        bytes memory nodeID
    ) external view returns (bytes32);

    /// @notice Get the current Subnet validator set (list of NodeIDs)
    function getActiveValidatorSet() external view returns (bytes32[] memory);

    /// @notice Get the total weight of the current L1 validator set
    function l1TotalWeight() external view returns (uint64);

    /// @notice Get the list of message IDs associated with a validator of the Subnet
    function getValidatorValidations(
        bytes memory nodeID
    ) external view returns (bytes32[] memory);

    /**
     * @notice Set the address of the security module attached to this manager
     * @param securityModule_ The address of the security module
     */
    function setSecurityModule(
        address securityModule_
    ) external;

    /**
     * @notice Verifies and sets the initial validator set for the chain through a P-Chain
     * SubnetConversionMessage.
     * @param conversionData The Subnet conversion message data used to recompute and verify against the subnetConversionID.
     * @param messsageIndex The index that contains the SubnetConversionMessage Warp message containing the subnetConversionID to be verified against the provided {subnetConversionData}
     */
    function initializeValidatorSet(
        ConversionData calldata conversionData,
        uint32 messsageIndex
    ) external;

    /**
     * @notice Initiate a validator registration by issuing a RegisterSubnetValidatorTx Warp message
     * @param nodeID The ID of the node to add to the Subnet
     * @param blsPublicKey The BLS public key of the validator
     * @param registrationExpiry The time after which this message is invalid
     * @param remainingBalanceOwner The remaining balance owner of the validator
     * @param disableOwner The disable owner of the validator
     * @param weight The weight of the node on the Subnet
     */
    function initiateValidatorRegistration(
        bytes memory nodeID,
        bytes memory blsPublicKey,
        uint64 registrationExpiry,
        PChainOwner memory remainingBalanceOwner,
        PChainOwner memory disableOwner,
        uint64 weight
    ) external returns (bytes32);

    /**
     * @notice Resubmits a validator registration message to be sent to P-Chain.
     * Only necessary if the original message can't be delivered due to validator churn.
     * @param validationID The validationID attached to the registration message
     */
    function resendValidatorRegistrationMessage(
        bytes32 validationID
    ) external returns (bytes32);

    /**
     * @notice Completes the validator registration process by returning an acknowledgement of the registration of a
     * validationID from the P-Chain.
     * @param messageIndex The index of the Warp message to be received providing the acknowledgement.
     */
    function completeValidatorRegistration(
        uint32 messageIndex
    ) external;

    /**
     * @notice Initiate a validator weight update by issuing a SetSubnetValidatorWeightTx Warp message.
     * If the weight is 0, this initiates the removal of the validator from the Subnet. An uptime proof can be
     * included. This proof might be required to claim validator rewards (handled by the security module).
     * @param nodeID The ID of the node to modify
     * @param weight The new weight of the node on the Subnet
     * @param includesUptimeProof Whether the uptime proof is included in the message
     * @param messageIndex The index of the Warp message containing the uptime proof
     */
    function initiateValidatorWeightUpdate(
        bytes memory nodeID,
        uint64 weight,
        bool includesUptimeProof,
        uint32 messageIndex
    ) external;

    /**
     * @notice Completes the validator weight update process by returning an acknowledgement of the weight update of a
     * validationID from the P-Chain.
     * @param messageIndex The index of the Warp message to be received providing the acknowledgement.
     */
    function completeValidatorWeightUpdate(
        uint32 messageIndex
    ) external;
}

// (c) 2024, ADDPHO All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

/// @custom:security-contact security@suzaku.network
interface IValidatorSetManager {
    /// @notice Subnet validation status
    enum ValidationStatus {
        Registering,
        Active,
        Updating,
        Removing,
        Completed,
        Expired
    }

    // /**
    //  * @notice Subnet validator
    //  * @param messageID The Warp message ID corresponding to the RegisterSubnetValidatorTx that added the validator.
    //  * The message ID is needed to submit subsequent SetSubnetValidatorWeightTx.
    //  * @param nodeID The NodeID of the validator
    //  * @param nonce The nonce of the latest validator weight update
    //  * @param currentWeight The validator current weight
    //  * @param addTimestamp The timestamp the validator was added
    //  */
    // struct Validator {
    //     bytes32 messageID;
    //     bytes32 nodeID;
    //     uint64 nonce;
    //     uint64 currentWeight;
    //     uint64 addTimestamp;
    // }

    /**
     * @notice Subnet validation
     * @param status The validation status
     * @param nodeID The NodeID of the validator
     * @param periods The list of validation periods
     * The index is the nonce associated with the weight update.
     * @param totalUptimeSeconds The total uptime of the validator
     */
    struct Validation {
        ValidationStatus status;
        bytes32 nodeID;
        ValidationPeriod[] periods;
        uint64 totalUptimeSeconds;
    }

    /**
     * @notice Subnet validation period
     * @param weight The weight of the validator during the period
     * @param startTime The start time of the validation period
     * @param endTime The end time of the validation period (only ≠ 0 when the period is over)
     * @param uptimeSeconds The uptime of the validator during this validation period (only > 0 once the validation period is over)
     */
    struct ValidationPeriod {
        uint64 weight;
        uint64 startTime;
        uint64 endTime;
        int64 uptimeSeconds;
    }

    /// @notice Emitted when the security module address is set
    event SetSecurityModule(address indexed securityModule);
    /// @notice Emitted when a validator registration to the Subnet is initiated
    event InitiateValidatorRegistration(
        bytes32 indexed nodeID,
        bytes32 indexed validationID,
        bytes32 indexed registrationMessageID,
        uint64 weight,
        uint64 registrationExpiry
    );
    /// @notice Emitted when a validator registration to the Subnet is completed
    event CompleteValidatorRegistration(
        bytes32 indexed validationID,
        bytes32 nodeID,
        uint64 weight,
        uint64 validationPeriodStartTime
    );
    /// @notice Emitted when a validator weight update is initiated
    event InitiateValidatorWeightUpdate(
        bytes32 indexed nodeID,
        bytes32 indexed validationID,
        bytes32 indexed weightUpdateMessageID,
        uint64 weight
    );

    error ValidatorSetManager__OnlySecurityModule(address sender, address securityModule);
    error ValidatorSetManager__InvalidExpiry(uint64 expiry, uint256 timestamp);
    error ValidatorSetManager__ZeroNodeID();
    error ValidatorSetManager__NodeIDAlreadyValidator(bytes32 nodeID);
    error ValidatorSetManager__InvalidSignatureLength(uint256 length);
    error ValidatorSetManager__InvalidValidationID(bytes32 validationID);
    error ValidatorSetManager__InvalidWarpMessage();
    error ValidatorSetManager__InvalidSourceChainID(bytes32 sourceChainID);
    error ValidatorSetManager__InvalidOriginSenderAddress(address originSenderAddress);
    error ValidatorSetManager__InvalidRegistration();
    error ValidatorSetManager__NodeIDNotActiveValidator(bytes32 nodeID);
    error ValidatorSetManager__InvalidUptimeValidationID(bytes32 validationID);
    error ValidatorSetManager__InvalidSetSubnetValidatorWeightNonce(
        uint64 nonce, uint64 currentNonce
    );

    /// @notice Get the ID of the Subnet tied to this manager
    function subnetID() external view returns (bytes32);

    /// @notice Get the address of the security module attached to this manager
    function securityModule() external view returns (address);

    /// @notice Get the current Subnet validator set (list of NodeIDs)
    function getSubnetCurrentValidatorSet() external view returns (bytes32[] memory);

    /// @notice Get the total weight of the current Subnet validator set
    function subnetTotalWeight() external view returns (uint64);

    /// @notice Get the list of message IDs associated with a validator of the Subnet
    function getSubnetValidatorValidations(bytes32 nodeID)
        external
        view
        returns (bytes32[] memory);

    /**
     * @notice Initiate a validator registration by issuing a RegisterSubnetValidatorTx Warp message
     * @param nodeID The ID of the node to add to the Subnet
     * @param weight The weight of the node on the Subnet
     * @param expiry The time after which this message is invalid
     * @param signature The Ed25519 signature of [subnetID]+[nodeID]+[blsPublicKey]+[weight]+[timestamp]
     */
    function initiateValidatorRegistration(
        bytes32 nodeID,
        uint64 weight,
        uint64 expiry,
        bytes memory signature
    ) external returns (bytes32);

    /**
     * @notice Resubmits a validator registration message to be sent to P-Chain.
     * Only necessary if the original message can't be delivered due to validator churn.
     * @param validationID The validationID attached to the registration message
     */
    function resendValidatorRegistrationMessage(bytes32 validationID) external;

    /**
     * @notice Completes the validator registration process by returning an acknowledgement of the registration of a
     * validationID from the P-Chain.
     * @param messageIndex The index of the Warp message to be received providing the acknowledgement.
     */
    function completeValidatorRegistration(uint32 messageIndex) external;

    /**
     * @notice Initiate a validator weight update by issuing a SetSubnetValidatorWeightTx Warp message
     * @param nodeID The ID of the node to modify
     * @param weight The new weight of the node on the Subnet
     */
    function initiateValidatorWeightUpdate(
        bytes32 nodeID,
        uint64 weight,
        bool includeUptimeProof,
        uint32 messageIndex
    ) external;

    /**
     * @notice Completes the validator weight update process by returning an acknowledgement of the weight update of a
     * validationID from the P-Chain.
     * @param messageIndex The index of the Warp message to be received providing the acknowledgement.
     */
    function completeValidatorWeightUpdate(uint32 messageIndex) external;

    // /**
    //  * @notice Issue a SetSubnetValidatorManagerTx
    //  * @param blockchainID The ID of the chain on which the Subnet validator manager is located
    //  * @param managerAddress The address of the Subnet validator set manager
    //  */
    // function setSubnetManager(bytes32 blockchainID, address managerAddress) external;
}
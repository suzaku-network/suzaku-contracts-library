// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {IBalancerValidatorManager} from
    "../../../interfaces/ValidatorManager/IBalancerValidatorManager.sol";
import {ISecurityModule} from "../../../interfaces/ValidatorManager/ISecurityModule.sol";
import {PChainOwner} from "@avalabs/icm-contracts/validator-manager/interfaces/IACP99Manager.sol";
import {Ownable} from "@openzeppelin/contracts@5.0.2/access/Ownable.sol";
import {ERC165} from "@openzeppelin/contracts@5.0.2/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts@5.0.2/utils/introspection/IERC165.sol";

/**
 * @title PoASecurityModule
 * @notice Proof of Authority security module for the Balancer Validator Manager
 * @dev Manages validator initiation operations through the balancer validator manager while keeping
 * completion operations permissionless to ensure liveness.
 * @custom:security-contact security@suzaku.network
 */
contract PoASecurityModule is Ownable, ERC165, ISecurityModule {
    /// @notice Thrown when a zero address is provided where not allowed
    error ZeroAddress();

    /// @notice The Balancer Validator Manager contract this module controls
    IBalancerValidatorManager public immutable balancerValidatorManager;

    /**
     * @notice Initializes the PoA Security Module
     * @dev Sets the Balancer Validator Manager address and initial owner
     * @param balancerValidatorManagerAddress Address of the Balancer Validator Manager contract
     * @param initialOwner Address of the initial owner who can initiate validator operations
     */
    constructor(
        address balancerValidatorManagerAddress,
        address initialOwner
    ) Ownable(initialOwner) {
        if (balancerValidatorManagerAddress == address(0)) {
            revert ZeroAddress();
        }

        balancerValidatorManager = IBalancerValidatorManager(balancerValidatorManagerAddress);
    }

    /**
     * @notice Checks if the contract supports a given interface
     * @dev Implements ERC165 interface detection
     * @param interfaceId The interface identifier to check
     * @return True if the contract supports the interface, false otherwise
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override (ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(ISecurityModule).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @notice Initiates the registration of a new validator
     * @dev Only callable by the contract owner
     * @param nodeID The node ID of the validator
     * @param blsPublicKey The BLS public key of the validator
     * @param remainingBalanceOwner P-Chain owner for remaining balance
     * @param disableOwner P-Chain owner who can disable the validator
     * @param weight The weight of the validator
     * @return validationID The ID of the validation being registered
     */
    function initiateValidatorRegistration(
        bytes calldata nodeID,
        bytes calldata blsPublicKey,
        PChainOwner calldata remainingBalanceOwner,
        PChainOwner calldata disableOwner,
        uint64 weight
    ) external onlyOwner returns (bytes32 validationID) {
        return balancerValidatorManager.initiateValidatorRegistration(
            nodeID, blsPublicKey, remainingBalanceOwner, disableOwner, weight
        );
    }

    /**
     * @notice Initiates the removal of a validator
     * @dev Only callable by the contract owner
     * @param validationID The ID of the validator to remove
     */
    function initiateValidatorRemoval(
        bytes32 validationID
    ) external onlyOwner {
        balancerValidatorManager.initiateValidatorRemoval(validationID);
    }

    /**
     * @notice Initiates a weight update for a validator
     * @dev Only callable by the contract owner
     * @param validationID The ID of the validator to update
     * @param newWeight The new weight to set for the validator
     * @return nonce The nonce of the weight update operation
     * @return messageID The ID of the initiated message
     */
    function initiateValidatorWeightUpdate(
        bytes32 validationID,
        uint64 newWeight
    ) external onlyOwner returns (uint64 nonce, bytes32 messageID) {
        return balancerValidatorManager.initiateValidatorWeightUpdate(validationID, newWeight);
    }

    /// @inheritdoc ISecurityModule
    function completeValidatorRegistration(
        uint32 messageIndex
    ) external returns (bytes32) {
        return balancerValidatorManager.completeValidatorRegistration(messageIndex);
    }

    /// @inheritdoc ISecurityModule
    function completeValidatorRemoval(
        uint32 messageIndex
    ) external returns (bytes32) {
        return balancerValidatorManager.completeValidatorRemoval(messageIndex);
    }

    /// @inheritdoc ISecurityModule
    function completeValidatorWeightUpdate(
        uint32 messageIndex
    ) external returns (bytes32 validationID, uint64 nonce) {
        return balancerValidatorManager.completeValidatorWeightUpdate(messageIndex);
    }
}

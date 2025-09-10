// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {IBalancerValidatorManager} from
    "../../../interfaces/ValidatorManager/IBalancerValidatorManager.sol";
import {ISecurityModule} from "../../../interfaces/ValidatorManager/ISecurityModule.sol";
import {
    ConversionData,
    PChainOwner
} from "@avalabs/icm-contracts/validator-manager/interfaces/IACP99Manager.sol";
import {Ownable} from "@openzeppelin/contracts@5.0.2/access/Ownable.sol";
import {ERC165} from "@openzeppelin/contracts@5.0.2/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts@5.0.2/utils/introspection/IERC165.sol";

/**
 * @dev PoA-style security module for the Balancer Validator Manager.
 * Owner-gated for initiates; completes/resends are permissionless for liveness.
 *
 * @custom:security-contact security@suzaku.network
 */
contract PoASecurityModule is Ownable, ERC165, ISecurityModule {
    error ZeroAddress();

    IBalancerValidatorManager public immutable balancerValidatorManager;

    constructor(
        address balancerValidatorManagerAddress,
        address initialOwner
    ) Ownable(initialOwner) {
        if (balancerValidatorManagerAddress == address(0)) {
            revert ZeroAddress();
        }

        balancerValidatorManager = IBalancerValidatorManager(balancerValidatorManagerAddress);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override (ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(ISecurityModule).interfaceId || super.supportsInterface(interfaceId);
    }

    // --- Initial validator set
    function initializeValidatorSet(
        ConversionData calldata conversionData,
        uint32 messageIndex
    ) external {
        balancerValidatorManager.initializeValidatorSet(conversionData, messageIndex);
    }

    // --- Registration ---
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

    function completeValidatorRegistration(
        uint32 messageIndex
    ) external returns (bytes32) {
        return balancerValidatorManager.completeValidatorRegistration(messageIndex);
    }

    // --- Removal ---
    function initiateValidatorRemoval(
        bytes32 validationID
    ) external onlyOwner {
        balancerValidatorManager.initiateValidatorRemoval(validationID);
    }

    function completeValidatorRemoval(
        uint32 messageIndex
    ) external returns (bytes32) {
        return balancerValidatorManager.completeValidatorRemoval(messageIndex);
    }

    // --- Weight update ---
    function initiateValidatorWeightUpdate(
        bytes32 validationID,
        uint64 newWeight
    ) external onlyOwner returns (uint64 nonce, bytes32 messageID) {
        return balancerValidatorManager.initiateValidatorWeightUpdate(validationID, newWeight);
    }

    function completeValidatorWeightUpdate(
        uint32 messageIndex
    ) external returns (bytes32 validationID, uint64 nonce) {
        return balancerValidatorManager.completeValidatorWeightUpdate(messageIndex);
    }
}

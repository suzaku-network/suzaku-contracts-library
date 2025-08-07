// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {IBalancerValidatorManager} from
    "../../../interfaces/ValidatorManager/IBalancerValidatorManager.sol";
import {PChainOwner} from "@avalabs/icm-contracts/validator-manager/interfaces/IACP99Manager.sol";
import {Ownable} from "@openzeppelin/contracts@5.0.2/access/Ownable.sol";

/**
 * @dev Proof-of-Authority security module for BalancerValidatorManager.
 *
 * @custom:security-contact security@suzaku.network
 */
contract PoASecurityModule is Ownable {
    error ZeroAddress();

    IBalancerValidatorManager public immutable balancerValidatorManager;

    constructor(address balancerValidatorManager_, address initialOwner) Ownable(initialOwner) {
        if (balancerValidatorManager_ == address(0)) {
            revert ZeroAddress();
        }

        balancerValidatorManager = IBalancerValidatorManager(balancerValidatorManager_);
    }

    function initiateValidatorRegistration(
        bytes memory nodeID,
        bytes memory blsPublicKey,
        PChainOwner memory remainingBalanceOwner,
        PChainOwner memory disableOwner,
        uint64 weight
    ) external onlyOwner returns (bytes32 validationID) {
        return balancerValidatorManager.initiateValidatorRegistrationWithSecurityModule(
            nodeID, blsPublicKey, remainingBalanceOwner, disableOwner, weight
        );
    }

    function initiateValidatorRemoval(
        bytes32 validationID
    ) external onlyOwner {
        // IPoAManager expects void return, but BalancerValidatorManager returns Validator memory
        // We ignore the return value as the PoA module doesn't need it
        balancerValidatorManager.initiateValidatorRemovalWithSecurityModule(validationID);
    }

    function initiateValidatorWeightUpdate(
        bytes32 validationID,
        uint64 newWeight
    ) external onlyOwner returns (uint64 nonce, bytes32 messageID) {
        return balancerValidatorManager.initiateValidatorWeightUpdateWithSecurityModule(
            validationID, newWeight
        );
    }

    function completeValidatorRegistration(
        uint32 messageIndex
    ) external returns (bytes32 validationID) {
        return
            balancerValidatorManager.completeValidatorRegistrationWithSecurityModule(messageIndex);
    }

    function completeValidatorRemoval(
        uint32 messageIndex
    ) external returns (bytes32 validationID) {
        return balancerValidatorManager.completeValidatorRemovalWithSecurityModule(messageIndex);
    }

    function completeValidatorWeightUpdate(bytes32 validationID, uint32 messageIndex) external {
        balancerValidatorManager.completeValidatorWeightUpdateWithSecurityModule(
            validationID, messageIndex
        );
    }

    function resendRegisterValidatorMessage(
        bytes32 validationID
    ) external {
        balancerValidatorManager.resendRegisterValidatorMessageWithSecurityModule(validationID);
    }

    function resendValidatorRemovalMessage(
        bytes32 validationID
    ) external {
        balancerValidatorManager.resendValidatorRemovalMessageWithSecurityModule(validationID);
    }

    function resendValidatorWeightUpdate(
        bytes32 validationID
    ) external {
        balancerValidatorManager.resendValidatorWeightUpdate(validationID);
    }
}

// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {IACP99Manager} from "../../../interfaces/ACP99/IACP99Manager.sol";
import {
    IACP99SecurityModule,
    ValidatorRegistrationInfo,
    ValidatorWeightChangeInfo
} from "../../../interfaces/ACP99/IACP99SecurityModule.sol";
import {PChainOwner} from
    "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManager.sol";
import {Ownable} from "@openzeppelin/contracts@5.0.2/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts@5.0.2/access/Ownable2Step.sol";

/**
 * @title ACP99PoAModule
 * @author ADDPHO
 * @notice The ACP99PoAModule is a security module for the ACP99Manager contract.
 * It implements the Proof of Authority (PoA) mechanism for managing the validator set of a Subnet.
 * @custom:security-contact security@suzaku.network
 */
contract ACP99PoAModule is Ownable2Step, IACP99SecurityModule {
    /// @notice The ACP99Manager contract that relies on this security module
    IACP99Manager public immutable manager;

    constructor(
        address _manager
    ) Ownable(msg.sender) {
        if (_manager == address(0)) {
            revert ACP99SecurityModule__ZeroAddressManager();
        }

        manager = IACP99Manager(_manager);
    }

    modifier onlyManager() {
        if (msg.sender != address(manager)) {
            revert ACP99SecurityModule__OnlyManager(msg.sender, address(manager));
        }
        _;
    }

    /**
     * @notice Add a new validator to the Subnet
     * @param nodeID The NodeID of the validator node
     * @param weight The initial weight assigned to the validator
     * @param registrationExpiry The expiration time for the registration
     * @param blsPublicKey The validator's BLS public key
     * @return The ValidationID of the new validation
     */
    function addValidator(
        bytes memory nodeID,
        bytes memory blsPublicKey,
        uint64 registrationExpiry,
        PChainOwner memory remainingBalanceOwner,
        PChainOwner memory disableOwner,
        uint64 weight
    ) external onlyOwner returns (bytes32) {
        return manager.initiateValidatorRegistration(
            nodeID, blsPublicKey, registrationExpiry, remainingBalanceOwner, disableOwner, weight
        );
    }

    /**
     * @notice Update the weight of an existing validator
     * @param nodeID The NodeID of the validator node
     * @param newWeight The new weight to assign to the validator
     */
    function updateValidatorWeight(bytes memory nodeID, uint64 newWeight) external onlyOwner {
        manager.initiateValidatorWeightUpdate(nodeID, newWeight, false, 0);
    }

    /**
     * @notice Remove a validator from the Subnet
     * @param nodeID The NodeID of the validator to remove
     * @param includesUptimeProof Whether an uptime proof is included
     * @param messageIndex The index of the uptime proof message (if included)
     */
    function removeValidator(
        bytes memory nodeID,
        bool includesUptimeProof,
        uint32 messageIndex
    ) external onlyOwner {
        // Passing 0 as the new weight to indicate removal
        manager.initiateValidatorWeightUpdate(nodeID, 0, includesUptimeProof, messageIndex);
    }

    /// @inheritdoc IACP99SecurityModule
    function handleValidatorRegistration(
        ValidatorRegistrationInfo memory /*validatorInfo*/
    ) external onlyManager {
        // This function doesn't perform any special actions for PoA
    }

    /// @inheritdoc IACP99SecurityModule
    function handleValidatorWeightChange(
        ValidatorWeightChangeInfo memory /*weightChangeInfo*/
    ) external onlyManager {
        // This function doesn't perform any special actions for PoA
    }

    /// @inheritdoc IACP99SecurityModule
    function getManagerAddress() external view returns (address) {
        return address(manager);
    }
}

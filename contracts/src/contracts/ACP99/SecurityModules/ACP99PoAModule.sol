// (c) 2024, ADDPHO All rights reserved.
// See the file LICENSE_BUSL for licensing terms.

// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import {IACP99Manager} from "../../../interfaces/ACP99/IACP99Manager.sol";
import {IACP99SecurityModule} from "../../../interfaces/ACP99/IACP99SecurityModule.sol";
import {Ownable2Step} from "@openzeppelin/contracts@4.9.6/access/Ownable2Step.sol";

contract ACP99PoAModule is Ownable2Step, IACP99SecurityModule {
    IACP99Manager public manager;

    constructor(address _manager) Ownable2Step() {
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
        bytes32 nodeID,
        uint64 weight,
        uint64 registrationExpiry,
        bytes memory blsPublicKey
    ) external onlyOwner returns (bytes32) {
        return
            manager.initiateValidatorRegistration(nodeID, weight, registrationExpiry, blsPublicKey);
    }

    /**
     * @notice Update the weight of an existing validator
     * @param nodeID The NodeID of the validator node
     * @param newWeight The new weight to assign to the validator
     */
    function updateValidatorWeight(bytes32 nodeID, uint64 newWeight) external onlyOwner {
        manager.initiateValidatorWeightUpdate(nodeID, newWeight, false, 0);
    }

    /**
     * @notice Remove a validator from the Subnet
     * @param nodeID The NodeID of the validator to remove
     * @param includesUptimeProof Whether an uptime proof is included
     * @param messageIndex The index of the uptime proof message (if included)
     */
    function removeValidator(
        bytes32 nodeID,
        bool includesUptimeProof,
        uint32 messageIndex
    ) external onlyOwner {
        // Passing 0 as the new weight to indicate removal
        manager.initiateValidatorWeightUpdate(nodeID, 0, includesUptimeProof, messageIndex);
    }

    /// @inheritdoc IACP99SecurityModule
    function handleValidatorRegistration(ValidatiorRegistrationInfo memory validatorInfo)
        external
        onlyManager
    {
        // This function doesn't perform any special actions for PoA
    }

    /// @inheritdoc IACP99SecurityModule
    function handleValidatorWeightChange(ValidatorWeightChangeInfo memory weightChangeInfo)
        external
        onlyManager
    {
        // This function doesn't perform any special actions for PoA
    }

    /// @inheritdoc IACP99SecurityModule
    function getManagerAddress() external view returns (address) {
        return address(manager);
    }
}

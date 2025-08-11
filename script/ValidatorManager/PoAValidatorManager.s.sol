// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {PoAUpgradeConfig} from "./PoAUpgradeConfigTypes.s.sol";

import {ICMInitializable} from "@avalabs/icm-contracts/utilities/ICMInitializable.sol";
import {PoAManager} from "@avalabs/icm-contracts/validator-manager/PoAManager.sol";
import {
    ValidatorManager as VM2,
    ValidatorManagerSettings as VM2Settings
} from "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";
import {IValidatorManagerExternalOwnable} from
    "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManagerExternalOwnable.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Script} from "forge-std/Script.sol";

/**
 * @dev Deploy a PoA-style Validator Manager using v2.1 architecture
 * This deploys ValidatorManager + PoAManager (not the old PoAValidatorManager)
 */
contract ExecutePoAValidatorManager is Script {
    function executeDeployPoA(
        PoAUpgradeConfig memory poaConfig,
        uint256 proxyAdminOwnerKey
    ) external returns (address) {
        vm.startBroadcast(proxyAdminOwnerKey);

        // 1. Deploy ValidatorManager (v2.1 style)
        VM2Settings memory settings = VM2Settings({
            admin: poaConfig.validatorManagerOwnerAddress,
            subnetID: poaConfig.subnetID,
            churnPeriodSeconds: poaConfig.churnPeriodSeconds,
            maximumChurnPercentage: poaConfig.maximumChurnPercentage
        });

        VM2 vmImpl = new VM2(ICMInitializable.Allowed);
        address vmProxy = UnsafeUpgrades.deployTransparentProxy(
            address(vmImpl),
            poaConfig.proxyAdminOwnerAddress,
            abi.encodeCall(VM2.initialize, (settings))
        );

        // 2. Deploy PoAManager as the owner
        PoAManager poaManager = new PoAManager(
            poaConfig.validatorManagerOwnerAddress, IValidatorManagerExternalOwnable(vmProxy)
        );

        // 3. Transfer VM ownership to PoAManager
        VM2(vmProxy).transferOwnership(address(poaManager));

        vm.stopBroadcast();

        // Return the ValidatorManager proxy address (not PoAManager)
        // This maintains compatibility with existing tests that expect the VM address
        return vmProxy;
    }
}

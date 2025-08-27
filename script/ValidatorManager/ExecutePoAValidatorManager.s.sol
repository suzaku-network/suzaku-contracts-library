// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {BalancerMigrationConfig} from "./BalancerConfigTypes.s.sol";

import {ICMInitializable} from "@avalabs/icm-contracts/utilities/ICMInitializable.sol";
import {PoAManager} from "@avalabs/icm-contracts/validator-manager/PoAManager.sol";
import {
    ValidatorManager,
    ValidatorManagerSettings
} from "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";
import {IValidatorManagerExternalOwnable} from
    "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManagerExternalOwnable.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Script} from "forge-std/Script.sol";

/**
 * @dev Deploy a PoA Validator Manager
 */
contract ExecutePoAValidatorManager is Script {
    function executeDeployPoA(
        BalancerMigrationConfig memory config,
        uint256 proxyAdminOwnerKey,
        uint256 validatorManagerOwnerKey
    ) external returns (address validatorManagerProxy, address poaManagerAddress) {
        vm.startBroadcast(proxyAdminOwnerKey);

        // Deploy ValidatorManager implementation and proxy
        ValidatorManager validatorManagerImpl = new ValidatorManager(ICMInitializable.Allowed);
        validatorManagerProxy = UnsafeUpgrades.deployTransparentProxy(
            address(validatorManagerImpl),
            config.proxyAdminOwnerAddress,
            "" // Initialize later from non-admin
        );

        // Deploy PoAManager
        PoAManager poaManager = new PoAManager(
            config.validatorManagerOwnerAddress,
            IValidatorManagerExternalOwnable(validatorManagerProxy)
        );
        poaManagerAddress = address(poaManager);

        vm.stopBroadcast();

        // Initialize ValidatorManager with PoAManager as admin
        vm.startBroadcast(validatorManagerOwnerKey);

        ValidatorManagerSettings memory settings = ValidatorManagerSettings({
            admin: poaManagerAddress,
            subnetID: config.subnetID,
            churnPeriodSeconds: config.churnPeriodSeconds,
            maximumChurnPercentage: config.maximumChurnPercentage
        });

        ValidatorManager(validatorManagerProxy).initialize(settings);

        vm.stopBroadcast();

        return (validatorManagerProxy, poaManagerAddress);
    }
}

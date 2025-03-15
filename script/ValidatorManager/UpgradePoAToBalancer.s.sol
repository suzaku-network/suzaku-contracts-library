// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {
    BalancerValidatorManager,
    BalancerValidatorManagerSettings
} from "../../src/contracts/ValidatorManager/BalancerValidatorManager.sol";
import {PoASecurityModule} from
    "../../src/contracts/ValidatorManager/SecurityModule/PoASecurityModule.sol";
import {PoAUpgradeConfig} from "./PoAUpgradeConfigTypes.s.sol";
import {ValidatorManagerSettings} from
    "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManager.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Script} from "forge-std/Script.sol";

contract UpgradePoAToBalancerValidatorManager is Script {
    function executeUpgradePoAToBalancer(
        PoAUpgradeConfig memory balancerConfig
    ) external returns (address, address) {
        address validatorManagerOwnerAddress = vm.addr(balancerConfig.validatorManagerOwnerKey);

        // Deploy new implementation
        BalancerValidatorManager newImplementation = new BalancerValidatorManager();

        // Upgrade proxy implementation
        UnsafeUpgrades.upgradeProxy(balancerConfig.proxyAddress, address(newImplementation), "");

        // Deploy PoASecurityModule
        PoASecurityModule securityModule =
            new PoASecurityModule(balancerConfig.proxyAddress, validatorManagerOwnerAddress);

        // Initialize new implementation
        BalancerValidatorManager balancerValidatorManager =
            BalancerValidatorManager(balancerConfig.proxyAddress);
        BalancerValidatorManagerSettings memory settings = BalancerValidatorManagerSettings({
            baseSettings: ValidatorManagerSettings({
                l1ID: balancerConfig.l1ID,
                churnPeriodSeconds: balancerConfig.churnPeriodSeconds,
                maximumChurnPercentage: balancerConfig.maximumChurnPercentage
            }),
            initialOwner: validatorManagerOwnerAddress,
            initialSecurityModule: address(securityModule),
            initialSecurityModuleMaxWeight: balancerConfig.initialSecurityModuleMaxWeight,
            migratedValidators: balancerConfig.migratedValidators
        });

        balancerValidatorManager.initialize(settings);

        return (balancerConfig.proxyAddress, address(securityModule));
    }
}

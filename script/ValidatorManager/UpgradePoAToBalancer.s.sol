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
    "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Script} from "forge-std/Script.sol";

contract UpgradePoAToBalancer is Script {
    function executeUpgradePoAToBalancer(
        PoAUpgradeConfig memory balancerConfig,
        uint256 proxyAdminOwnerKey
    ) external returns (address, address) {
        vm.startBroadcast(proxyAdminOwnerKey);
        // Deploy new implementation
        BalancerValidatorManager newImplementation = new BalancerValidatorManager();

        // Upgrade proxy implementation
        UnsafeUpgrades.upgradeProxy(balancerConfig.proxyAddress, address(newImplementation), "");

        // Deploy PoASecurityModule
        PoASecurityModule securityModule = new PoASecurityModule(
            balancerConfig.proxyAddress, balancerConfig.validatorManagerOwnerAddress
        );

        // Initialize new implementation
        BalancerValidatorManager balancerValidatorManager =
            BalancerValidatorManager(balancerConfig.proxyAddress);
        BalancerValidatorManagerSettings memory settings = BalancerValidatorManagerSettings({
            baseSettings: ValidatorManagerSettings({
                admin: balancerConfig.validatorManagerOwnerAddress, // Set owner directly
                subnetID: balancerConfig.l1ID,
                churnPeriodSeconds: balancerConfig.churnPeriodSeconds,
                maximumChurnPercentage: balancerConfig.maximumChurnPercentage
            }),
            initialOwner: balancerConfig.validatorManagerOwnerAddress,
            initialSecurityModule: address(securityModule),
            initialSecurityModuleMaxWeight: balancerConfig.initialSecurityModuleMaxWeight,
            migratedValidators: balancerConfig.migratedValidators
        });

        balancerValidatorManager.initialize(settings);
        vm.stopBroadcast();

        return (balancerConfig.proxyAddress, address(securityModule));
    }
}

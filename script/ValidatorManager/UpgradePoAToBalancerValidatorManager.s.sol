// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {
    BalancerValidatorManager,
    BalancerValidatorManagerSettings
} from "../../src/contracts/ValidatorManager/BalancerValidatorManager.sol";
import {PoASecurityModule} from
    "../../src/contracts/ValidatorManager/SecurityModule/PoASecurityModule.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {ValidatorManagerSettings} from
    "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManager.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Script} from "forge-std/Script.sol";

contract UpgradePoAToBalancerValidatorManager is Script {
    function run(
        address proxyAddress,
        uint64 initialSecurityModuleMaxWeight,
        bytes32[] calldata migratedValidations
    ) external returns (address, address) {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint256 proxyAdminOwnerKey,
            uint256 validatorManagerOwnerKey,
            bytes32 l1ID,
            uint64 churnPeriodSeconds,
            uint8 maximumChurnPercentage
        ) = helperConfig.activeNetworkConfig();
        address validatorManagerOwnerAddress = vm.addr(validatorManagerOwnerKey);

        vm.startBroadcast(proxyAdminOwnerKey);

        // Deploy new implementation
        BalancerValidatorManager newImplementation = new BalancerValidatorManager();

        // Upgrade proxy implementation
        UnsafeUpgrades.upgradeProxy(proxyAddress, address(newImplementation), "");

        // Deploy PoASecurityModule
        PoASecurityModule securityModule =
            new PoASecurityModule(proxyAddress, validatorManagerOwnerAddress);

        // Initialize new implementation
        BalancerValidatorManager balancerValidatorManager = BalancerValidatorManager(proxyAddress);
        BalancerValidatorManagerSettings memory settings = BalancerValidatorManagerSettings({
            baseSettings: ValidatorManagerSettings({
                l1ID: l1ID,
                churnPeriodSeconds: churnPeriodSeconds,
                maximumChurnPercentage: maximumChurnPercentage
            }),
            initialOwner: validatorManagerOwnerAddress,
            initialSecurityModule: address(securityModule),
            initialSecurityModuleMaxWeight: initialSecurityModuleMaxWeight,
            migratedValidations: migratedValidations
        });

        balancerValidatorManager.initialize(settings);

        vm.stopBroadcast();

        return (proxyAddress, address(securityModule));
    }
}

// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {ValidatorManagerSettings} from
    "../../lib/teleporter/contracts/validator-manager/interfaces/IValidatorManager.sol";
import {
    BalancerValidatorManager,
    BalancerValidatorManagerSettings
} from "../../src/contracts/ValidatorManager/BalancerValidatorManager.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Script} from "forge-std/Script.sol";

contract DeployBalancerValidatorManager is Script {
    function run(
        address initialSecurityModule,
        uint64 initialSecurityModuleWeight,
        bytes[] calldata migratedValidators
    ) external returns (address) {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint256 proxyAdminOwnerKey,
            uint256 validatorManagerOwnerKey,
            bytes32 subnetID,
            uint64 churnPeriodSeconds,
            uint8 maximumChurnPercentage
        ) = helperConfig.activeNetworkConfig();
        address proxyAdminOwnerAddress = vm.addr(proxyAdminOwnerKey);
        address validatorManagerOwnerAddress = vm.addr(validatorManagerOwnerKey);

        vm.startBroadcast(proxyAdminOwnerKey);

        ValidatorManagerSettings memory settings = ValidatorManagerSettings({
            subnetID: subnetID,
            churnPeriodSeconds: churnPeriodSeconds,
            maximumChurnPercentage: maximumChurnPercentage
        });
        BalancerValidatorManagerSettings memory balancerSettings = BalancerValidatorManagerSettings({
            baseSettings: settings,
            initialOwner: validatorManagerOwnerAddress,
            initialSecurityModule: initialSecurityModule,
            initialSecurityModuleMaxWeight: initialSecurityModuleWeight,
            migratedValidators: migratedValidators
        });

        address proxy = Upgrades.deployTransparentProxy(
            "BalancerValidatorManager.sol:BalancerValidatorManager",
            proxyAdminOwnerAddress,
            abi.encodeCall(BalancerValidatorManager.initialize, balancerSettings)
        );

        vm.stopBroadcast();

        return proxy;
    }
}

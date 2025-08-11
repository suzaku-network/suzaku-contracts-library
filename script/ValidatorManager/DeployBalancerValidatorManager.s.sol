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
    "../../src/interfaces/ValidatorManager/IBalancerValidatorManager.sol";
import {ICMInitializable} from "@avalabs/icm-contracts/utilities/ICMInitializable.sol";
import {
    ValidatorManager as VM2,
    ValidatorManagerSettings as VM2Settings
} from "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Script} from "forge-std/Script.sol";

contract DeployBalancerValidatorManager is Script {
    function run(
        address initialSecurityModule,
        uint64 initialSecurityModuleWeight,
        bytes[] calldata migratedValidators
    ) external returns (address balancer, address securityModule, address vmAddress) {
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

        bool deployPoASecurityModule = initialSecurityModule == address(0);

        vm.startBroadcast(proxyAdminOwnerKey);

        // 1) Deploy v2 VM (proxy)
        VM2Settings memory vmSettings = VM2Settings({
            admin: validatorManagerOwnerAddress,
            subnetID: subnetID,
            churnPeriodSeconds: churnPeriodSeconds,
            maximumChurnPercentage: maximumChurnPercentage
        });
        VM2 vmImpl = new VM2(ICMInitializable.Allowed);
        vmAddress = UnsafeUpgrades.deployTransparentProxy(
            address(vmImpl), proxyAdminOwnerAddress, abi.encodeCall(VM2.initialize, (vmSettings))
        );

        // 2) Deploy Balancer (proxy)
        BalancerValidatorManagerSettings memory balancerSettings = BalancerValidatorManagerSettings({
            baseSettings: ValidatorManagerSettings({
                subnetID: subnetID,
                churnPeriodSeconds: churnPeriodSeconds,
                maximumChurnPercentage: maximumChurnPercentage
            }),
            initialOwner: validatorManagerOwnerAddress,
            initialSecurityModule: initialSecurityModule,
            initialSecurityModuleMaxWeight: initialSecurityModuleWeight,
            migratedValidators: migratedValidators
        });
        BalancerValidatorManager balancerImpl = new BalancerValidatorManager();
        balancer = UnsafeUpgrades.deployTransparentProxy(
            address(balancerImpl),
            proxyAdminOwnerAddress,
            abi.encodeCall(BalancerValidatorManager.initialize, (balancerSettings, vmAddress))
        );

        // 3) Transfer VM ownership to Balancer so it can call VM-onlyOwner functions
        vm.stopBroadcast();
        vm.startBroadcast(validatorManagerOwnerKey);
        VM2(vmAddress).transferOwnership(balancer);
        vm.stopBroadcast();

        // 4) Optionally deploy PoA security module and register it
        if (deployPoASecurityModule) {
            vm.startBroadcast(proxyAdminOwnerKey);
            securityModule = address(new PoASecurityModule(balancer, validatorManagerOwnerAddress));
            vm.stopBroadcast();

            vm.startBroadcast(validatorManagerOwnerKey);
            BalancerValidatorManager(balancer).setUpSecurityModule(
                securityModule, initialSecurityModuleWeight
            );
            vm.stopBroadcast();
        } else {
            securityModule = initialSecurityModule;
        }

        return (balancer, securityModule, vmAddress);
    }
}

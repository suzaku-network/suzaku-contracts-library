// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {
    BalancerValidatorManager,
    BalancerValidatorManagerSettings
} from "../../src/contracts/ValidatorManager/BalancerValidatorManager.sol";
import {PoASecurityModule} from
    "../../src/contracts/ValidatorManager/SecurityModule/PoASecurityModule.sol";

import {ValidatorManagerSettings} from
    "../../src/interfaces/ValidatorManager/IBalancerValidatorManager.sol";
import {PoAUpgradeConfig} from "./PoAUpgradeConfigTypes.s.sol";

import {ICMInitializable} from "@avalabs/icm-contracts/utilities/ICMInitializable.sol";
import {
    ValidatorManager as VM2,
    ValidatorManagerSettings as VM2Settings
} from "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Script} from "forge-std/Script.sol";

contract UpgradePoAToBalancer is Script {
    function executeUpgradePoAToBalancer(
        PoAUpgradeConfig memory balancerConfig,
        uint256 proxyAdminOwnerKey
    ) external returns (address proxyAddress, address securityModuleAddress, address vmAddress) {
        vm.startBroadcast(proxyAdminOwnerKey);
        // 1) Deploy VM2
        VM2Settings memory vmSettings = VM2Settings({
            admin: balancerConfig.validatorManagerOwnerAddress,
            subnetID: balancerConfig.subnetID,
            churnPeriodSeconds: balancerConfig.churnPeriodSeconds,
            maximumChurnPercentage: balancerConfig.maximumChurnPercentage
        });
        VM2 vmImpl = new VM2(ICMInitializable.Allowed);
        vmAddress = UnsafeUpgrades.deployTransparentProxy(
            address(vmImpl),
            balancerConfig.proxyAdminOwnerAddress,
            abi.encodeCall(VM2.initialize, (vmSettings))
        );

        // 2) Upgrade PoA proxy -> Balancer wrapper implementation
        BalancerValidatorManager newImplementation = new BalancerValidatorManager();
        UnsafeUpgrades.upgradeProxy(balancerConfig.proxyAddress, address(newImplementation), "");

        // 3) Deploy PoASecurityModule
        PoASecurityModule securityModule = new PoASecurityModule(
            balancerConfig.proxyAddress, balancerConfig.validatorManagerOwnerAddress
        );

        // Prepare init settings
        BalancerValidatorManager balancerValidatorManager =
            BalancerValidatorManager(balancerConfig.proxyAddress);
        BalancerValidatorManagerSettings memory settings = BalancerValidatorManagerSettings({
            baseSettings: ValidatorManagerSettings({
                subnetID: balancerConfig.subnetID,
                churnPeriodSeconds: balancerConfig.churnPeriodSeconds,
                maximumChurnPercentage: balancerConfig.maximumChurnPercentage
            }),
            initialOwner: balancerConfig.validatorManagerOwnerAddress,
            initialSecurityModule: address(securityModule),
            initialSecurityModuleMaxWeight: balancerConfig.initialSecurityModuleMaxWeight,
            migratedValidators: balancerConfig.migratedValidators
        });

        // 4) Initialize Balancer wrapper with VM2 address
        balancerValidatorManager.initialize(settings, vmAddress);

        // 5) Transfer VM2 ownership to the Balancer (upgraded proxy)
        VM2(vmAddress).transferOwnership(balancerConfig.proxyAddress);
        vm.stopBroadcast();

        // The proxy address stays the same (upgraded implementation)
        return (balancerConfig.proxyAddress, address(securityModule), vmAddress);
    }
}

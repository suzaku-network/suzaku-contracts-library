// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {ValidatorManagerSettings} from
    "../../lib/teleporter/contracts/validator-manager/interfaces/IValidatorManager.sol";
import {
    BalancerValidatorManager,
    BalancerValidatorManagerSettings
} from "../../src/contracts/ValidatorManager/BalancerValidatorManager.sol";
import {PoASecurityModule} from
    "../../src/contracts/ValidatorManager/SecurityModule/PoASecurityModule.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Script} from "forge-std/Script.sol";

contract DeployBalancerValidatorManager is Script {
    function run(
        address initialSecurityModule,
        uint64 initialSecurityModuleWeight,
        bytes[] calldata migratedValidators
    ) external returns (address, address) {
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

        // Predict the address where PoASecurityModule will be deployed if deployPoASecurityModule is true
        // This will be the next address after the proxy deployment
        bool deployPoASecurityModule = initialSecurityModule == address(0);
        if (deployPoASecurityModule) {
            initialSecurityModule = vm.computeCreateAddress(
                proxyAdminOwnerAddress, vm.getNonce(proxyAdminOwnerAddress) + 2
            );
        }

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

        address securityModuleDeploymentAddress;
        if (deployPoASecurityModule) {
            securityModuleDeploymentAddress =
                address(new PoASecurityModule(proxy, validatorManagerOwnerAddress));
            if (securityModuleDeploymentAddress != initialSecurityModule) {
                revert("PoASecurityModule deployed at unexpected address");
            }
        }

        vm.stopBroadcast();

        return (proxy, initialSecurityModule);
    }
}

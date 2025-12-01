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
import {BalancerMigrationConfig} from "./BalancerConfigTypes.s.sol";
import {ValidatorManager} from "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";

import {
    Validator,
    ValidatorStatus
} from "@avalabs/icm-contracts/validator-manager/interfaces/IACP99Manager.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Script, console} from "forge-std/Script.sol";

contract MigratePoAToBalancer is Script {
    function _sumMigratedWeight(
        address validatorManager,
        bytes[] memory migratedValidators
    ) internal view returns (uint64 sum) {
        ValidatorManager vm = ValidatorManager(validatorManager);
        for (uint256 i = 0; i < migratedValidators.length; i++) {
            bytes32 vid = vm.getNodeValidationID(migratedValidators[i]);
            require(vid != bytes32(0), "migrated nodeID not registered");
            Validator memory v = vm.getValidator(vid);
            if (
                (v.status == ValidatorStatus.Active || v.status == ValidatorStatus.PendingAdded)
                    && v.weight > 0
            ) {
                sum += v.weight;
            }
        }
    }

    /**
     * @notice Deploy BalancerValidatorManager + PoASecurityModule and initialize
     * @param config Migration configuration
     * @param proxyAdminOwnerKey Private key for proxy admin
     * @param validatorManagerOwnerKey Private key for validator manager owner
     * @dev Ownership transfer must be done manually after verifying configuration
     */
    function executeMigratePoAToBalancer(
        BalancerMigrationConfig memory config,
        uint256 proxyAdminOwnerKey,
        uint256 validatorManagerOwnerKey
    ) external returns (address proxyAddress, address securityModuleAddress, address vmAddress) {
        address validatorManager = config.validatorManagerProxy;

        // 0) Sanity: Balancer cap must cover current total weight
        uint64 totalWeight = ValidatorManager(validatorManager).l1TotalWeight();
        require(
            config.initialSecurityModuleMaxWeight >= totalWeight,
            "initial cap < current total weight"
        );

        // Check list before any deployments
        uint64 listed = _sumMigratedWeight(validatorManager, config.migratedValidators);
        require(listed == totalWeight, "migrated list weight != l1TotalWeight");

        // 1) Deploy Balancer proxy
        vm.startBroadcast(proxyAdminOwnerKey);
        BalancerValidatorManager balancerImplementation = new BalancerValidatorManager();
        proxyAddress = UnsafeUpgrades.deployTransparentProxy(
            address(balancerImplementation),
            config.proxyAdminOwnerAddress,
            ""
        );
        vm.stopBroadcast();

        // 2) Deploy PoA security module
        vm.startBroadcast(proxyAdminOwnerKey);
        PoASecurityModule poaSecurityModule =
            new PoASecurityModule(proxyAddress, config.validatorManagerOwnerAddress);
        securityModuleAddress = address(poaSecurityModule);
        vm.stopBroadcast();

        // 3) Initialize Balancer
        BalancerValidatorManagerSettings memory settings = BalancerValidatorManagerSettings({
            baseSettings: ValidatorManagerSettings({
                admin: address(0), // Will be set by ValidatorManager initialization
                subnetID: config.subnetID,
                churnPeriodSeconds: config.churnPeriodSeconds,
                maximumChurnPercentage: config.maximumChurnPercentage
            }),
            initialOwner: config.validatorManagerOwnerAddress,
            initialSecurityModule: securityModuleAddress,
            initialSecurityModuleMaxWeight: config.initialSecurityModuleMaxWeight,
            migratedValidators: config.migratedValidators
        });

        vm.startBroadcast(validatorManagerOwnerKey);
        BalancerValidatorManager(proxyAddress).initialize(settings, validatorManager);
        vm.stopBroadcast();

        console.log("Balancer:", proxyAddress);
        console.log("PoA module:", securityModuleAddress);
        console.log("ValidatorManager:", validatorManager);
        console.log("Balancer owner:", BalancerValidatorManager(proxyAddress).owner());
        vmAddress = validatorManager;

        return (proxyAddress, securityModuleAddress, vmAddress);
    }
}

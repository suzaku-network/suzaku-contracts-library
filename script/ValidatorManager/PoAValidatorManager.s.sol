// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {PoAUpgradeConfig} from "./PoAUpgradeConfigTypes.s.sol";

import {PoAManager} from "@avalabs/icm-contracts/validator-manager/PoAManager.sol";
import {ValidatorManagerSettings} from
    "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";
import {IValidatorManagerExternalOwnable} from
    "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManagerExternalOwnable.sol";
// import {Options, Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {ICMInitializable} from "@utilities/ICMInitializable.sol";
import {Script} from "forge-std/Script.sol";

/**
 * @dev Deploy a PoA Validator Manager
 */
contract ExecutePoAManager is Script {
    function executeDeployPoA(
        PoAUpgradeConfig memory poaConfig,
        uint256 proxyAdminOwnerKey
    ) external returns (address) {
        vm.startBroadcast(proxyAdminOwnerKey);
        ValidatorManagerSettings memory settings = ValidatorManagerSettings({
            admin: poaConfig.validatorManagerOwnerAddress,
            subnetID: poaConfig.l1ID,
            churnPeriodSeconds: poaConfig.churnPeriodSeconds,
            maximumChurnPercentage: poaConfig.maximumChurnPercentage
        });

        // Keeping this for reference. Cannot use the regular Upgrades because libraries are not supported.
        // See https://github.com/foundry-rs/book/issues/1361

        // Options memory opts;
        // opts.constructorData = abi.encode(ICMInitializable.Allowed);
        // opts.unsafeAllow = "constructor,missing-initializer-call,external-library-linking";
        // address proxy = Upgrades.deployTransparentProxy(
        //     "PoAManager.sol:PoAManager",
        //     proxyAdminOwnerAddress,
        //     abi.encodeCall(PoAManager.initialize, (settings, validatorManagerOwnerAddress)),
        //     opts
        // );

        // Deploy the ValidatorManager first (placeholder for actual deployment)
        // In v2, PoAManager is a separate contract that wraps a ValidatorManager
        // This would need to be updated based on the actual deployment flow
        address validatorManagerAddress = address(0); // TODO: Deploy actual ValidatorManager
        PoAManager validatorSetManager = new PoAManager(
            poaConfig.validatorManagerOwnerAddress,
            IValidatorManagerExternalOwnable(validatorManagerAddress)
        );

        // In v2, PoAManager is not upgradeable and doesn't have initialize
        // The ValidatorManager would be the upgradeable contract
        // This script needs major refactoring for v2 architecture
        address proxy = address(validatorSetManager); // Temporary fix
        vm.stopBroadcast();

        return proxy;
    }
}

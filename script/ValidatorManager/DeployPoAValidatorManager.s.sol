// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {HelperConfig} from "./HelperConfig.s.sol";

import {PoAValidatorManager} from "@avalabs/icm-contracts/validator-manager/PoAValidatorManager.sol";
import {ValidatorManagerSettings} from
    "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManager.sol";
// import {Options, Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {ICMInitializable} from "@utilities/ICMInitializable.sol";
import {Script} from "forge-std/Script.sol";

/**
 * @dev Deploy a PoA Validator Manager
 */
contract DeployPoAValidatorManager is Script {
    function run() external returns (address) {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint256 proxyAdminOwnerKey,
            uint256 validatorManagerOwnerKey,
            bytes32 l1ID,
            uint64 churnPeriodSeconds,
            uint8 maximumChurnPercentage
        ) = helperConfig.activeNetworkConfig();
        address proxyAdminOwnerAddress = vm.addr(proxyAdminOwnerKey);
        address validatorManagerOwnerAddress = vm.addr(validatorManagerOwnerKey);

        vm.startBroadcast(proxyAdminOwnerKey);

        ValidatorManagerSettings memory settings = ValidatorManagerSettings({
            l1ID: l1ID,
            churnPeriodSeconds: churnPeriodSeconds,
            maximumChurnPercentage: maximumChurnPercentage
        });

        // Keeping this for reference. Cannot use the regular Upgrades because libraries are not supported.
        // See https://github.com/foundry-rs/book/issues/1361

        // Options memory opts;
        // opts.constructorData = abi.encode(ICMInitializable.Allowed);
        // opts.unsafeAllow = "constructor,missing-initializer-call,external-library-linking";
        // address proxy = Upgrades.deployTransparentProxy(
        //     "PoAValidatorManager.sol:PoAValidatorManager",
        //     proxyAdminOwnerAddress,
        //     abi.encodeCall(PoAValidatorManager.initialize, (settings, validatorManagerOwnerAddress)),
        //     opts
        // );

        PoAValidatorManager validatorSetManager = new PoAValidatorManager(ICMInitializable.Allowed);

        address proxy = UnsafeUpgrades.deployTransparentProxy(
            address(validatorSetManager),
            proxyAdminOwnerAddress,
            abi.encodeCall(PoAValidatorManager.initialize, (settings, validatorManagerOwnerAddress))
        );

        vm.stopBroadcast();

        return proxy;
    }
}

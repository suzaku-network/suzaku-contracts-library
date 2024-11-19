// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {ValidatorManagerSettings} from "../../lib/teleporter/contracts/validator-manager/interfaces/IValidatorManager.sol";
import {PoAValidatorManager} from "../../lib/teleporter/contracts/validator-manager/PoAValidatorManager.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {ProxyAdmin} from "@openzeppelin/contracts@5.0.2/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts@5.0.2/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ICMInitializable} from "@utilities/ICMInitializable.sol";
import {Script} from "forge-std/Script.sol";

contract DeployPoAValidatorManager is Script {
    function run() external returns (address) {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint256 proxyAdminOwnerKey,
            uint256 validatorManagerOwnerKey,
            bytes32 subnetID,
            uint64 churnPeriodSeconds,
            uint8 maximumChurnPercentage
        ) = helperConfig.activeNetworkConfig();
        address proxyAdminOwnerAddress = vm.addr(proxyAdminOwnerKey);
        address validatorManagerOwnerAddress = vm.addr(
            validatorManagerOwnerKey
        );

        vm.startBroadcast(proxyAdminOwnerKey);
        PoAValidatorManager validatorSetManager = new PoAValidatorManager(
            ICMInitializable.Allowed
        );

        ValidatorManagerSettings memory settings = ValidatorManagerSettings({
            subnetID: subnetID,
            churnPeriodSeconds: churnPeriodSeconds,
            maximumChurnPercentage: maximumChurnPercentage
        });

        ProxyAdmin proxyAdmin = new ProxyAdmin(proxyAdminOwnerAddress);

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(validatorSetManager),
            address(proxyAdmin),
            abi.encodeWithSelector(
                PoAValidatorManager.initialize.selector,
                settings,
                validatorManagerOwnerAddress
            )
        );

        vm.stopBroadcast();

        return address(proxy);
    }
}

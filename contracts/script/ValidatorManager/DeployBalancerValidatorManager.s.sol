// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {ValidatorManagerSettings} from
    "../../lib/teleporter/contracts/validator-manager/interfaces/IValidatorManager.sol";
import {BalancerValidatorManager} from
    "../../src/contracts/ValidatorManager/BalancerValidatorManager.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ICMInitializable} from "@utilities/ICMInitializable.sol";
import {Script} from "forge-std/Script.sol";

contract DeployBalancerValidatorManager is Script {
    function run(
        address initialSecurityModule,
        uint64 initialSecurityModuleWeight
    ) external returns (address) {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint256 deployerKey,
            bytes32 subnetID,
            uint64 churnPeriodSeconds,
            uint8 maximumChurnPercentage
        ) = helperConfig.activeNetworkConfig();
        address deployerAddress = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        BalancerValidatorManager validatorSetManager =
            new BalancerValidatorManager(ICMInitializable.Allowed);

        ValidatorManagerSettings memory settings = ValidatorManagerSettings({
            subnetID: subnetID,
            churnPeriodSeconds: churnPeriodSeconds,
            maximumChurnPercentage: maximumChurnPercentage
        });

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(validatorSetManager),
            abi.encodeWithSelector(
                BalancerValidatorManager.initialize.selector,
                settings,
                deployerAddress,
                initialSecurityModule,
                initialSecurityModuleWeight
            )
        );

        vm.stopBroadcast();

        return address(proxy);
    }
}

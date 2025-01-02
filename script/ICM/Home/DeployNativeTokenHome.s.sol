// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {WarpMessengerMock} from "../../../src/contracts/mocks/WarpMessengerMock.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

import {NativeTokenHome} from "@avalabs/icm-contracts/ictt/TokenHome/NativeTokenHome.sol";
import {Script, console} from "forge-std/Script.sol";

contract DeployNativeTokenHome is Script {
    uint256 private minTeleporterVersion = vm.envUint("MIN_TELEPORTER_VERSION");

    function run() external returns (NativeTokenHome) {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint256 deployerKey,
            address teleporterManager,
            ,
            address wrappedTokenAddress,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            address teleporterRegistryAddress,
            ,
            ,
            ,
            ,
        ) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);
        NativeTokenHome nativeTokenHome = new NativeTokenHome(
            teleporterRegistryAddress, teleporterManager, minTeleporterVersion, wrappedTokenAddress
        );
        vm.stopBroadcast();

        return nativeTokenHome;
    }
}

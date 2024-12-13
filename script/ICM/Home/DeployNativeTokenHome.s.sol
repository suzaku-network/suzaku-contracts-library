// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {WarpMessengerMock} from "../../../src/contracts/mocks/WarpMessengerMock.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

import {NativeTokenHome} from "@avalabs/icm-contracts/ictt/TokenHome/NativeTokenHome.sol";
import {Script, console} from "forge-std/Script.sol";

contract DeployNativeTokenHome is Script {
    uint256 private constant MIN_TELEPORTER_VERSION = 1;

    function run() external returns (NativeTokenHome) {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint256 deployerKey,
            address warpPrecompileAddress,
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
            ,
            WarpMessengerMock mock
        ) = helperConfig.activeNetworkConfig();

        vm.etch(warpPrecompileAddress, address(mock).code);

        vm.startBroadcast(deployerKey);
        NativeTokenHome nativeTokenHome = new NativeTokenHome(
            teleporterRegistryAddress,
            teleporterManager,
            MIN_TELEPORTER_VERSION,
            wrappedTokenAddress
        );
        vm.stopBroadcast();

        return nativeTokenHome;
    }
}

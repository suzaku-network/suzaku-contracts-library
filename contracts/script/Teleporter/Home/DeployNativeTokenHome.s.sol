// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {WarpMessengerMock} from "../../../src/mocks/WarpMessengerMock.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {NativeTokenHome} from "@avalabs/avalanche-ictt/TokenHome/NativeTokenHome.sol";
import {Script, console} from "forge-std/Script.sol";

contract DeployNativeTokenHome is Script {
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
        NativeTokenHome nativeTokenHome =
            new NativeTokenHome(teleporterRegistryAddress, teleporterManager, wrappedTokenAddress);
        vm.stopBroadcast();

        return nativeTokenHome;
    }
}

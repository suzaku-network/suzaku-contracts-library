// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {AvalancheICTTRouterSetFees} from
    "../../../src/contracts/Teleporter/AvalancheICTTRouterSetFees.sol";
import {WarpMessengerMock} from "../../../src/contracts/mocks/WarpMessengerMock.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {Script, console} from "forge-std/Script.sol";

contract DeployAvalancheICTTRouterSetFees is Script {
    function run() external returns (AvalancheICTTRouterSetFees) {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint256 deployerKey,
            address warpPrecompileAddress,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 primaryRelayerFeeBips,
            uint256 secondaryRelayerFeeBips,
            ,
            ,
            ,
            ,
            ,
            ,
            WarpMessengerMock mock
        ) = helperConfig.activeNetworkConfig();
        vm.etch(warpPrecompileAddress, address(mock).code);
        vm.startBroadcast(deployerKey);
        AvalancheICTTRouterSetFees tokenBridgeRouter =
            new AvalancheICTTRouterSetFees(primaryRelayerFeeBips, secondaryRelayerFeeBips);
        vm.stopBroadcast();

        return (tokenBridgeRouter);
    }
}

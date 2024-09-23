// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {AvalancheICTTRouterFreeFees} from
    "../../../src/contracts/Teleporter/AvalancheICTTRouterFreeFees.sol";
import {WarpMessengerMock} from "../../../src/contracts/mocks/WarpMessengerMock.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {Script, console} from "forge-std/Script.sol";

contract DeployAvalancheICTTRouterFreeFees is Script {
    function run() external returns (AvalancheICTTRouterFreeFees) {
        HelperConfig helperConfig = new HelperConfig();
        (uint256 deployerKey, address warpPrecompileAddress,,,,,,,,,,,,,,,,, WarpMessengerMock mock)
        = helperConfig.activeNetworkConfig();
        vm.etch(warpPrecompileAddress, address(mock).code);
        vm.startBroadcast(deployerKey);
        AvalancheICTTRouterFreeFees tokenBridgeRouter = new AvalancheICTTRouterFreeFees();
        vm.stopBroadcast();

        return (tokenBridgeRouter);
    }
}

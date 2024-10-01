// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {AvalancheICTTRouter} from "../../../src/contracts/Teleporter/AvalancheICTTRouter.sol";
import {WarpMessengerMock} from "../../../src/contracts/mocks/WarpMessengerMock.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {Script, console} from "forge-std/Script.sol";

contract DeployAvalancheICTTRouter is Script {
    function run() external returns (AvalancheICTTRouter) {
        HelperConfig helperConfig = new HelperConfig();
        (uint256 deployerKey, address warpPrecompileAddress,,,,,,,,,,,,,,,,, WarpMessengerMock mock)
        = helperConfig.activeNetworkConfig();
        vm.etch(warpPrecompileAddress, address(mock).code);
        vm.startBroadcast(deployerKey);
        AvalancheICTTRouter tokenBridgeRouter = new AvalancheICTTRouter();
        vm.stopBroadcast();

        return (tokenBridgeRouter);
    }
}

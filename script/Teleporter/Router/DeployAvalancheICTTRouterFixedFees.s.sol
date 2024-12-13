// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {AvalancheICTTRouterFixedFees} from
    "../../../src/contracts/Teleporter/AvalancheICTTRouterFixedFees.sol";
import {WarpMessengerMock} from "../../../src/contracts/mocks/WarpMessengerMock.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

import {Script, console} from "forge-std/Script.sol";

contract DeployAvalancheICTTRouterFixedFees is Script {
    function run() external returns (AvalancheICTTRouterFixedFees) {
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
        address owner = vm.addr(deployerKey);
        vm.etch(warpPrecompileAddress, address(mock).code);
        vm.startBroadcast(deployerKey);
        AvalancheICTTRouterFixedFees tokenBridgeRouter =
            new AvalancheICTTRouterFixedFees(primaryRelayerFeeBips, secondaryRelayerFeeBips, owner);
        vm.stopBroadcast();

        return (tokenBridgeRouter);
    }
}

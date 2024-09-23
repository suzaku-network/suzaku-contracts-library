// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {AvalancheICTTRouterEnforcedFees} from
    "../../../src/contracts/Teleporter/AvalancheICTTRouterEnforcedFees.sol";
import {WarpMessengerMock} from "../../../src/contracts/mocks/WarpMessengerMock.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {Script, console} from "forge-std/Script.sol";

contract DeployAvalancheICTTRouterSetFees is Script {
    function run() external returns (AvalancheICTTRouterEnforcedFees) {
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
        AvalancheICTTRouterEnforcedFees tokenBridgeRouter =
            new AvalancheICTTRouterEnforcedFees(primaryRelayerFeeBips, secondaryRelayerFeeBips);
        vm.stopBroadcast();

        return (tokenBridgeRouter);
    }
}

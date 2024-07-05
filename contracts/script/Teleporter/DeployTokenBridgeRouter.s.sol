// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {TokenBridgeRouter} from "../../src/Teleporter/TokenBridgeRouter.sol";
import {WarpMessengerMock} from "../../src/mocks/WarpMessengerMock.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Script, console} from "forge-std/Script.sol";

contract DeployTokenBridgeRouter is Script {
    function run() external returns (TokenBridgeRouter) {
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
        TokenBridgeRouter tokenBridgeRouter =
            new TokenBridgeRouter(primaryRelayerFeeBips, secondaryRelayerFeeBips);
        vm.stopBroadcast();

        return (tokenBridgeRouter);
    }
}

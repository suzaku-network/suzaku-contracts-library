// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {AvalancheICTTRouter} from "../../src/contracts/Teleporter/AvalancheICTTRouter.sol";
import {WarpMessengerMock} from "../../src/mocks/WarpMessengerMock.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Script} from "forge-std/Script.sol";

contract DeployAvalancheICTTRouter is Script {
    function run() external returns (AvalancheICTTRouter) {
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
        AvalancheICTTRouter tokenBridgeRouter =
            new AvalancheICTTRouter(primaryRelayerFeeBips, secondaryRelayerFeeBips);
        vm.stopBroadcast();

        return (tokenBridgeRouter);
    }
}

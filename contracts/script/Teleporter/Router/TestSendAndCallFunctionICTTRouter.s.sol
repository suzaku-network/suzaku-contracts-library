// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {AvalancheICTTRouter} from "../../../src/contracts/Teleporter/AvalancheICTTRouter.sol";

import {WarpMessengerMock} from "../../../src/contracts/mocks/WarpMessengerMock.sol";
import {IAvalancheICTTRouter} from "../../../src/interfaces/Teleporter/IAvalancheICTTRouter.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

import {IERC20} from "@openzeppelin/contracts@4.8.1/interfaces/IERC20.sol";
import {Script, console} from "forge-std/Script.sol";

contract TestSendAndCallFunctionICTTRouter is Script {
    function run(
        bool erc20
    ) external {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            address warpPrecompileAddress,
            ,
            address tokenAddress,
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

        address tokenBridgeRouterAddr = vm.envAddress("TOKEN_BRIDGE_ROUTER_HOME");
        address bridgerAddr = vm.envAddress("BRIDGER_ADDR");
        bytes32 destinationChainID = vm.envBytes32("REMOTE_CHAIN_HEX");
        uint256 amount = 1 ether;
        address recipient = vm.envAddress("USERS_MOCK_CONTRACT");
        bytes memory recipientPayload = abi.encode(123);
        uint256 recipientGasLimit = 100_000;
        uint256 requiredGasLimit = 10_000_000;
        address multiHopFallback = address(0);

        vm.etch(warpPrecompileAddress, address(mock).code);
        vm.startBroadcast(bridgerAddr);
        if (erc20) {
            sendAndCallERC20(
                tokenBridgeRouterAddr,
                tokenAddress,
                destinationChainID,
                amount,
                recipient,
                recipientPayload,
                bridgerAddr,
                recipientGasLimit,
                requiredGasLimit,
                multiHopFallback,
                primaryRelayerFeeBips,
                secondaryRelayerFeeBips
            );
        } else {
            sendAndCallNative(
                tokenBridgeRouterAddr,
                tokenAddress,
                destinationChainID,
                amount,
                recipient,
                recipientPayload,
                bridgerAddr,
                recipientGasLimit,
                requiredGasLimit,
                multiHopFallback,
                primaryRelayerFeeBips,
                secondaryRelayerFeeBips
            );
        }
        vm.stopBroadcast();
    }

    function sendAndCallERC20(
        address tokenBridgeRouterAddr,
        address tokenAddress,
        bytes32 destinationChainID,
        uint256 amount,
        address recipient,
        bytes memory recipientPayload,
        address recipientFallback,
        uint256 recipientGasLimit,
        uint256 requiredGasLimit,
        address multiHopFallback,
        uint256 primaryRelayerFeeBips,
        uint256 secondaryRelayerFeeBips
    ) public {
        IERC20(tokenAddress).approve(tokenBridgeRouterAddr, amount);
        IAvalancheICTTRouter(tokenBridgeRouterAddr).bridgeAndCallERC20(
            tokenAddress,
            destinationChainID,
            amount,
            recipient,
            recipientPayload,
            recipientFallback,
            recipientGasLimit,
            requiredGasLimit,
            multiHopFallback,
            primaryRelayerFeeBips,
            secondaryRelayerFeeBips
        );
    }

    function sendAndCallNative(
        address tokenBridgeRouterAddr,
        address tokenAddress,
        bytes32 destinationChainID,
        uint256 amount,
        address recipient,
        bytes memory recipientPayload,
        address recipientFallback,
        uint256 recipientGasLimit,
        uint256 requiredGasLimit,
        address multiHopFallback,
        uint256 primaryRelayerFeeBips,
        uint256 secondaryRelayerFeeBips
    ) public {
        IAvalancheICTTRouter(tokenBridgeRouterAddr).bridgeAndCallNative{value: amount}(
            destinationChainID,
            recipient,
            tokenAddress,
            recipientPayload,
            recipientFallback,
            recipientGasLimit,
            requiredGasLimit,
            multiHopFallback,
            primaryRelayerFeeBips,
            secondaryRelayerFeeBips
        );
    }
}

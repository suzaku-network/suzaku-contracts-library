// SPDX-License-Identifier: UNLICENSED
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {AvalancheICTTRouter} from "../../../src/contracts/Teleporter/AvalancheICTTRouter.sol";
import {WarpMessengerTestMock} from "../../../src/contracts/mocks/WarpMessengerTestMock.sol";
import {IAvalancheICTTRouter} from "../../../src/interfaces/Teleporter/IAvalancheICTTRouter.sol";
import {HelperConfig4Test} from "../HelperConfig4Test.t.sol";
import {NativeTokenHome} from "@avalabs/avalanche-ictt/TokenHome/NativeTokenHome.sol";
import {WrappedNativeToken} from "@avalabs/avalanche-ictt/WrappedNativeToken.sol";
import {IERC20} from "@openzeppelin/contracts@4.8.1/interfaces/IERC20.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract AvalancheICTTRouterNativeTokenTest is Test {
    address private constant TOKEN_SOURCE = 0x5CF7F96627F3C9903763d128A1cc5D97556A6b99;

    event BridgeNative(
        bytes32 indexed destinationChainID,
        address recipient,
        uint256 amount,
        uint256 primaryRelaryFee,
        uint256 secondaryRelayerFee
    );

    event BridgeAndCallNative(
        bytes32 indexed destinationChainID,
        address recipient,
        uint256 amount,
        uint256 primaryRelaryFee,
        uint256 secondaryRelayerFee
    );

    HelperConfig4Test helperConfig = new HelperConfig4Test(TOKEN_SOURCE, 0);

    uint256 deployerKey;
    address owner;
    address bridger;
    bytes32 messageId;
    address warpPrecompileAddress;
    WarpMessengerTestMock warpMessengerTestMock;

    address token = address(0);
    WrappedNativeToken wrappedNativeToken;

    NativeTokenHome nativeTokenSource;
    address tokenDestination;
    AvalancheICTTRouter tokenBridgeRouter;
    bytes32 sourceChainID;
    bytes32 destinationChainID;

    uint256 primaryRelayerFee;
    uint256 secondaryRelayerFee;
    uint256 amount;

    uint256 requiredGasLimit = 10_000_000;
    uint256 recipientGasLimit = 100_000;
    address multihopFallBackAddress = address(0);

    uint256 constant STARTING_GAS_BALANCE = 10 ether;

    function setUp() external {
        (
            deployerKey,
            owner,
            bridger,
            messageId,
            warpPrecompileAddress,
            warpMessengerTestMock,
            ,
            wrappedNativeToken,
            ,
            ,
            nativeTokenSource,
            tokenDestination,
            tokenBridgeRouter,
            ,
            sourceChainID,
            destinationChainID,
            primaryRelayerFee,
            secondaryRelayerFee,
            amount
        ) = helperConfig.activeNetworkConfigTest();
        vm.deal(bridger, STARTING_GAS_BALANCE);

        vm.etch(warpPrecompileAddress, address(warpMessengerTestMock).code);
    }

    modifier registerTokenBridge() {
        vm.startPrank(owner);
        tokenBridgeRouter.registerSourceTokenBridge(token, address(nativeTokenSource));
        tokenBridgeRouter.registerDestinationTokenBridge(
            token, destinationChainID, tokenDestination, requiredGasLimit, false
        );
        vm.stopPrank();
        _;
    }

    modifier fundRouterFeeToken() {
        vm.startPrank(bridger);
        wrappedNativeToken.deposit{value: primaryRelayerFee}();
        IERC20(address(wrappedNativeToken)).approve(address(tokenBridgeRouter), primaryRelayerFee);
        _;
    }

    function testBalancesWhenNativeTokensSent() public registerTokenBridge fundRouterFeeToken {
        uint256 balanceBridgerStart = bridger.balance;
        uint256 balanceBridgeStart = wrappedNativeToken.balanceOf(address(nativeTokenSource));

        tokenBridgeRouter.bridgeNative{value: amount}(
            destinationChainID,
            bridger,
            address(wrappedNativeToken),
            multihopFallBackAddress,
            primaryRelayerFee,
            secondaryRelayerFee
        );

        uint256 balanceBridgerEnd = bridger.balance;
        uint256 balanceBridgeEnd = wrappedNativeToken.balanceOf(address(nativeTokenSource));
        assert(balanceBridgerStart == balanceBridgerEnd + amount);
        assert(balanceBridgeStart == balanceBridgeEnd - amount);
        vm.stopPrank();
    }

    function testEmitsWhenNativeTokensSent() public registerTokenBridge fundRouterFeeToken {
        vm.expectEmit(true, false, false, false, address(tokenBridgeRouter));
        emit BridgeNative(
            destinationChainID, bridger, amount, primaryRelayerFee, secondaryRelayerFee
        );

        tokenBridgeRouter.bridgeNative{value: amount}(
            destinationChainID,
            bridger,
            address(wrappedNativeToken),
            multihopFallBackAddress,
            primaryRelayerFee,
            secondaryRelayerFee
        );
        vm.stopPrank();
    }

    function testBalancesWhenNativeTokensSentViaBridgeAndCall()
        public
        registerTokenBridge
        fundRouterFeeToken
    {
        uint256 balanceBridgerStart = bridger.balance;
        uint256 balanceBridgeStart = wrappedNativeToken.balanceOf(address(nativeTokenSource));

        bytes memory payload = abi.encode("abcdefghijklmnopqrstuvwxyz");

        tokenBridgeRouter.bridgeAndCallNative{value: amount}(
            destinationChainID,
            tokenDestination,
            address(wrappedNativeToken),
            payload,
            bridger,
            recipientGasLimit,
            multihopFallBackAddress,
            primaryRelayerFee,
            secondaryRelayerFee
        );

        uint256 balanceBridgerEnd = bridger.balance;
        uint256 balanceBridgeEnd = wrappedNativeToken.balanceOf(address(nativeTokenSource));
        assert(balanceBridgerStart == balanceBridgerEnd + amount);
        assert(balanceBridgeStart == balanceBridgeEnd - amount);
        vm.stopPrank();
    }

    function testEmitsWhenNativeTokensSentViaBridgeAndCall()
        public
        registerTokenBridge
        fundRouterFeeToken
    {
        bytes memory payload = abi.encode("abcdefghijklmnopqrstuvwxyz");

        vm.expectEmit(true, false, false, false, address(tokenBridgeRouter));
        emit BridgeAndCallNative(
            destinationChainID, bridger, amount, primaryRelayerFee, secondaryRelayerFee
        );

        tokenBridgeRouter.bridgeAndCallNative{value: amount}(
            destinationChainID,
            tokenDestination,
            address(wrappedNativeToken),
            payload,
            bridger,
            recipientGasLimit,
            multihopFallBackAddress,
            primaryRelayerFee,
            secondaryRelayerFee
        );
        vm.stopPrank();
    }
}

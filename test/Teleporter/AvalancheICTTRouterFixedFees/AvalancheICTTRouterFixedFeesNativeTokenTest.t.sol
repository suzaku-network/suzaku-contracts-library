// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {AvalancheICTTRouterFixedFees} from
    "../../../src/contracts/Teleporter/AvalancheICTTRouterFixedFees.sol";
import {WarpMessengerTestMock} from "../../../src/contracts/mocks/WarpMessengerTestMock.sol";
import {IAvalancheICTTRouter} from "../../../src/interfaces/Teleporter/IAvalancheICTTRouter.sol";
import {HelperConfig4Test} from "../HelperConfig4Test.t.sol";
import {NativeTokenHome} from "@avalabs/avalanche-ictt/TokenHome/NativeTokenHome.sol";
import {WrappedNativeToken} from "@avalabs/avalanche-ictt/WrappedNativeToken.sol";
import {ERC20Mock} from "@openzeppelin/contracts@4.8.1/mocks/ERC20Mock.sol";
import {SafeMath} from "@openzeppelin/contracts@4.8.1/utils/math/SafeMath.sol";
import {TeleporterMessenger} from "@teleporter/TeleporterMessenger.sol";
import {
    ProtocolRegistryEntry, TeleporterRegistry
} from "@teleporter/upgrades/TeleporterRegistry.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract AvalancheICTTRouterFixedFeesNativeTokenTest is Test {
    address private constant WARP_PRECOMPILE = 0x0200000000000000000000000000000000000005;

    bytes32 private constant SRC_CHAIN_HEX =
        0x7a69000000000000000000000000000000000000000000000000000000000000;
    bytes32 private constant DEST_CHAIN_HEX =
        0x1000000000000000000000000000000000000000000000000000000000000000;

    address private constant TOKEN_SRC = 0xDe09E74d4888Bc4e65F589e8c13Bce9F71DdF4c7;
    address private constant TOKEN_DEST = 0x9C5d3EBEA175C8F401feAa23a4a01214DDE525b6;

    uint256 private constant PRIM_RELAYER_FEE_BIPS = 20;
    uint256 private constant SEC_RELAYER_FEE_BIPS = 20;
    uint256 private constant MIN_PRIM_RELAYER_FEE = 1 gwei;
    uint256 private constant MIN_SEC_RELAYER_FEE = 0;

    uint256 private constant REQ_GAS_LIMIT = 10_000_000;
    uint256 private constant REC_GAS_LIMIT = 100_000;

    address private constant MULTIHOP_ADDR = address(0);

    uint256 private constant AMOUNT = 1 ether;
    uint256 private constant STARTING_GAS_BALANCE = 10 ether;

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

    HelperConfig4Test helperConfig = new HelperConfig4Test();

    uint256 deployerKey;
    address owner;
    address bridger;

    address token = address(0);
    WrappedNativeToken wrappedNativeToken;

    NativeTokenHome tokenSrc;
    AvalancheICTTRouterFixedFees tokenBridgeRouter;

    ProtocolRegistryEntry[] protocolRegistryEntry;

    function setUp() external {
        (deployerKey, owner, bridger) = helperConfig.activeNetworkConfigTest();

        WarpMessengerTestMock warpMessengerTestMock = new WarpMessengerTestMock(TOKEN_SRC);
        vm.etch(WARP_PRECOMPILE, address(warpMessengerTestMock).code);

        wrappedNativeToken = new WrappedNativeToken("WNTT");

        vm.startBroadcast(deployerKey);
        TeleporterMessenger teleporterMessenger = new TeleporterMessenger();
        protocolRegistryEntry.push(ProtocolRegistryEntry(1, address(teleporterMessenger)));
        TeleporterRegistry teleporterRegistry = new TeleporterRegistry(protocolRegistryEntry);

        tokenSrc =
            new NativeTokenHome(address(teleporterRegistry), owner, address(wrappedNativeToken));
        tokenBridgeRouter =
            new AvalancheICTTRouterFixedFees(PRIM_RELAYER_FEE_BIPS, SEC_RELAYER_FEE_BIPS);
        vm.stopBroadcast();

        teleporterMessenger.receiveCrossChainMessage(1, address(0));

        vm.deal(bridger, STARTING_GAS_BALANCE);
    }

    modifier registerTokenBridge() {
        vm.startPrank(owner);
        tokenBridgeRouter.registerSourceTokenBridge(token, TOKEN_SRC);
        tokenBridgeRouter.registerDestinationTokenBridge(
            token,
            DEST_CHAIN_HEX,
            TOKEN_DEST,
            REQ_GAS_LIMIT,
            false,
            MIN_PRIM_RELAYER_FEE,
            MIN_SEC_RELAYER_FEE
        );
        vm.stopPrank();
        _;
    }

    function testBalancesWhenNativeTokensSent() public registerTokenBridge {
        vm.startPrank(bridger);
        uint256 balanceBridgerStart = bridger.balance;
        uint256 balanceBridgeStart = wrappedNativeToken.balanceOf(TOKEN_SRC);

        tokenBridgeRouter.bridgeNative{value: AMOUNT}(
            DEST_CHAIN_HEX, bridger, address(wrappedNativeToken), MULTIHOP_ADDR
        );

        uint256 feesPaid = (AMOUNT * PRIM_RELAYER_FEE_BIPS) / 10_000;

        uint256 balanceBridgerEnd = bridger.balance;
        uint256 balanceBridgeEnd = wrappedNativeToken.balanceOf(TOKEN_SRC);

        assert(balanceBridgerStart == balanceBridgerEnd + AMOUNT);
        assert(balanceBridgeStart == balanceBridgeEnd - (AMOUNT - feesPaid));
        vm.stopPrank();
    }

    function testEmitsWhenNativeTokensSent() public registerTokenBridge {
        vm.startPrank(bridger);
        vm.expectEmit(true, false, false, false, address(tokenBridgeRouter));
        emit BridgeNative(
            DEST_CHAIN_HEX, bridger, AMOUNT, (AMOUNT * PRIM_RELAYER_FEE_BIPS) / 10_000, 0
        );

        tokenBridgeRouter.bridgeNative{value: AMOUNT}(
            DEST_CHAIN_HEX, bridger, address(wrappedNativeToken), MULTIHOP_ADDR
        );
        vm.stopPrank();
    }

    function testBalancesWhenNativeTokensSentViaBridgeAndCall() public registerTokenBridge {
        vm.startPrank(bridger);
        uint256 balanceBridgerStart = bridger.balance;
        uint256 balanceBridgeStart = wrappedNativeToken.balanceOf(TOKEN_SRC);

        bytes memory payload = abi.encode("abcdefghijklmnopqrstuvwxyz");

        tokenBridgeRouter.bridgeAndCallNative{value: AMOUNT}(
            DEST_CHAIN_HEX,
            TOKEN_DEST,
            address(wrappedNativeToken),
            payload,
            bridger,
            REC_GAS_LIMIT,
            MULTIHOP_ADDR
        );

        uint256 feesPaid = (AMOUNT * PRIM_RELAYER_FEE_BIPS) / 10_000;

        uint256 balanceBridgerEnd = bridger.balance;
        uint256 balanceBridgeEnd = wrappedNativeToken.balanceOf(TOKEN_SRC);
        assert(balanceBridgerStart == balanceBridgerEnd + AMOUNT);
        assert(balanceBridgeStart == balanceBridgeEnd - (AMOUNT - feesPaid));
        vm.stopPrank();
    }

    function testEmitsWhenNativeTokensSentViaBridgeAndCall() public registerTokenBridge {
        vm.startPrank(bridger);
        bytes memory payload = abi.encode("abcdefghijklmnopqrstuvwxyz");

        vm.expectEmit(true, false, false, false, address(tokenBridgeRouter));
        emit BridgeAndCallNative(
            DEST_CHAIN_HEX, bridger, AMOUNT, (AMOUNT * PRIM_RELAYER_FEE_BIPS) / 10_000, 0
        );

        tokenBridgeRouter.bridgeAndCallNative{value: AMOUNT}(
            DEST_CHAIN_HEX,
            TOKEN_DEST,
            address(wrappedNativeToken),
            payload,
            bridger,
            REC_GAS_LIMIT,
            MULTIHOP_ADDR
        );
        vm.stopPrank();
    }
}

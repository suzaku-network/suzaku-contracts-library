// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {AvalancheICTTRouter} from "../../../src/contracts/ICM/AvalancheICTTRouter.sol";
import {WarpMessengerTestMock} from "../../../src/contracts/mocks/WarpMessengerTestMock.sol";
import {IAvalancheICTTRouter} from "../../../src/interfaces/ICM/IAvalancheICTTRouter.sol";
import {HelperConfig4Test} from "../HelperConfig4Test.t.sol";

import {NativeTokenHome} from "@avalabs/icm-contracts/ictt/TokenHome/NativeTokenHome.sol";
import {WrappedNativeToken} from "@avalabs/icm-contracts/ictt/WrappedNativeToken.sol";
import {TeleporterMessenger} from "@avalabs/icm-contracts/teleporter/TeleporterMessenger.sol";
import {
    ProtocolRegistryEntry,
    TeleporterRegistry
} from "@avalabs/icm-contracts/teleporter/registry/TeleporterRegistry.sol";
import {IERC20} from "@openzeppelin/contracts@5.0.2/interfaces/IERC20.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract AvalancheICTTRouterNativeTokenTest is Test {
    address private constant WARP_PRECOMPILE = 0x0200000000000000000000000000000000000005;
    uint256 private constant MIN_TELEPORTER_VERSION = 1;

    bytes32 private constant SRC_CHAIN_HEX =
        0x7a69000000000000000000000000000000000000000000000000000000000000;
    bytes32 private constant DEST_CHAIN_HEX =
        0x1000000000000000000000000000000000000000000000000000000000000000;

    address private constant TOKEN_SRC = 0xDe09E74d4888Bc4e65F589e8c13Bce9F71DdF4c7;
    address private constant TOKEN_DEST = 0x9C5d3EBEA175C8F401feAa23a4a01214DDE525b6;

    uint256 private constant PRIM_RELAYER_FEE = 0.01 ether;
    uint256 private constant SEC_RELAYER_FEE = 0.01 ether;

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
    AvalancheICTTRouter tokenBridgeRouter;

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

        tokenSrc = new NativeTokenHome(
            address(teleporterRegistry), owner, MIN_TELEPORTER_VERSION, address(wrappedNativeToken)
        );
        tokenBridgeRouter = new AvalancheICTTRouter(owner);
        vm.stopBroadcast();

        teleporterMessenger.receiveCrossChainMessage(1, address(0));

        vm.deal(bridger, STARTING_GAS_BALANCE);
    }

    modifier registerTokenBridge() {
        vm.startPrank(owner);
        tokenBridgeRouter.registerSourceTokenBridge(token, address(tokenSrc));
        tokenBridgeRouter.registerDestinationTokenBridge(
            token, DEST_CHAIN_HEX, TOKEN_DEST, REQ_GAS_LIMIT, false
        );
        vm.stopPrank();
        _;
    }

    modifier fundRouterFeeToken() {
        vm.startPrank(bridger);
        wrappedNativeToken.deposit{value: PRIM_RELAYER_FEE}();
        IERC20(address(wrappedNativeToken)).approve(address(tokenBridgeRouter), PRIM_RELAYER_FEE);
        _;
    }

    function testBalancesWhenNativeTokensSent() public registerTokenBridge fundRouterFeeToken {
        uint256 balanceBridgerStart = bridger.balance;
        uint256 balanceBridgeStart = wrappedNativeToken.balanceOf(address(tokenSrc));

        tokenBridgeRouter.bridgeNative{value: AMOUNT}(
            DEST_CHAIN_HEX,
            bridger,
            address(wrappedNativeToken),
            MULTIHOP_ADDR,
            PRIM_RELAYER_FEE,
            SEC_RELAYER_FEE
        );

        uint256 balanceBridgerEnd = bridger.balance;
        uint256 balanceBridgeEnd = wrappedNativeToken.balanceOf(address(tokenSrc));
        assert(balanceBridgerStart == balanceBridgerEnd + AMOUNT);
        assert(balanceBridgeStart == balanceBridgeEnd - AMOUNT);
        vm.stopPrank();
    }

    function testEmitsWhenNativeTokensSent() public registerTokenBridge fundRouterFeeToken {
        vm.expectEmit(true, false, false, false, address(tokenBridgeRouter));
        emit BridgeNative(DEST_CHAIN_HEX, bridger, AMOUNT, PRIM_RELAYER_FEE, SEC_RELAYER_FEE);

        tokenBridgeRouter.bridgeNative{value: AMOUNT}(
            DEST_CHAIN_HEX,
            bridger,
            address(wrappedNativeToken),
            MULTIHOP_ADDR,
            PRIM_RELAYER_FEE,
            SEC_RELAYER_FEE
        );
        vm.stopPrank();
    }

    function testBalancesWhenNativeTokensSentViaBridgeAndCall()
        public
        registerTokenBridge
        fundRouterFeeToken
    {
        uint256 balanceBridgerStart = bridger.balance;
        uint256 balanceBridgeStart = wrappedNativeToken.balanceOf(address(tokenSrc));

        bytes memory payload = abi.encode("abcdefghijklmnopqrstuvwxyz");

        tokenBridgeRouter.bridgeAndCallNative{value: AMOUNT}(
            DEST_CHAIN_HEX,
            TOKEN_DEST,
            address(wrappedNativeToken),
            payload,
            bridger,
            REC_GAS_LIMIT,
            MULTIHOP_ADDR,
            PRIM_RELAYER_FEE,
            SEC_RELAYER_FEE
        );

        uint256 balanceBridgerEnd = bridger.balance;
        uint256 balanceBridgeEnd = wrappedNativeToken.balanceOf(address(tokenSrc));
        assert(balanceBridgerStart == balanceBridgerEnd + AMOUNT);
        assert(balanceBridgeStart == balanceBridgeEnd - AMOUNT);
        vm.stopPrank();
    }

    function testEmitsWhenNativeTokensSentViaBridgeAndCall()
        public
        registerTokenBridge
        fundRouterFeeToken
    {
        bytes memory payload = abi.encode("abcdefghijklmnopqrstuvwxyz");

        vm.expectEmit(true, false, false, false, address(tokenBridgeRouter));
        emit BridgeAndCallNative(DEST_CHAIN_HEX, bridger, AMOUNT, PRIM_RELAYER_FEE, SEC_RELAYER_FEE);

        tokenBridgeRouter.bridgeAndCallNative{value: AMOUNT}(
            DEST_CHAIN_HEX,
            TOKEN_DEST,
            address(wrappedNativeToken),
            payload,
            bridger,
            REC_GAS_LIMIT,
            MULTIHOP_ADDR,
            PRIM_RELAYER_FEE,
            SEC_RELAYER_FEE
        );
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {AvalancheICTTRouterFixedFees} from
    "../../../src/contracts/Teleporter/AvalancheICTTRouterFixedFees.sol";
import {WarpMessengerTestMock} from "../../../src/contracts/mocks/WarpMessengerTestMock.sol";
import {IAvalancheICTTRouter} from "../../../src/interfaces/Teleporter/IAvalancheICTTRouter.sol";
import {
    IAvalancheICTTRouterFixedFees,
    MinBridgeFees
} from "../../../src/interfaces/Teleporter/IAvalancheICTTRouterFixedFees.sol";
import {HelperConfig4Test} from "../HelperConfig4Test.t.sol";
import {ERC20TokenHome} from "@avalabs/avalanche-ictt/TokenHome/ERC20TokenHome.sol";
import {ERC20Mock} from "@openzeppelin/contracts@4.8.1/mocks/ERC20Mock.sol";
import {TeleporterMessenger} from "@teleporter/TeleporterMessenger.sol";
import {
    ProtocolRegistryEntry, TeleporterRegistry
} from "@teleporter/upgrades/TeleporterRegistry.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract AvalancheICTTRouterFixedFeesErc20TokenTest is Test {
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

    event BridgeERC20(
        address indexed tokenAddress,
        bytes32 indexed destinationBlockchainID,
        address recipient,
        uint256 amount,
        uint256 primaryRelaryFee,
        uint256 secondaryRelayerFee
    );

    event BridgeAndCallERC20(
        address indexed tokenAddress,
        bytes32 indexed destinationBlockchainID,
        address recipient,
        uint256 amount,
        uint256 primaryRelaryFee,
        uint256 secondaryRelayerFee
    );

    HelperConfig4Test helperConfig = new HelperConfig4Test();

    uint256 deployerKey;
    address owner;
    address bridger;

    ERC20Mock erc20Token;
    ERC20Mock feeToken;

    ERC20TokenHome tokenSrc;
    AvalancheICTTRouterFixedFees tokenBridgeRouter;

    ProtocolRegistryEntry[] protocolRegistryEntry;

    function setUp() external {
        (deployerKey, owner, bridger) = helperConfig.activeNetworkConfigTest();

        WarpMessengerTestMock warpMessengerTestMock = new WarpMessengerTestMock(TOKEN_SRC);
        vm.etch(WARP_PRECOMPILE, address(warpMessengerTestMock).code);

        erc20Token = new ERC20Mock("ERC20Mock", "ERC20M", makeAddr("mockRecipient"), 0);
        feeToken = new ERC20Mock("FeeTokenMock", "FTKMock", makeAddr("feeTokenHolder"), 0);

        vm.startBroadcast(deployerKey);
        TeleporterMessenger teleporterMessenger = new TeleporterMessenger();
        protocolRegistryEntry.push(ProtocolRegistryEntry(1, address(teleporterMessenger)));
        TeleporterRegistry teleporterRegistry = new TeleporterRegistry(protocolRegistryEntry);

        tokenSrc = new ERC20TokenHome(address(teleporterRegistry), owner, address(erc20Token), 18);
        tokenBridgeRouter =
            new AvalancheICTTRouterFixedFees(PRIM_RELAYER_FEE_BIPS, SEC_RELAYER_FEE_BIPS);
        vm.stopBroadcast();

        teleporterMessenger.receiveCrossChainMessage(1, address(0));

        vm.deal(bridger, STARTING_GAS_BALANCE);
    }

    modifier registerTokenBridge() {
        vm.startPrank(owner);
        tokenBridgeRouter.registerSourceTokenBridge(address(erc20Token), TOKEN_SRC);
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token),
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

    modifier registerTokenBridgeMultihop() {
        vm.startPrank(owner);
        tokenBridgeRouter.registerSourceTokenBridge(address(erc20Token), TOKEN_SRC);
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token),
            DEST_CHAIN_HEX,
            TOKEN_DEST,
            REQ_GAS_LIMIT,
            true,
            MIN_PRIM_RELAYER_FEE,
            MIN_SEC_RELAYER_FEE
        );
        vm.stopPrank();
        _;
    }

    modifier fundBridgerAccount() {
        vm.startPrank(bridger);
        erc20Token.mint(bridger, 10 ether);
        _;
    }

    function testRevertsIfBridgedAmountNotEnoughToPayMinBridgeFees()
        public
        registerTokenBridge
        fundBridgerAccount
    {
        uint256 tooLittleAmount = 0.000000001 ether;

        uint256 primaryRelayerFee = (tooLittleAmount * PRIM_RELAYER_FEE_BIPS) / 10_000;
        MinBridgeFees memory minBridgeFees = MinBridgeFees(MIN_PRIM_RELAYER_FEE, 0);

        erc20Token.approve(address(tokenBridgeRouter), tooLittleAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAvalancheICTTRouterFixedFees
                    .AvalancheICTTRouterFixedFees__RelayerFeesTooLow
                    .selector,
                primaryRelayerFee,
                0,
                minBridgeFees
            )
        );
        tokenBridgeRouter.bridgeERC20(
            address(erc20Token), DEST_CHAIN_HEX, tooLittleAmount, bridger, MULTIHOP_ADDR
        );
    }

    function testRevertsIfBridgedAmountNotEnoughToPayMinBridgeFeesMultihop()
        public
        registerTokenBridgeMultihop
        fundBridgerAccount
    {
        uint256 tooLittleAmount = 0.000000001 ether;

        uint256 primaryRelayerFee = (tooLittleAmount * PRIM_RELAYER_FEE_BIPS) / 10_000;
        uint256 secondaryRelayerFee = (tooLittleAmount * SEC_RELAYER_FEE_BIPS) / 10_000;
        MinBridgeFees memory minBridgeFees =
            MinBridgeFees(MIN_PRIM_RELAYER_FEE, MIN_SEC_RELAYER_FEE);

        erc20Token.approve(address(tokenBridgeRouter), tooLittleAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAvalancheICTTRouterFixedFees
                    .AvalancheICTTRouterFixedFees__RelayerFeesTooLow
                    .selector,
                primaryRelayerFee,
                secondaryRelayerFee,
                minBridgeFees
            )
        );
        tokenBridgeRouter.bridgeERC20(
            address(erc20Token), DEST_CHAIN_HEX, tooLittleAmount, bridger, MULTIHOP_ADDR
        );
    }

    function testBalancesWhenERC20TokensSent() public registerTokenBridge fundBridgerAccount {
        uint256 initialBalanceBridgerERC20Token = erc20Token.balanceOf(bridger);
        uint256 initialBalanceBridgeERC20Token = erc20Token.balanceOf(TOKEN_SRC);

        erc20Token.approve(address(tokenBridgeRouter), AMOUNT);

        tokenBridgeRouter.bridgeERC20(
            address(erc20Token), DEST_CHAIN_HEX, AMOUNT, bridger, MULTIHOP_ADDR
        );

        uint256 feesPaid = (AMOUNT * PRIM_RELAYER_FEE_BIPS) / 10_000;

        uint256 finalBalanceBridgerERC20Token = erc20Token.balanceOf(bridger);
        uint256 finalBalanceBridgeERC20Token = erc20Token.balanceOf(TOKEN_SRC);

        assert(initialBalanceBridgerERC20Token == finalBalanceBridgerERC20Token + AMOUNT);
        assert(initialBalanceBridgeERC20Token == finalBalanceBridgeERC20Token - (AMOUNT - feesPaid));
        vm.stopPrank();
    }

    function testEmitsWhenERC20TokensSent() public registerTokenBridge fundBridgerAccount {
        erc20Token.approve(address(tokenBridgeRouter), AMOUNT);

        vm.expectEmit(true, true, false, false, address(tokenBridgeRouter));
        emit BridgeERC20(
            address(erc20Token),
            DEST_CHAIN_HEX,
            bridger,
            AMOUNT,
            (AMOUNT * PRIM_RELAYER_FEE_BIPS) / 10_000,
            0
        );
        tokenBridgeRouter.bridgeERC20(
            address(erc20Token), DEST_CHAIN_HEX, AMOUNT, bridger, MULTIHOP_ADDR
        );
        vm.stopPrank();
    }

    function testBalancesWhenERC20TokensSentViaBridgeAndCall()
        public
        registerTokenBridge
        fundBridgerAccount
    {
        uint256 initialBalanceBridgerERC20Token = erc20Token.balanceOf(bridger);
        uint256 initialBalanceBridgeERC20Token = erc20Token.balanceOf(TOKEN_SRC);
        bytes memory payload = abi.encode("abcdefghijklmnopqrstuvwxyz");

        erc20Token.approve(address(tokenBridgeRouter), AMOUNT);

        tokenBridgeRouter.bridgeAndCallERC20(
            address(erc20Token),
            DEST_CHAIN_HEX,
            AMOUNT,
            TOKEN_DEST,
            payload,
            bridger,
            REC_GAS_LIMIT,
            MULTIHOP_ADDR
        );

        uint256 feesPaid = (AMOUNT * PRIM_RELAYER_FEE_BIPS) / 10_000;

        uint256 finalBalanceBridgerERC20Token = erc20Token.balanceOf(bridger);
        uint256 finalBalanceBridgeERC20Token = erc20Token.balanceOf(TOKEN_SRC);

        assert(initialBalanceBridgerERC20Token == finalBalanceBridgerERC20Token + AMOUNT);
        assert(initialBalanceBridgeERC20Token == finalBalanceBridgeERC20Token - (AMOUNT - feesPaid));
        vm.stopPrank();
    }

    function testEmitsWhenERC20TokensSentViaBridgeAndCall()
        public
        registerTokenBridge
        fundBridgerAccount
    {
        bytes memory payload = abi.encode("abcdefghijklmnopqrstuvwxyz");

        erc20Token.approve(address(tokenBridgeRouter), AMOUNT);

        vm.expectEmit(true, true, false, false, address(tokenBridgeRouter));
        emit BridgeAndCallERC20(
            address(erc20Token),
            DEST_CHAIN_HEX,
            TOKEN_DEST,
            AMOUNT,
            (AMOUNT * PRIM_RELAYER_FEE_BIPS) / 10_000,
            0
        );
        tokenBridgeRouter.bridgeAndCallERC20(
            address(erc20Token),
            DEST_CHAIN_HEX,
            AMOUNT,
            TOKEN_DEST,
            payload,
            bridger,
            REC_GAS_LIMIT,
            MULTIHOP_ADDR
        );
        vm.stopPrank();
    }
}

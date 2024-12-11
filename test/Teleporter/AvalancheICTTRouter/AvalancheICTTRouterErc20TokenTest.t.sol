// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {AvalancheICTTRouter} from "../../../src/contracts/Teleporter/AvalancheICTTRouter.sol";
import {WarpMessengerTestMock} from "../../../src/contracts/mocks/WarpMessengerTestMock.sol";
import {HelperConfig4Test} from "../HelperConfig4Test.t.sol";
import {ERC20TokenHome} from "@avalabs/avalanche-ictt/TokenHome/ERC20TokenHome.sol";
import {ERC20Mock} from "@openzeppelin/contracts@4.8.1/mocks/ERC20Mock.sol";
import {TeleporterMessenger} from "@teleporter/TeleporterMessenger.sol";
import {
    ProtocolRegistryEntry, TeleporterRegistry
} from "@teleporter/upgrades/TeleporterRegistry.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract AvalancheICTTRouterErc20TokenTest is Test {
    address private constant WARP_PRECOMPILE = 0x0200000000000000000000000000000000000005;

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
    AvalancheICTTRouter tokenBridgeRouter;

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
        tokenBridgeRouter = new AvalancheICTTRouter();
        vm.stopBroadcast();

        teleporterMessenger.receiveCrossChainMessage(1, address(0));

        vm.deal(bridger, STARTING_GAS_BALANCE);
    }

    modifier registerTokenBridge() {
        vm.startPrank(owner);
        tokenBridgeRouter.registerSourceTokenBridge(address(erc20Token), TOKEN_SRC);
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token), DEST_CHAIN_HEX, TOKEN_DEST, REQ_GAS_LIMIT, false
        );
        vm.stopPrank();
        _;
    }

    modifier fundBridgerAccount() {
        vm.startPrank(bridger);
        erc20Token.mint(bridger, 10 ether);
        _;
    }

    modifier fundFeeBridgerAccount() {
        feeToken.mint(bridger, 1 ether);
        _;
    }

    function testBalancesWhenERC20TokensSent()
        public
        registerTokenBridge
        fundBridgerAccount
        fundFeeBridgerAccount
    {
        uint256 initialBalanceBridgerERC20Token = erc20Token.balanceOf(bridger);
        uint256 initialBalanceBridgeERC20Token = erc20Token.balanceOf(TOKEN_SRC);
        uint256 initialBalanceBridgerFeeToken = feeToken.balanceOf(bridger);

        erc20Token.approve(address(tokenBridgeRouter), AMOUNT);
        feeToken.approve(address(tokenBridgeRouter), PRIM_RELAYER_FEE);

        tokenBridgeRouter.bridgeERC20(
            address(erc20Token),
            DEST_CHAIN_HEX,
            AMOUNT,
            bridger,
            MULTIHOP_ADDR,
            address(feeToken),
            PRIM_RELAYER_FEE,
            SEC_RELAYER_FEE
        );

        uint256 finalBalanceBridgerERC20Token = erc20Token.balanceOf(bridger);
        uint256 finalBalanceBridgeERC20Token = erc20Token.balanceOf(TOKEN_SRC);
        uint256 finalBalanceBridgerFeeToken = feeToken.balanceOf(bridger);

        assert(initialBalanceBridgerERC20Token == finalBalanceBridgerERC20Token + AMOUNT);
        assert(initialBalanceBridgeERC20Token == finalBalanceBridgeERC20Token - AMOUNT);
        assert(initialBalanceBridgerFeeToken == finalBalanceBridgerFeeToken + PRIM_RELAYER_FEE);
        vm.stopPrank();
    }

    function testEmitsWhenERC20TokensSent()
        public
        registerTokenBridge
        fundBridgerAccount
        fundFeeBridgerAccount
    {
        erc20Token.approve(address(tokenBridgeRouter), AMOUNT);
        feeToken.approve(address(tokenBridgeRouter), PRIM_RELAYER_FEE);

        vm.expectEmit(true, true, false, false, address(tokenBridgeRouter));
        emit BridgeERC20(
            address(erc20Token), DEST_CHAIN_HEX, bridger, AMOUNT, PRIM_RELAYER_FEE, SEC_RELAYER_FEE
        );
        tokenBridgeRouter.bridgeERC20(
            address(erc20Token),
            DEST_CHAIN_HEX,
            AMOUNT,
            bridger,
            MULTIHOP_ADDR,
            address(feeToken),
            PRIM_RELAYER_FEE,
            SEC_RELAYER_FEE
        );

        vm.stopPrank();
    }

    function testBalancesWhenERC20TokensSentViaBridgeAndCall()
        public
        registerTokenBridge
        fundBridgerAccount
        fundFeeBridgerAccount
    {
        bytes memory payload = abi.encode("abcdefghijklmnopqrstuvwxyz");

        uint256 initialBalanceBridgerERC20Token = erc20Token.balanceOf(bridger);
        uint256 initialBalanceBridgeERC20Token = erc20Token.balanceOf(TOKEN_SRC);
        uint256 initialBalanceBridgerFeeToken = feeToken.balanceOf(bridger);

        erc20Token.approve(address(tokenBridgeRouter), AMOUNT);
        feeToken.approve(address(tokenBridgeRouter), PRIM_RELAYER_FEE);

        tokenBridgeRouter.bridgeAndCallERC20(
            address(erc20Token),
            DEST_CHAIN_HEX,
            AMOUNT,
            TOKEN_DEST,
            payload,
            bridger,
            REC_GAS_LIMIT,
            MULTIHOP_ADDR,
            address(feeToken),
            PRIM_RELAYER_FEE,
            SEC_RELAYER_FEE
        );

        uint256 finalBalanceBridgerERC20Token = erc20Token.balanceOf(bridger);
        uint256 finalBalanceBridgeERC20Token = erc20Token.balanceOf(TOKEN_SRC);
        uint256 finalBalanceBridgerFeeToken = feeToken.balanceOf(bridger);

        assert(initialBalanceBridgerERC20Token == finalBalanceBridgerERC20Token + AMOUNT);
        assert(initialBalanceBridgeERC20Token == finalBalanceBridgeERC20Token - AMOUNT);
        assert(initialBalanceBridgerFeeToken == finalBalanceBridgerFeeToken + PRIM_RELAYER_FEE);
        vm.stopPrank();
    }

    function testEmitsWhenERC20TokensSentViaBridgeAndCall()
        public
        registerTokenBridge
        fundBridgerAccount
        fundFeeBridgerAccount
    {
        bytes memory payload = abi.encode("abcdefghijklmnopqrstuvwxyz");

        erc20Token.approve(address(tokenBridgeRouter), AMOUNT);
        feeToken.approve(address(tokenBridgeRouter), PRIM_RELAYER_FEE);

        vm.expectEmit(true, true, false, false, address(tokenBridgeRouter));
        emit BridgeAndCallERC20(
            address(erc20Token),
            DEST_CHAIN_HEX,
            TOKEN_DEST,
            AMOUNT,
            PRIM_RELAYER_FEE,
            SEC_RELAYER_FEE
        );
        tokenBridgeRouter.bridgeAndCallERC20(
            address(erc20Token),
            DEST_CHAIN_HEX,
            AMOUNT,
            TOKEN_DEST,
            payload,
            bridger,
            REC_GAS_LIMIT,
            MULTIHOP_ADDR,
            address(feeToken),
            PRIM_RELAYER_FEE,
            SEC_RELAYER_FEE
        );
        vm.stopPrank();
    }
}

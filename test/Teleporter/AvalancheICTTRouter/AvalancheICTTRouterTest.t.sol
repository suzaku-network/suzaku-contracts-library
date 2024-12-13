// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {
    AvalancheICTTRouter,
    DestinationBridge
} from "../../../src/contracts/Teleporter/AvalancheICTTRouter.sol";
import {WarpMessengerTestMock} from "../../../src/contracts/mocks/WarpMessengerTestMock.sol";
import {IAvalancheICTTRouter} from "../../../src/interfaces/Teleporter/IAvalancheICTTRouter.sol";
import {HelperConfig4Test} from "../HelperConfig4Test.t.sol";

import {ERC20TokenHome} from "@avalabs/icm-contracts/ictt/TokenHome/ERC20TokenHome.sol";
import {TeleporterMessenger} from "@avalabs/icm-contracts/teleporter/TeleporterMessenger.sol";
import {
    ProtocolRegistryEntry,
    TeleporterRegistry
} from "@avalabs/icm-contracts/teleporter/registry/TeleporterRegistry.sol";
import {ERC20Mock} from "@openzeppelin/contracts@5.0.2/mocks/token/ERC20Mock.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract AvalancheICTTRouterTest is Test {
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

    event RegisterSourceTokenBridge(address indexed tokenAddress, address indexed bridgeAddress);
    event RegisterDestinationTokenBridge(
        address indexed tokenAddress,
        bytes32 indexed destinationChainID,
        DestinationBridge indexed destinationBridge
    );
    event RemoveSourceTokenBridge(address indexed tokenAddress);
    event RemoveDestinationTokenBridge(
        address indexed tokenAddress, bytes32 indexed destinationChainID
    );

    HelperConfig4Test helperConfig = new HelperConfig4Test();

    uint256 deployerKey;
    address owner;
    address bridger;

    ERC20Mock erc20Token;

    ERC20TokenHome tokenSrc;
    AvalancheICTTRouter tokenBridgeRouter;
    ProtocolRegistryEntry[] protocolRegistryEntry;

    function setUp() external {
        (deployerKey, owner, bridger) = helperConfig.activeNetworkConfigTest();

        WarpMessengerTestMock warpMessengerTestMock = new WarpMessengerTestMock(TOKEN_SRC);
        vm.etch(WARP_PRECOMPILE, address(warpMessengerTestMock).code);

        erc20Token = new ERC20Mock();

        vm.startBroadcast(deployerKey);
        TeleporterMessenger teleporterMessenger = new TeleporterMessenger();
        protocolRegistryEntry.push(ProtocolRegistryEntry(1, address(teleporterMessenger)));
        TeleporterRegistry teleporterRegistry = new TeleporterRegistry(protocolRegistryEntry);

        tokenSrc = new ERC20TokenHome(
            address(teleporterRegistry), owner, MIN_TELEPORTER_VERSION, address(erc20Token), 18
        );
        tokenBridgeRouter = new AvalancheICTTRouter(owner);
        vm.stopBroadcast();

        teleporterMessenger.receiveCrossChainMessage(1, address(0));

        vm.deal(bridger, STARTING_GAS_BALANCE);
    }

    function testBridgeAddrNotAContractRevertOnRegisterSourceTokenBridge() public {
        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAvalancheICTTRouter.AvalancheICTTRouter__BridgeAddrNotAContract.selector,
                address(0)
            )
        );
        tokenBridgeRouter.registerSourceTokenBridge(address(erc20Token), address(0));
        vm.stopPrank();
    }

    function testTokenAddrNotAContractRevertOnRegisterSourceTokenBridge() public {
        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAvalancheICTTRouter.AvalancheICTTRouter__TokenAddrNotAContract.selector,
                address(0x1111111111111111111111111111111111111111)
            )
        );
        tokenBridgeRouter.registerSourceTokenBridge(
            address(0x1111111111111111111111111111111111111111), TOKEN_SRC
        );
        vm.stopPrank();
    }

    function testSourceChainEqualToDestinationChainRevertOnRegisterDestinationTokenBridge()
        public
    {
        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAvalancheICTTRouter.AvalancheICTTRouter__SourceChainEqualsDestinationChain.selector,
                SRC_CHAIN_HEX,
                SRC_CHAIN_HEX
            )
        );
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token), SRC_CHAIN_HEX, TOKEN_DEST, REQ_GAS_LIMIT, false
        );
        vm.stopPrank();
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

    function testEmitsOnRegisterSourceTokenBridge() public {
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, false, address(tokenBridgeRouter));
        emit RegisterSourceTokenBridge(address(erc20Token), TOKEN_SRC);
        tokenBridgeRouter.registerSourceTokenBridge(address(erc20Token), TOKEN_SRC);
        vm.stopPrank();
    }

    function testEmitsOnRegisterDestinationTokenBridge() public {
        vm.startPrank(owner);
        DestinationBridge memory destinationBridge =
            DestinationBridge(TOKEN_DEST, REQ_GAS_LIMIT, false);
        vm.expectEmit(true, true, true, false, address(tokenBridgeRouter));
        emit RegisterDestinationTokenBridge(address(erc20Token), DEST_CHAIN_HEX, destinationBridge);
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token), DEST_CHAIN_HEX, TOKEN_DEST, REQ_GAS_LIMIT, false
        );
        vm.stopPrank();
    }

    function testGetSourceBridgeAfterRegister() public registerTokenBridge {
        assert(tokenBridgeRouter.getSourceBridge(address(erc20Token)) == TOKEN_SRC);
    }

    function testGetDestinationBridgeConfigAfterRegister() public registerTokenBridge {
        DestinationBridge memory destinationBridge =
            tokenBridgeRouter.getDestinationBridge(DEST_CHAIN_HEX, address(erc20Token));
        assert(
            destinationBridge.bridgeAddress == TOKEN_DEST
                && destinationBridge.requiredGasLimit == REQ_GAS_LIMIT
        );
    }

    function testEmitsOnRemoveSourceTokenBridge() public {
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, false, address(tokenBridgeRouter));
        emit RemoveSourceTokenBridge(address(erc20Token));
        tokenBridgeRouter.removeSourceTokenBridge(address(erc20Token));
        vm.stopPrank();
    }

    function testEmitsOnRemoveDestinationTokenBridge() public {
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, false, address(tokenBridgeRouter));
        emit RemoveDestinationTokenBridge(address(erc20Token), DEST_CHAIN_HEX);
        tokenBridgeRouter.removeDestinationTokenBridge(address(erc20Token), DEST_CHAIN_HEX);
        vm.stopPrank();
    }

    function testTokenAddedToTokensListWhenRegisterTokenSource() public {
        vm.startPrank(owner);
        address[] memory startList = tokenBridgeRouter.getTokensList();
        assert(startList.length == 0);
        tokenBridgeRouter.registerSourceTokenBridge(address(erc20Token), TOKEN_SRC);
        address[] memory endList = tokenBridgeRouter.getTokensList();
        assert(endList.length == 1 && endList[0] == address(erc20Token));
        vm.stopPrank();
    }

    function testTokenRemovedFromTokensListWhenRemovingTokenSource() public registerTokenBridge {
        vm.startPrank(owner);
        address[] memory startList = tokenBridgeRouter.getTokensList();
        assert(startList.length == 1 && startList[0] == address(erc20Token));
        tokenBridgeRouter.removeSourceTokenBridge(address(erc20Token));
        address[] memory endList = tokenBridgeRouter.getTokensList();
        assert(endList.length == 0);
        vm.stopPrank();
    }

    function testDestinationChainAddedToTokenToDestinationChainsListWhenRegisterTokenDestination()
        public
    {
        vm.startPrank(owner);
        bytes32[] memory startList =
            tokenBridgeRouter.getDestinationChainsForToken(address(erc20Token));
        assert(startList.length == 0);
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token), DEST_CHAIN_HEX, TOKEN_DEST, REQ_GAS_LIMIT, false
        );
        bytes32[] memory endList =
            tokenBridgeRouter.getDestinationChainsForToken(address(erc20Token));
        assert(endList.length == 1 && endList[0] == DEST_CHAIN_HEX);
        vm.stopPrank();
    }

    function testDestinationChainRemovedFromDestinationChainsListWhenRemovingTokenDestination()
        public
    {
        vm.startPrank(owner);
        tokenBridgeRouter.registerSourceTokenBridge(address(erc20Token), TOKEN_SRC);
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token), bytes32("a"), TOKEN_DEST, REQ_GAS_LIMIT, false
        );
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token), bytes32("b"), TOKEN_DEST, REQ_GAS_LIMIT, false
        );
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token), bytes32("c"), TOKEN_DEST, REQ_GAS_LIMIT, false
        );
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token), bytes32("d"), TOKEN_DEST, REQ_GAS_LIMIT, false
        );
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token), bytes32("e"), TOKEN_DEST, REQ_GAS_LIMIT, false
        );

        bytes32[] memory startList =
            tokenBridgeRouter.getDestinationChainsForToken(address(erc20Token));
        assert(_contains(startList, bytes32("b")));
        tokenBridgeRouter.removeDestinationTokenBridge(address(erc20Token), bytes32("b"));
        bytes32[] memory endList =
            tokenBridgeRouter.getDestinationChainsForToken(address(erc20Token));
        assert(!_contains(endList, bytes32("b")));
        assertEq(endList.length, startList.length - 1);
        vm.stopPrank();
    }

    function _contains(bytes32[] memory list, bytes32 element) internal pure returns (bool) {
        for (uint256 i; i < list.length; i++) {
            if (list[i] == element) {
                return true;
            }
        }
        return false;
    }
}

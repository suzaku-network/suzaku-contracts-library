// SPDX-License-Identifier: UNLICENSED
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {
    AvalancheICTTRouter,
    DestinationBridge
} from "../../../src/contracts/Teleporter/AvalancheICTTRouter.sol";
import {IAvalancheICTTRouter} from "../../../src/interfaces/Teleporter/IAvalancheICTTRouter.sol";
import {HelperConfig4Test} from "../HelperConfig4Test.t.sol";
import {ERC20TokenHome} from "@avalabs/avalanche-ictt/TokenHome/ERC20TokenHome.sol";
import {ERC20Mock} from "@openzeppelin/contracts@4.8.1/mocks/ERC20Mock.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract AvalancheICTTRouterTest is Test {
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

    HelperConfig4Test helperConfig = new HelperConfig4Test(address(0), 0);
    uint256 deployerKey;
    address owner;
    address bridger;
    bytes32 messageId;

    ERC20Mock erc20Token;

    ERC20TokenHome erc20TokenSource;
    address tokenDestination;
    AvalancheICTTRouter tokenBridgeRouter;
    bytes32 sourceChainID;
    bytes32 destinationChainID;

    uint256 requiredGasLimit = 10_000_000;
    address multihopFallBackAddress = address(0);

    uint256 constant STARTING_GAS_BALANCE = 10 ether;

    function setUp() external {
        (
            deployerKey,
            owner,
            bridger,
            messageId,
            ,
            ,
            erc20Token,
            ,
            ,
            erc20TokenSource,
            ,
            tokenDestination,
            tokenBridgeRouter,
            ,
            sourceChainID,
            destinationChainID,
            ,
            ,
        ) = helperConfig.activeNetworkConfigTest();
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
            address(0x1111111111111111111111111111111111111111), address(erc20TokenSource)
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
                sourceChainID,
                sourceChainID
            )
        );
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token),
            sourceChainID,
            tokenDestination,
            requiredGasLimit,
            false,
            0.00001 ether,
            0.00001 ether
        );
        vm.stopPrank();
    }

    modifier registerTokenBridge() {
        vm.startPrank(owner);
        tokenBridgeRouter.registerSourceTokenBridge(address(erc20Token), address(erc20TokenSource));
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token),
            destinationChainID,
            tokenDestination,
            requiredGasLimit,
            false,
            0.00001 ether,
            0.00001 ether
        );
        vm.stopPrank();
        _;
    }

    function testEmitsOnRegisterSourceTokenBridge() public {
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, false, address(tokenBridgeRouter));
        emit RegisterSourceTokenBridge(address(erc20Token), address(erc20TokenSource));
        tokenBridgeRouter.registerSourceTokenBridge(address(erc20Token), address(erc20TokenSource));
        vm.stopPrank();
    }

    function testEmitsOnRegisterDestinationTokenBridge() public {
        vm.startPrank(owner);
        DestinationBridge memory destinationBridge = DestinationBridge(
            tokenDestination, requiredGasLimit, false, 0.00001 ether, 0.00001 ether
        );
        vm.expectEmit(true, true, true, false, address(tokenBridgeRouter));
        emit RegisterDestinationTokenBridge(
            address(erc20Token), destinationChainID, destinationBridge
        );
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token),
            destinationChainID,
            tokenDestination,
            requiredGasLimit,
            false,
            0.00001 ether,
            0.00001 ether
        );
        vm.stopPrank();
    }

    function testGetSourceBridgeAfterRegister() public registerTokenBridge {
        assert(tokenBridgeRouter.getSourceBridge(address(erc20Token)) == address(erc20TokenSource));
    }

    function testGetDestinationBridgeConfigAfterRegister() public registerTokenBridge {
        DestinationBridge memory destinationBridge =
            tokenBridgeRouter.getDestinationBridge(destinationChainID, address(erc20Token));
        assert(
            destinationBridge.bridgeAddress == tokenDestination
                && destinationBridge.requiredGasLimit == requiredGasLimit
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
        emit RemoveDestinationTokenBridge(address(erc20Token), destinationChainID);
        tokenBridgeRouter.removeDestinationTokenBridge(address(erc20Token), destinationChainID);
        vm.stopPrank();
    }

    function testTokenAddedToTokensListWhenRegisterTokenSource() public {
        vm.startPrank(owner);
        address[] memory startList = tokenBridgeRouter.getTokensList();
        assert(startList.length == 0);
        tokenBridgeRouter.registerSourceTokenBridge(address(erc20Token), address(erc20TokenSource));
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
            address(erc20Token),
            destinationChainID,
            tokenDestination,
            requiredGasLimit,
            false,
            0.00001 ether,
            0.00001 ether
        );
        bytes32[] memory endList =
            tokenBridgeRouter.getDestinationChainsForToken(address(erc20Token));
        assert(endList.length == 1 && endList[0] == destinationChainID);
        vm.stopPrank();
    }

    function testDestinationChainRemovedFromDestinationChainsListWhenRemovingTokenDestination()
        public
    {
        vm.startPrank(owner);
        tokenBridgeRouter.registerSourceTokenBridge(address(erc20Token), address(erc20TokenSource));
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token), bytes32("a"), tokenDestination, requiredGasLimit, false, 0, 0
        );
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token), bytes32("b"), tokenDestination, requiredGasLimit, false, 0, 0
        );
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token), bytes32("c"), tokenDestination, requiredGasLimit, false, 0, 0
        );
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token), bytes32("d"), tokenDestination, requiredGasLimit, false, 0, 0
        );
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token), bytes32("e"), tokenDestination, requiredGasLimit, false, 0, 0
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

// SPDX-License-Identifier: UNLICENSED
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {
    AvalancheICTTRouterEnforcedFees,
    DestinationBridge
} from "../../../src/contracts/Teleporter/AvalancheICTTRouterEnforcedFees.sol";
import {IAvalancheICTTRouter} from "../../../src/interfaces/IAvalancheICTTRouter.sol";
import {HelperConfig4Test} from "../HelperConfig4Test.t.sol";
import {ERC20TokenHome} from "@avalabs/avalanche-ictt/TokenHome/ERC20TokenHome.sol";
import {WrappedNativeToken} from "@avalabs/avalanche-ictt/WrappedNativeToken.sol";
import {ERC20Mock} from "@openzeppelin/contracts@4.8.1/mocks/ERC20Mock.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract AvalancheICTTRouterTest is Test {
    event ChangeRelayerFees(uint256 primaryRelayerFee, uint256 secondaryRelayerFee);
    event RegisterSourceTokenBridge(address indexed tokenAddress, address indexed bridgeAddress);
    event RegisterDestinationTokenBridge(
        address indexed tokenAddress,
        DestinationBridge indexed destinationBridge,
        bytes32 indexed destinationChainID
    );
    event RemoveSourceTokenBridge(address indexed tokenAddress);
    event RemoveDestinationTokenBridge(
        address indexed tokenAddress, bytes32 indexed destinationChainID
    );

    HelperConfig4Test helperConfig = new HelperConfig4Test(address(0), 1);
    AvalancheICTTRouterEnforcedFees tokenBridgeRouter;
    uint256 deployerKey;
    ERC20Mock erc20Token;
    ERC20TokenHome tokenSource;
    address tokenDestination;
    bytes32 sourceChainID;
    bytes32 destinationChainID;
    address owner;
    address bridger;
    bytes32 messageId;
    uint256 requiredGasLimit = 10_000_000;

    uint256 constant STARTING_GAS_BALANCE = 10 ether;

    function setUp() external {
        (
            deployerKey,
            ,
            ,
            erc20Token,
            ,
            tokenSource,
            ,
            tokenDestination,
            ,
            tokenBridgeRouter,
            sourceChainID,
            destinationChainID,
            owner,
            bridger,
            messageId,
            ,
        ) = helperConfig.activeNetworkConfigTest();
        vm.deal(bridger, STARTING_GAS_BALANCE);
    }

    function testNotAContractRevertOnRegisterSourceTokenBridge() public {
        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IAvalancheICTTRouter.NotAContract.selector, address(0))
        );
        tokenBridgeRouter.registerSourceTokenBridge(address(erc20Token), address(0));
        vm.stopPrank();
    }

    function testSourceChainEqualToDestinationChainRevertOnRegisterDestinationTokenBridge()
        public
    {
        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAvalancheICTTRouter.SourceChainEqualToDestinationChain.selector,
                sourceChainID,
                sourceChainID
            )
        );
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token), sourceChainID, tokenDestination, requiredGasLimit, false
        );
        vm.stopPrank();
    }

    modifier registerTokenBridge() {
        vm.startPrank(owner);
        tokenBridgeRouter.registerSourceTokenBridge(address(erc20Token), address(tokenSource));
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token), destinationChainID, tokenDestination, requiredGasLimit, false
        );
        vm.stopPrank();
        _;
    }

    function testSetRelayerFee() public {
        vm.startPrank(owner);
        (uint256 primaryRelayerFeeStart, uint256 secondaryRelayerFeeStart) =
            tokenBridgeRouter.getRelayerFeesBips();
        uint256 primaryRelayerFeeValue = 50;
        uint256 secondaryRelayerFeeValue = 20;
        tokenBridgeRouter.setRelayerFeesBips(primaryRelayerFeeValue, secondaryRelayerFeeValue);
        (uint256 primaryRelayerFeeEnd, uint256 secondaryRelayerFeeEnd) =
            tokenBridgeRouter.getRelayerFeesBips();
        assert(
            (primaryRelayerFeeStart != primaryRelayerFeeEnd)
                && (secondaryRelayerFeeStart != secondaryRelayerFeeEnd)
        );
        assert(
            (primaryRelayerFeeEnd == primaryRelayerFeeValue)
                && (secondaryRelayerFeeEnd == secondaryRelayerFeeValue)
        );
        vm.stopPrank();
    }

    function testEmitsOnSetRelayerFee() public {
        vm.startPrank(owner);
        uint256 primaryRelayerFeeValue = 50;
        uint256 secondaryRelayerFeeValue = 20;
        vm.expectEmit(true, true, false, false, address(tokenBridgeRouter));
        emit ChangeRelayerFees(primaryRelayerFeeValue, secondaryRelayerFeeValue);
        tokenBridgeRouter.setRelayerFeesBips(primaryRelayerFeeValue, secondaryRelayerFeeValue);
        vm.stopPrank();
    }

    function testEmitsOnRegisterSourceTokenBridge() public {
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, false, address(tokenBridgeRouter));
        emit RegisterSourceTokenBridge(address(erc20Token), address(tokenSource));
        tokenBridgeRouter.registerSourceTokenBridge(address(erc20Token), address(tokenSource));
        vm.stopPrank();
    }

    function testEmitsOnRegisterDestinationTokenBridge() public {
        vm.startPrank(owner);
        DestinationBridge memory destinationBridge =
            DestinationBridge(tokenDestination, requiredGasLimit, false);
        vm.expectEmit(true, true, true, false, address(tokenBridgeRouter));
        emit RegisterDestinationTokenBridge(
            address(erc20Token), destinationBridge, destinationChainID
        );
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token), destinationChainID, tokenDestination, requiredGasLimit, false
        );
        vm.stopPrank();
    }

    function testGetSourceBridgeAfterRegister() public registerTokenBridge {
        assert(tokenBridgeRouter.getSourceBridge(address(erc20Token)) == address(tokenSource));
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
}

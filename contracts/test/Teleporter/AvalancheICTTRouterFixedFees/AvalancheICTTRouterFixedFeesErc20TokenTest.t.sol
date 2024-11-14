// SPDX-License-Identifier: UNLICENSED
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {AvalancheICTTRouterFixedFees} from
    "../../../src/contracts/Teleporter/AvalancheICTTRouterFixedFees.sol";
import {WarpMessengerTestMock} from "../../../src/contracts/mocks/WarpMessengerTestMock.sol";
import {IAvalancheICTTRouter} from "../../../src/interfaces/Teleporter/IAvalancheICTTRouter.sol";
import {HelperConfig4Test} from "../HelperConfig4Test.t.sol";
import {ERC20TokenHome} from "@avalabs/avalanche-ictt/TokenHome/ERC20TokenHome.sol";
import {ERC20Mock} from "@openzeppelin/contracts@4.8.1/mocks/ERC20Mock.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract AvalancheICTTRouterFixedFeesErc20TokenTest is Test {
    address private constant TOKEN_SOURCE = 0x6D411e0A54382eD43F02410Ce1c7a7c122afA6E1;

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

    HelperConfig4Test helperConfig = new HelperConfig4Test(TOKEN_SOURCE, 1);

    uint256 deployerKey;
    address owner;
    address bridger;
    bytes32 messageId;
    address warpPrecompileAddress;
    WarpMessengerTestMock warpMessengerTestMock;

    ERC20Mock erc20Token;

    ERC20TokenHome erc20TokenSource;
    address tokenDestination;
    AvalancheICTTRouterFixedFees tokenBridgeRouter;
    bytes32 sourceChainID;
    bytes32 destinationChainID;

    uint256 primaryRelayerFeeBips;
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
            erc20Token,
            ,
            ,
            erc20TokenSource,
            ,
            tokenDestination,
            ,
            tokenBridgeRouter,
            sourceChainID,
            destinationChainID,
            primaryRelayerFeeBips,
            ,
            amount
        ) = helperConfig.activeNetworkConfigTest();
        vm.deal(bridger, STARTING_GAS_BALANCE);

        vm.etch(warpPrecompileAddress, address(warpMessengerTestMock).code);
    }

    modifier registerTokenBridge() {
        vm.startPrank(owner);
        tokenBridgeRouter.registerSourceTokenBridge(address(erc20Token), address(erc20TokenSource));
        tokenBridgeRouter.registerDestinationTokenBridge(
            address(erc20Token), destinationChainID, tokenDestination, requiredGasLimit, false
        );
        vm.stopPrank();
        _;
    }

    modifier fundBridgerAccount() {
        vm.startPrank(bridger);
        erc20Token.mint(bridger, 10 ether);
        _;
    }

    function testBalancesWhenERC20TokensSent() public registerTokenBridge fundBridgerAccount {
        uint256 initialBalanceBridgerERC20Token = erc20Token.balanceOf(bridger);
        uint256 initialBalanceBridgeERC20Token = erc20Token.balanceOf(address(erc20TokenSource));

        erc20Token.approve(address(tokenBridgeRouter), amount);

        tokenBridgeRouter.bridgeERC20(
            address(erc20Token), destinationChainID, amount, bridger, multihopFallBackAddress
        );

        uint256 feesPaid = (amount * primaryRelayerFeeBips) / 10_000;

        uint256 finalBalanceBridgerERC20Token = erc20Token.balanceOf(bridger);
        uint256 finalBalanceBridgeERC20Token = erc20Token.balanceOf(address(erc20TokenSource));

        assert(initialBalanceBridgerERC20Token == finalBalanceBridgerERC20Token + amount);
        assert(initialBalanceBridgeERC20Token == finalBalanceBridgeERC20Token - (amount - feesPaid));
        vm.stopPrank();
    }

    function testEmitsWhenERC20TokensSent() public registerTokenBridge fundBridgerAccount {
        erc20Token.approve(address(tokenBridgeRouter), amount);

        vm.expectEmit(true, true, false, false, address(tokenBridgeRouter));
        emit BridgeERC20(
            address(erc20Token),
            destinationChainID,
            bridger,
            amount,
            (amount * primaryRelayerFeeBips) / 10_000,
            0
        );
        tokenBridgeRouter.bridgeERC20(
            address(erc20Token), destinationChainID, amount, bridger, multihopFallBackAddress
        );
        vm.stopPrank();
    }

    function testBalancesWhenERC20TokensSentViaBridgeAndCall()
        public
        registerTokenBridge
        fundBridgerAccount
    {
        uint256 initialBalanceBridgerERC20Token = erc20Token.balanceOf(bridger);
        uint256 initialBalanceBridgeERC20Token = erc20Token.balanceOf(address(erc20TokenSource));
        bytes memory payload = abi.encode("abcdefghijklmnopqrstuvwxyz");

        erc20Token.approve(address(tokenBridgeRouter), amount);

        tokenBridgeRouter.bridgeAndCallERC20(
            address(erc20Token),
            destinationChainID,
            amount,
            tokenDestination,
            payload,
            bridger,
            recipientGasLimit,
            multihopFallBackAddress
        );

        uint256 feesPaid = (amount * primaryRelayerFeeBips) / 10_000;

        uint256 finalBalanceBridgerERC20Token = erc20Token.balanceOf(bridger);
        uint256 finalBalanceBridgeERC20Token = erc20Token.balanceOf(address(erc20TokenSource));

        assert(initialBalanceBridgerERC20Token == finalBalanceBridgerERC20Token + amount);
        assert(initialBalanceBridgeERC20Token == finalBalanceBridgeERC20Token - (amount - feesPaid));
        vm.stopPrank();
    }

    function testEmitsWhenERC20TokensSentViaBridgeAndCall()
        public
        registerTokenBridge
        fundBridgerAccount
    {
        bytes memory payload = abi.encode("abcdefghijklmnopqrstuvwxyz");

        erc20Token.approve(address(tokenBridgeRouter), amount);

        vm.expectEmit(true, true, false, false, address(tokenBridgeRouter));
        emit BridgeAndCallERC20(
            address(erc20Token),
            destinationChainID,
            tokenDestination,
            amount,
            (amount * primaryRelayerFeeBips) / 10_000,
            0
        );
        tokenBridgeRouter.bridgeAndCallERC20(
            address(erc20Token),
            destinationChainID,
            amount,
            tokenDestination,
            payload,
            bridger,
            recipientGasLimit,
            multihopFallBackAddress
        );
        vm.stopPrank();
    }
}

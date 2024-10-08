// SPDX-License-Identifier: UNLICENSED
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {AvalancheICTTRouterFixedFees} from
    "../../../src/contracts/Teleporter/AvalancheICTTRouterFixedFees.sol";
import {WarpMessengerTestMock} from "../../../src/contracts/mocks/WarpMessengerTestMock.sol";
import {IAvalancheICTTRouter} from "../../../src/interfaces/IAvalancheICTTRouter.sol";
import {HelperConfig4Test} from "../HelperConfig4Test.t.sol";
import {ERC20TokenHome} from "@avalabs/avalanche-ictt/TokenHome/ERC20TokenHome.sol";
import {ERC20Mock} from "@openzeppelin/contracts@4.8.1/mocks/ERC20Mock.sol";
import {SafeMath} from "@openzeppelin/contracts@4.8.1/utils/math/SafeMath.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract AvalancheICTTRouterErc20Test is Test {
    address private constant TOKEN_SOURCE = 0x6D411e0A54382eD43F02410Ce1c7a7c122afA6E1;

    event UpdateRelayerFees(uint256 primaryRelayerFee, uint256 secondaryRelayerFee);

    event BridgeERC20(
        address indexed tokenAddress,
        bytes32 indexed destinationBlockchainID,
        uint256 amount,
        address recipient
    );

    event BridgeContractERC20(
        address indexed tokenAddress,
        bytes32 indexed destinationBlockchainID,
        uint256 amount,
        address recipient
    );

    HelperConfig4Test helperConfig = new HelperConfig4Test(TOKEN_SOURCE, 1);
    AvalancheICTTRouterFixedFees tokenBridgeRouter;
    uint256 deployerKey;
    uint256 primaryRelayerFeeBips;
    uint256 secondaryRelayerFeeBips;
    ERC20Mock erc20Token;
    ERC20TokenHome tokenSource;
    address tokenDestination;
    bytes32 sourceChainID;
    bytes32 destinationChainID;
    address owner;
    address bridger;
    bytes32 messageId;
    address warpPrecompileAddress;
    uint256 requiredGasLimit = 10_000_000;
    WarpMessengerTestMock warpMessengerTestMock;

    uint256 constant STARTING_GAS_BALANCE = 10 ether;

    function setUp() external {
        (
            deployerKey,
            primaryRelayerFeeBips,
            secondaryRelayerFeeBips,
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
            warpPrecompileAddress,
            warpMessengerTestMock
        ) = helperConfig.activeNetworkConfigTest();
        vm.deal(bridger, STARTING_GAS_BALANCE);

        vm.etch(warpPrecompileAddress, address(warpMessengerTestMock).code);
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

    modifier fundBridgerAccount() {
        vm.startPrank(bridger);
        erc20Token.mint(bridger, 10 ether);
        vm.stopPrank();
        _;
    }

    function testSetRelayerFee() public {
        vm.startPrank(owner);
        (uint256 primaryRelayerFeeStart, uint256 secondaryRelayerFeeStart) =
            tokenBridgeRouter.getRelayerFeesBips();
        uint256 primaryRelayerFeeValue = 50;
        uint256 secondaryRelayerFeeValue = 20;
        tokenBridgeRouter.updateRelayerFeesBips(primaryRelayerFeeValue, secondaryRelayerFeeValue);
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
        emit UpdateRelayerFees(primaryRelayerFeeValue, secondaryRelayerFeeValue);
        tokenBridgeRouter.updateRelayerFeesBips(primaryRelayerFeeValue, secondaryRelayerFeeValue);
        vm.stopPrank();
    }

    function testBalanceBridgerWhenSendERC20Tokens()
        public
        registerTokenBridge
        fundBridgerAccount
    {
        vm.startPrank(bridger);
        uint256 balanceStart = erc20Token.balanceOf(bridger);

        uint256 amount = 1 ether;
        erc20Token.approve(address(tokenBridgeRouter), amount);
        tokenBridgeRouter.bridgeERC20(
            address(erc20Token), destinationChainID, amount, bridger, address(0)
        );

        uint256 balanceEnd = erc20Token.balanceOf(bridger);
        assert(balanceStart == balanceEnd + amount);
        vm.stopPrank();
    }

    function testBalanceBridgeWhenSendERC20Tokens() public registerTokenBridge fundBridgerAccount {
        vm.startPrank(bridger);
        uint256 balanceStart = erc20Token.balanceOf(address(tokenSource));
        assert(balanceStart == 0);

        uint256 amount = 1 ether;
        erc20Token.approve(address(tokenBridgeRouter), amount);
        tokenBridgeRouter.bridgeERC20(
            address(erc20Token), destinationChainID, amount, bridger, address(0)
        );

        uint256 feeAmount = SafeMath.div(SafeMath.mul(amount, primaryRelayerFeeBips), 10_000);
        uint256 balanceEnd = erc20Token.balanceOf(address(tokenSource));
        assert(balanceEnd == amount - feeAmount);
        vm.stopPrank();
    }

    function testEmitsOnCallOfBridgeERC20Function() public registerTokenBridge fundBridgerAccount {
        vm.startPrank(bridger);
        uint256 amount = 1 ether;
        erc20Token.approve(address(tokenBridgeRouter), amount);

        vm.expectEmit(true, true, false, false, address(tokenBridgeRouter));
        emit BridgeERC20(address(erc20Token), destinationChainID, amount, bridger);
        tokenBridgeRouter.bridgeERC20(
            address(erc20Token), destinationChainID, amount, bridger, address(0)
        );

        vm.stopPrank();
    }

    function testBalanceBridgerWhenSendAndCallERC20Tokens()
        public
        registerTokenBridge
        fundBridgerAccount
    {
        vm.startPrank(bridger);
        uint256 balanceStart = erc20Token.balanceOf(bridger);
        uint256 amount = 1 ether;
        erc20Token.approve(address(tokenBridgeRouter), amount);

        bytes memory payload = abi.encode("abcdefghijklmnopqrstuvwxyz");

        tokenBridgeRouter.bridgeContractERC20(
            address(erc20Token),
            destinationChainID,
            amount,
            tokenDestination,
            payload,
            bridger,
            100_000,
            requiredGasLimit,
            address(0)
        );

        uint256 balanceEnd = erc20Token.balanceOf(bridger);
        assert(balanceStart == balanceEnd + amount);

        vm.stopPrank();
    }

    function testBalanceBridgeWhenSendAndCallERC20Tokens()
        public
        registerTokenBridge
        fundBridgerAccount
    {
        vm.startPrank(bridger);
        uint256 balanceStart = erc20Token.balanceOf(address(tokenSource));
        assert(balanceStart == 0);
        uint256 amount = 1 ether;
        erc20Token.approve(address(tokenBridgeRouter), amount);

        bytes memory payload = abi.encode("abcdefghijklmnopqrstuvwxyz");

        tokenBridgeRouter.bridgeContractERC20(
            address(erc20Token),
            destinationChainID,
            amount,
            tokenDestination,
            payload,
            bridger,
            100_000,
            requiredGasLimit,
            address(0)
        );

        uint256 feeAmount = SafeMath.div(SafeMath.mul(amount, primaryRelayerFeeBips), 10_000);
        uint256 balanceEnd = erc20Token.balanceOf(address(tokenSource));
        assert(balanceEnd == amount - feeAmount);

        vm.stopPrank();
    }

    function testEmitsOnCallOfBridgeContractERC20Function()
        public
        registerTokenBridge
        fundBridgerAccount
    {
        vm.startPrank(bridger);
        uint256 amount = 1 ether;
        bytes memory payload = abi.encode("abcdefghijklmnopqrstuvwxyz");
        erc20Token.approve(address(tokenBridgeRouter), amount);

        vm.expectEmit(true, true, false, false, address(tokenBridgeRouter));
        emit BridgeContractERC20(address(erc20Token), destinationChainID, amount, tokenDestination);
        tokenBridgeRouter.bridgeContractERC20(
            address(erc20Token),
            destinationChainID,
            amount,
            tokenDestination,
            payload,
            bridger,
            100_000,
            requiredGasLimit,
            address(0)
        );

        vm.stopPrank();
    }
}

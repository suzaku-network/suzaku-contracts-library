// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {AvalancheICTTRouter} from "../../src/contracts/Teleporter/AvalancheICTTRouter.sol";
import {WarpMessengerTestMock} from "../../src/mocks/WarpMessengerTestMock.sol";
import {HelperConfig4Test} from "./HelperConfig4Test.t.sol";
import {NativeTokenHome} from "@avalabs/avalanche-ictt/TokenHome/NativeTokenHome.sol";
import {WrappedNativeToken} from "@avalabs/avalanche-ictt/WrappedNativeToken.sol";
import {ERC20Mock} from "@openzeppelin/contracts@4.8.1/mocks/ERC20Mock.sol";
import {SafeMath} from "@openzeppelin/contracts@4.8.1/utils/math/SafeMath.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract AvalancheICTTRouterNativeTokenTest is Test {
    address private constant TOKEN_HOME = 0x5CF7F96627F3C9903763d128A1cc5D97556A6b99;

    event BridgeNative(bytes32 indexed destinationChainID, uint256 amount, address recipient);

    HelperConfig4Test helperConfig = new HelperConfig4Test(TOKEN_HOME);
    uint256 deployerKey;
    uint256 primaryRelayerFeeBips;
    uint256 secondaryRelayerFeeBips;
    ERC20Mock erc20Token = ERC20Mock(address(0));
    WrappedNativeToken wrappedToken;
    NativeTokenHome tokenHome;
    address tokenRemote;
    AvalancheICTTRouter tokenBridgeRouter;
    bytes32 homeChainID;
    bytes32 remoteChainID;
    address owner;
    address bridger;
    address warpPrecompileAddress;
    WarpMessengerTestMock warpMessengerTestMock;
    uint256 requiredGasLimit = 10_000_000;

    uint256 constant STARTING_GAS_BALANCE = 10 ether;

    function setUp() external {
        (
            deployerKey,
            primaryRelayerFeeBips,
            secondaryRelayerFeeBips,
            ,
            wrappedToken,
            ,
            tokenHome,
            tokenRemote,
            tokenBridgeRouter,
            homeChainID,
            remoteChainID,
            owner,
            bridger,
            ,
            warpPrecompileAddress,
            warpMessengerTestMock
        ) = helperConfig.activeNetworkConfigTest();
        vm.deal(bridger, STARTING_GAS_BALANCE);

        vm.etch(warpPrecompileAddress, address(warpMessengerTestMock).code);
    }

    modifier registerTokenBridge() {
        vm.startPrank(owner);
        tokenBridgeRouter.registerHomeTokenBridge(address(erc20Token), address(tokenHome));
        tokenBridgeRouter.registerRemoteTokenBridge(
            address(erc20Token), remoteChainID, tokenRemote, requiredGasLimit, false
        );
        vm.stopPrank();
        _;
    }

    function testBalanceBridgerWhenSendNativeTokens() public registerTokenBridge {
        vm.startPrank(bridger);
        uint256 balanceStart = bridger.balance;

        uint256 amount = 1 ether;
        tokenBridgeRouter.bridgeNative{value: amount}(
            remoteChainID, bridger, address(wrappedToken), address(0)
        );

        uint256 balanceEnd = bridger.balance;
        assert(balanceStart == balanceEnd + amount);
        vm.stopPrank();
    }

    function testBalanceBridgeWhenSendNativeTokens() public registerTokenBridge {
        vm.startPrank(bridger);
        uint256 balanceStart = wrappedToken.balanceOf(address(tokenHome));
        assert(balanceStart == 0);

        uint256 amount = 1 ether;
        tokenBridgeRouter.bridgeNative{value: amount}(
            remoteChainID, bridger, address(wrappedToken), address(0)
        );

        uint256 feeAmount = SafeMath.div(SafeMath.mul(amount, primaryRelayerFeeBips), 10_000);

        uint256 balanceEnd = wrappedToken.balanceOf(address(tokenHome));
        assert(balanceEnd == amount - feeAmount);
        vm.stopPrank();
    }

    function testEmitsOnSendNativeTokens() public registerTokenBridge {
        vm.startPrank(bridger);
        vm.expectEmit(true, false, false, false, address(tokenBridgeRouter));
        emit BridgeNative(remoteChainID, 1 ether, bridger);

        tokenBridgeRouter.bridgeNative{value: 1 ether}(
            remoteChainID, bridger, address(wrappedToken), address(0)
        );
        vm.stopPrank();
    }
}

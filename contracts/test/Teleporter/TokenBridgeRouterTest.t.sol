// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {TokenBridgeRouter} from "../../src/Teleporter/TokenBridgeRouter.sol";
import {RemoteBridge} from "../../src/Teleporter/TokenBridgeRouter.sol";
import {HelperConfig4Test} from "./HelperConfig4Test.t.sol";
import {ERC20TokenHome} from "@avalabs/avalanche-ictt/TokenHome/ERC20TokenHome.sol";
import {WrappedNativeToken} from "@avalabs/avalanche-ictt/WrappedNativeToken.sol";
import {ERC20Mock} from "@openzeppelin/contracts@4.8.1/mocks/ERC20Mock.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract TokenBridgeRouterTest is Test {
    event ChangeRelayerFees(uint256 primaryRelayerFee, uint256 secondaryRelayerFee);
    event RegisterHomeTokenBridge(address indexed tokenAddress, address indexed bridgeAddress);
    event RegisterRemoteTokenBridge(
        address indexed tokenAddress,
        RemoteBridge indexed remoteBridge,
        bytes32 indexed remoteChainID
    );
    event RemoveHomeTokenBridge(address indexed tokenAddress);
    event RemoveRemoteTokenBridge(address indexed tokenAddress, bytes32 indexed remoteChainID);

    HelperConfig4Test helperConfig = new HelperConfig4Test(address(0));
    TokenBridgeRouter tokenBridgeRouter;
    uint256 deployerKey;
    ERC20Mock erc20Token;
    ERC20TokenHome tokenHome;
    address tokenRemote;
    bytes32 homeChainID;
    bytes32 remoteChainID;
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
            tokenHome,
            ,
            tokenRemote,
            tokenBridgeRouter,
            homeChainID,
            remoteChainID,
            owner,
            bridger,
            messageId,
            ,
        ) = helperConfig.activeNetworkConfigTest();
        vm.deal(bridger, STARTING_GAS_BALANCE);
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

    function testSetRelayerFee() public {
        vm.startPrank(owner);
        (uint256 primaryRelayerFeeStart, uint256 secondaryRelayerFeeStart) =
            tokenBridgeRouter.getRelayerFeeBips();
        uint256 primaryRelayerFeeValue = 50;
        uint256 secondaryRelayerFeeValue = 20;
        tokenBridgeRouter.setRelayerFeesBips(primaryRelayerFeeValue, secondaryRelayerFeeValue);
        (uint256 primaryRelayerFeeEnd, uint256 secondaryRelayerFeeEnd) =
            tokenBridgeRouter.getRelayerFeeBips();
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

    function testEmitsOnRegisterHomeTokenBridge() public {
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, false, address(tokenBridgeRouter));
        emit RegisterHomeTokenBridge(address(erc20Token), address(tokenHome));
        tokenBridgeRouter.registerHomeTokenBridge(address(erc20Token), address(tokenHome));
        vm.stopPrank();
    }

    function testEmitsOnRegisterRemoteTokenBridge() public {
        vm.startPrank(owner);
        RemoteBridge memory remoteBridge = RemoteBridge(tokenRemote, requiredGasLimit, false);
        vm.expectEmit(true, true, true, false, address(tokenBridgeRouter));
        emit RegisterRemoteTokenBridge(address(erc20Token), remoteBridge, remoteChainID);
        tokenBridgeRouter.registerRemoteTokenBridge(
            address(erc20Token), remoteChainID, tokenRemote, requiredGasLimit, false
        );
        vm.stopPrank();
    }

    function testGetHomeBridgeAfterRegister() public registerTokenBridge {
        assert(tokenBridgeRouter.getHomeBridge(address(erc20Token)) == address(tokenHome));
    }

    function testGetRemoteBridgeConfigAfterRegister() public registerTokenBridge {
        RemoteBridge memory remoteBridge =
            tokenBridgeRouter.getRemoteBridge(remoteChainID, address(erc20Token));
        assert(
            remoteBridge.bridgeAddress == tokenRemote
                && remoteBridge.requiredGasLimit == requiredGasLimit
        );
    }

    function testEmitsOnRemoveHomeTokenBridge() public {
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, false, address(tokenBridgeRouter));
        emit RemoveHomeTokenBridge(address(erc20Token));
        tokenBridgeRouter.removeHomeTokenBridge(address(erc20Token));
        vm.stopPrank();
    }

    function testEmitsOnRemoveRemoteTokenBridge() public {
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, false, address(tokenBridgeRouter));
        emit RemoveRemoteTokenBridge(address(erc20Token), remoteChainID);
        tokenBridgeRouter.removeRemoteTokenBridge(address(erc20Token), remoteChainID);
        vm.stopPrank();
    }
}

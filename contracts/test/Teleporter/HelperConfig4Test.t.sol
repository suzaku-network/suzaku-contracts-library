// SPDX-License-Identifier: UNLICENSED
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {AvalancheICTTRouter} from "../../src/contracts/Teleporter/AvalancheICTTRouter.sol";
import {AvalancheICTTRouterFixedFees} from
    "../../src/contracts/Teleporter/AvalancheICTTRouterFixedFees.sol";
import {WarpMessengerTestMock} from "../../src/contracts/mocks/WarpMessengerTestMock.sol";
import {ERC20TokenHome} from "@avalabs/avalanche-ictt/TokenHome/ERC20TokenHome.sol";
import {NativeTokenHome} from "@avalabs/avalanche-ictt/TokenHome/NativeTokenHome.sol";
import {WrappedNativeToken} from "@avalabs/avalanche-ictt/WrappedNativeToken.sol";
import {ERC20Mock} from "@openzeppelin/contracts@4.8.1/mocks/ERC20Mock.sol";
import {TeleporterMessenger} from "@teleporter/TeleporterMessenger.sol";
import {
    ProtocolRegistryEntry, TeleporterRegistry
} from "@teleporter/upgrades/TeleporterRegistry.sol";
import {Script, console} from "forge-std/Script.sol";

contract HelperConfig4Test is Script {
    address private constant TELEPORTER_MESSENGER_ADDRESS =
        0xF2E246BB76DF876Cef8b38ae84130F4F55De395b;
    bytes32 private constant ANVIL_CHAIN_HEX =
        0x7a69000000000000000000000000000000000000000000000000000000000000;
    bytes32 private constant DEST_CHAIN_HEX =
        0x1000000000000000000000000000000000000000000000000000000000000000;
    bytes32 private constant MESSAGE_ID =
        0x39fa07214dc7ff1d2f8b6dfe6cd26f6b138ee9d40d013724382a5c539c8641e2;
    address private constant WARP_PRECOMPILE = 0x0200000000000000000000000000000000000005;
    uint256 private constant DEPLOYER_PRIV_KEY = 1;

    struct NetworkConfigTest {
        uint256 deployerKey;
        uint256 primaryRelayerFeeBips;
        uint256 secondaryRelayerFeeBips;
        ERC20Mock erc20Token;
        WrappedNativeToken wrappedToken;
        ERC20TokenHome erc20TokenSource;
        NativeTokenHome nativeTokenSource;
        address tokenRemote;
        AvalancheICTTRouter tokenBridgeRouterF;
        AvalancheICTTRouterFixedFees tokenBridgeRouterS;
        bytes32 sourceChainID;
        bytes32 remoteChainID;
        address owner;
        address bridger;
        bytes32 messageID;
        address warpPrecompileAddress;
        WarpMessengerTestMock warpMessengerTestMock;
    }

    uint256 private _deployerKey = DEPLOYER_PRIV_KEY;
    address private _tokenRemote = makeAddr("bridgeremote");
    bytes32 private _sourceChainID = ANVIL_CHAIN_HEX;
    bytes32 private _remoteChainID = DEST_CHAIN_HEX;
    address private _owner = vm.addr(DEPLOYER_PRIV_KEY);
    address private _bridger = makeAddr("bridger");
    bytes32 private _messageID = MESSAGE_ID;
    address private _warpPrecompileAddress = WARP_PRECOMPILE;
    uint256 private _primaryRelayerFeeBips = 20;
    uint256 private _secondaryRelayerFeeBips = 0;
    uint256 private _initialReserveImbalance = 0;
    uint8 private _sourceTokenDecimals = 18;
    uint8 private _remoteTokenDecimals = 18;
    uint256 private _requiredGasLimit = 10_000_000;

    NetworkConfigTest public activeNetworkConfigTest;

    ProtocolRegistryEntry[] protocolRegistryEntry;

    constructor(address _tokenSource, uint256 _routerType) {
        if (_routerType == 0) {
            activeNetworkConfigTest = getNetworkConfigWoFees(_tokenSource);
        } else {
            activeNetworkConfigTest = getNetworkConfigWFees(_tokenSource);
        }
    }

    function getNetworkConfigWoFees(
        address _tokenSource
    ) public returns (NetworkConfigTest memory) {
        WarpMessengerTestMock warpMessengerTestMock = new WarpMessengerTestMock(
            _sourceChainID,
            _remoteChainID,
            _messageID,
            _initialReserveImbalance,
            _sourceTokenDecimals,
            _remoteTokenDecimals,
            TELEPORTER_MESSENGER_ADDRESS,
            _tokenSource,
            _tokenRemote,
            _requiredGasLimit
        );
        vm.etch(_warpPrecompileAddress, address(warpMessengerTestMock).code);

        vm.startBroadcast(_deployerKey);
        TeleporterMessenger teleporterMessenger = new TeleporterMessenger();
        protocolRegistryEntry.push(ProtocolRegistryEntry(1, address(teleporterMessenger)));
        TeleporterRegistry teleporterRegistry = new TeleporterRegistry(protocolRegistryEntry);

        ERC20Mock _erc20Token = new ERC20Mock("ERC20Mock", "ERC20M", makeAddr("mockRecipient"), 0);
        WrappedNativeToken _wrappedToken = new WrappedNativeToken("WNTT");

        AvalancheICTTRouter _tokenBridgeRouterF = new AvalancheICTTRouter();

        ERC20TokenHome _erc20TokenSource =
            new ERC20TokenHome(address(teleporterRegistry), _owner, address(_erc20Token), 18);
        NativeTokenHome _nativeTokenSource =
            new NativeTokenHome(address(teleporterRegistry), _owner, address(_wrappedToken));
        vm.stopBroadcast();
        teleporterMessenger.receiveCrossChainMessage(1, address(0));

        return NetworkConfigTest({
            deployerKey: _deployerKey,
            primaryRelayerFeeBips: _primaryRelayerFeeBips,
            secondaryRelayerFeeBips: _secondaryRelayerFeeBips,
            erc20Token: _erc20Token,
            wrappedToken: _wrappedToken,
            erc20TokenSource: _erc20TokenSource,
            nativeTokenSource: _nativeTokenSource,
            tokenRemote: _tokenRemote,
            tokenBridgeRouterF: _tokenBridgeRouterF,
            tokenBridgeRouterS: AvalancheICTTRouterFixedFees(address(0)),
            sourceChainID: _sourceChainID,
            remoteChainID: _remoteChainID,
            owner: _owner,
            bridger: _bridger,
            messageID: _messageID,
            warpPrecompileAddress: _warpPrecompileAddress,
            warpMessengerTestMock: warpMessengerTestMock
        });
    }

    function getNetworkConfigWFees(
        address _tokenSource
    ) public returns (NetworkConfigTest memory) {
        WarpMessengerTestMock warpMessengerTestMock = new WarpMessengerTestMock(
            _sourceChainID,
            _remoteChainID,
            _messageID,
            _initialReserveImbalance,
            _sourceTokenDecimals,
            _remoteTokenDecimals,
            TELEPORTER_MESSENGER_ADDRESS,
            _tokenSource,
            _tokenRemote,
            _requiredGasLimit
        );
        vm.etch(_warpPrecompileAddress, address(warpMessengerTestMock).code);

        vm.startBroadcast(_deployerKey);
        TeleporterMessenger teleporterMessenger = new TeleporterMessenger();
        protocolRegistryEntry.push(ProtocolRegistryEntry(1, address(teleporterMessenger)));
        TeleporterRegistry teleporterRegistry = new TeleporterRegistry(protocolRegistryEntry);

        ERC20Mock _erc20Token = new ERC20Mock("ERC20Mock", "ERC20M", makeAddr("mockRecipient"), 0);
        WrappedNativeToken _wrappedToken = new WrappedNativeToken("WNTT"); // WNTT for Wrapped Native Token Test

        AvalancheICTTRouterFixedFees _tokenBridgeRouterS =
            new AvalancheICTTRouterFixedFees(_primaryRelayerFeeBips, _secondaryRelayerFeeBips);

        ERC20TokenHome _erc20TokenSource =
            new ERC20TokenHome(address(teleporterRegistry), _owner, address(_erc20Token), 18);
        NativeTokenHome _nativeTokenSource =
            new NativeTokenHome(address(teleporterRegistry), _owner, address(_wrappedToken));
        vm.stopBroadcast();
        teleporterMessenger.receiveCrossChainMessage(1, address(0));

        return NetworkConfigTest({
            deployerKey: _deployerKey,
            primaryRelayerFeeBips: _primaryRelayerFeeBips,
            secondaryRelayerFeeBips: _secondaryRelayerFeeBips,
            erc20Token: _erc20Token,
            wrappedToken: _wrappedToken,
            erc20TokenSource: _erc20TokenSource,
            nativeTokenSource: _nativeTokenSource,
            tokenRemote: _tokenRemote,
            tokenBridgeRouterF: AvalancheICTTRouter(address(0)),
            tokenBridgeRouterS: _tokenBridgeRouterS,
            sourceChainID: _sourceChainID,
            remoteChainID: _remoteChainID,
            owner: _owner,
            bridger: _bridger,
            messageID: _messageID,
            warpPrecompileAddress: _warpPrecompileAddress,
            warpMessengerTestMock: warpMessengerTestMock
        });
    }
}

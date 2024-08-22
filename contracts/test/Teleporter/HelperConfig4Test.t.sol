// (c) 2024, ADDPHO All rights reserved.
// See the file LICENSE_MIT for licensing terms.

// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {AvalancheICTTRouter} from "../../src/contracts/Teleporter/AvalancheICTTRouter.sol";
import {WarpMessengerTestMock} from "../../src/mocks/WarpMessengerTestMock.sol";
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
    bytes32 private constant ANVIL_CHAIN_HEX =
        0x7a69000000000000000000000000000000000000000000000000000000000000;
    bytes32 private constant DEST_CHAIN_HEX =
        0x1000000000000000000000000000000000000000000000000000000000000000;
    bytes32 private constant MESSAGE_ID =
        0x39fa07214dc7ff1d2f8b6dfe6cd26f6b138ee9d40d013724382a5c539c8641e2;
    address private constant WARP_PRECOMPILE = 0x0200000000000000000000000000000000000005;
    uint256 private constant DEPLOYER_PRIV_KEY = 1;
    uint256 private constant PRIMARY_RELAYER_FEE_BIPS = 20;
    uint256 private constant SECONDARY_RELAYER_FEE_BIPS = 0;

    struct NetworkConfigTest {
        uint256 deployerKey;
        uint256 primaryRelayerFeeBips;
        uint256 secondaryRelayerFeeBips;
        ERC20Mock erc20Token;
        WrappedNativeToken wrappedToken;
        ERC20TokenHome erc20TokenHome;
        NativeTokenHome nativeTokenHome;
        address tokenRemote;
        AvalancheICTTRouter tokenBridgeRouter;
        bytes32 homeChainID;
        bytes32 remoteChainID;
        address owner;
        address bridger;
        bytes32 messageID;
        address warpPrecompileAddress;
        WarpMessengerTestMock warpMessengerTestMock;
    }

    uint256 private _deployerKey = DEPLOYER_PRIV_KEY;
    address private _tokenRemote = makeAddr("bridgeRemote");
    address private _owner = vm.addr(DEPLOYER_PRIV_KEY);
    address private _bridger = makeAddr("bridger");
    address private _warpPrecompileAddress = WARP_PRECOMPILE;

    NetworkConfigTest public activeNetworkConfigTest;

    ProtocolRegistryEntry[] protocolRegistryEntry;

    constructor(address _tokenHome) {
        activeNetworkConfigTest = getNetworkConfig(_tokenHome);
    }

    function getNetworkConfig(address _tokenHome) public returns (NetworkConfigTest memory) {
        WarpMessengerTestMock warpMessengerTestMock =
            new WarpMessengerTestMock(_tokenHome, _tokenRemote);
        vm.etch(_warpPrecompileAddress, address(warpMessengerTestMock).code);

        vm.startBroadcast(_deployerKey);
        TeleporterMessenger teleporterMessenger = new TeleporterMessenger();
        protocolRegistryEntry.push(ProtocolRegistryEntry(1, address(teleporterMessenger)));
        TeleporterRegistry teleporterRegistry = new TeleporterRegistry(protocolRegistryEntry);

        ERC20Mock _erc20Token = new ERC20Mock("ERC20Mock", "ERC20M", makeAddr("mockRecipient"), 0);
        WrappedNativeToken _wrappedToken = new WrappedNativeToken("WNTT"); // WNTT for Wrapped Native Token Test

        AvalancheICTTRouter _tokenBridgeRouter =
            new AvalancheICTTRouter(PRIMARY_RELAYER_FEE_BIPS, SECONDARY_RELAYER_FEE_BIPS);

        ERC20TokenHome _erc20TokenHome =
            new ERC20TokenHome(address(teleporterRegistry), _owner, address(_erc20Token), 18);
        NativeTokenHome _nativeTokenHome =
            new NativeTokenHome(address(teleporterRegistry), _owner, address(_wrappedToken));
        vm.stopBroadcast();
        teleporterMessenger.receiveCrossChainMessage(1, address(0));

        return NetworkConfigTest({
            deployerKey: _deployerKey,
            primaryRelayerFeeBips: PRIMARY_RELAYER_FEE_BIPS,
            secondaryRelayerFeeBips: SECONDARY_RELAYER_FEE_BIPS,
            erc20Token: _erc20Token,
            wrappedToken: _wrappedToken,
            erc20TokenHome: _erc20TokenHome,
            nativeTokenHome: _nativeTokenHome,
            tokenRemote: _tokenRemote,
            tokenBridgeRouter: _tokenBridgeRouter,
            homeChainID: ANVIL_CHAIN_HEX,
            remoteChainID: DEST_CHAIN_HEX,
            owner: _owner,
            bridger: _bridger,
            messageID: MESSAGE_ID,
            warpPrecompileAddress: _warpPrecompileAddress,
            warpMessengerTestMock: warpMessengerTestMock
        });
    }
}

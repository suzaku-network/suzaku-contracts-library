// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {WarpMessengerMock} from "../../../src/contracts/mocks/WarpMessengerMock.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

import {NativeTokenRemote} from "@avalabs/icm-contracts/ictt/TokenRemote/NativeTokenRemote.sol";
import {TokenRemoteSettings} from
    "@avalabs/icm-contracts/ictt/TokenRemote/interfaces/ITokenRemote.sol";
import {TeleporterFeeInfo} from "@avalabs/icm-contracts/teleporter/ITeleporterMessenger.sol";
import {Script, console} from "forge-std/Script.sol";

contract DeployNativeTokenRemote is Script {
    uint256 private constant MIN_TELEPORTER_VERSION = 1;

    function run() external returns (NativeTokenRemote) {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint256 deployerKey,
            address warpPrecompileAddress,
            address teleporterManager,
            ,
            ,
            ,
            ,
            string memory nativeAssetSymbol,
            uint256 initialReserveImbalance,
            uint256 burnedFeesReportingRewardPercentage,
            ,
            ,
            ,
            bytes32 tokenHomeBlockchainID,
            uint8 tokenHomeTokenDecimals,
            address tokenHomeAddress,
            address teleporterRegistryAddress,
            ,
            WarpMessengerMock mock
        ) = helperConfig.activeNetworkConfig();

        vm.etch(warpPrecompileAddress, address(mock).code);

        TokenRemoteSettings memory settings = TokenRemoteSettings({
            teleporterRegistryAddress: teleporterRegistryAddress,
            teleporterManager: teleporterManager,
            minTeleporterVersion: MIN_TELEPORTER_VERSION,
            tokenHomeBlockchainID: tokenHomeBlockchainID,
            tokenHomeAddress: tokenHomeAddress,
            tokenHomeDecimals: tokenHomeTokenDecimals
        });

        vm.startBroadcast(deployerKey);
        NativeTokenRemote nativeTokenRemote = deployBridgeInstance(
            settings,
            nativeAssetSymbol,
            initialReserveImbalance,
            burnedFeesReportingRewardPercentage
        );

        registerRemoteInstance(nativeTokenRemote);
        vm.stopBroadcast();

        return nativeTokenRemote;
    }

    function deployBridgeInstance(
        TokenRemoteSettings memory settings,
        string memory nativeAssetSymbol,
        uint256 initialReserveImbalance,
        uint256 burnedFeesReportingRewardPercentage
    ) public returns (NativeTokenRemote) {
        NativeTokenRemote nativeTokenRemote = new NativeTokenRemote(
            settings,
            nativeAssetSymbol,
            initialReserveImbalance,
            burnedFeesReportingRewardPercentage
        );

        return nativeTokenRemote;
    }

    function registerRemoteInstance(
        NativeTokenRemote tokenRemoteBridge
    ) public {
        TeleporterFeeInfo memory feeInfo =
            TeleporterFeeInfo({feeTokenAddress: address(tokenRemoteBridge), amount: 0});
        tokenRemoteBridge.approve(address(tokenRemoteBridge), 10 ether);
        tokenRemoteBridge.registerWithHome(feeInfo);
    }
}

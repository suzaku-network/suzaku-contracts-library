// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {WarpMessengerMock} from "../../../src/contracts/mocks/WarpMessengerMock.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

import {ERC20TokenRemote} from "@avalabs/icm-contracts/ictt/TokenRemote/ERC20TokenRemote.sol";
import {TokenRemoteSettings} from
    "@avalabs/icm-contracts/ictt/TokenRemote/interfaces/ITokenRemote.sol";
import {TeleporterFeeInfo} from "@avalabs/icm-contracts/teleporter/ITeleporterMessenger.sol";
import {IWarpMessenger} from
    "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {Script, console} from "forge-std/Script.sol";

contract DeployERC20TokenRemote is Script {
    uint256 private minTeleporterVersion = vm.envUint("MIN_TELEPORTER_VERSION");

    function run() external returns (ERC20TokenRemote) {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint256 deployerKey,
            address teleporterManager,
            ,
            ,
            string memory tokenName,
            string memory tokenSymbol,
            ,
            ,
            ,
            ,
            ,
            ,
            bytes32 tokenHomeBlockchainID,
            uint8 tokenHomeTokenDecimals,
            address tokenHomeAddress,
            address teleporterRegistryAddress,
            uint8 tokenDecimals
        ) = helperConfig.activeNetworkConfig();

        TokenRemoteSettings memory settings = TokenRemoteSettings({
            teleporterRegistryAddress: teleporterRegistryAddress,
            teleporterManager: teleporterManager,
            minTeleporterVersion: minTeleporterVersion,
            tokenHomeBlockchainID: tokenHomeBlockchainID,
            tokenHomeAddress: tokenHomeAddress,
            tokenHomeDecimals: tokenHomeTokenDecimals
        });

        vm.startBroadcast(deployerKey);

        ERC20TokenRemote erc20TokenRemote =
            deployBridgeInstance(settings, tokenName, tokenSymbol, tokenDecimals);

        registerRemoteInstance(erc20TokenRemote);

        vm.stopBroadcast();

        return erc20TokenRemote;
    }

    function deployBridgeInstance(
        TokenRemoteSettings memory settings,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 tokenDecimals
    ) public returns (ERC20TokenRemote) {
        ERC20TokenRemote erc20TokenRemote =
            new ERC20TokenRemote(settings, tokenName, tokenSymbol, tokenDecimals);

        return erc20TokenRemote;
    }

    function registerRemoteInstance(
        ERC20TokenRemote tokenRemoteBridge
    ) public {
        TeleporterFeeInfo memory feeInfo =
            TeleporterFeeInfo({feeTokenAddress: address(tokenRemoteBridge), amount: 0});
        tokenRemoteBridge.approve(address(tokenRemoteBridge), 10 ether);
        tokenRemoteBridge.registerWithHome(feeInfo);
    }
}

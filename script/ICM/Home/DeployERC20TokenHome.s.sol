// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {WarpMessengerMock} from "../../../src/contracts/mocks/WarpMessengerMock.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

import {ERC20TokenHome} from "@avalabs/icm-contracts/ictt/TokenHome/ERC20TokenHome.sol";
import {Script, console} from "forge-std/Script.sol";

contract DeployERC20TokenHome is Script {
    uint256 private constant MIN_TELEPORTER_VERSION = 1;

    function run() external returns (ERC20TokenHome) {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint256 deployerKey,
            address warpPrecompileAddress,
            address teleporterManager,
            address tokenAddress,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            address teleporterRegistryAddress,
            ,
            uint8 tokenDecimals,
            ,
            ,
            ,
            WarpMessengerMock mock
        ) = helperConfig.activeNetworkConfig();

        vm.etch(warpPrecompileAddress, address(mock).code);

        vm.startBroadcast(deployerKey);
        ERC20TokenHome erc20TokenHome = new ERC20TokenHome(
            teleporterRegistryAddress,
            teleporterManager,
            MIN_TELEPORTER_VERSION,
            tokenAddress,
            tokenDecimals
        );
        vm.stopBroadcast();

        return erc20TokenHome;
    }
}

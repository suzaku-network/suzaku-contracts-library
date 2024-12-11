// SPDX-License-Identifier: MIT
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
    bytes32 private constant ANVIL_CHAIN_HEX =
        0x7a69000000000000000000000000000000000000000000000000000000000000;
    uint256 private constant DEPLOYER_PRIV_KEY = 1;

    struct NetworkConfigTest {
        uint256 deployerKey;
        address owner;
        address bridger;
    }

    uint256 private _deployerKey = DEPLOYER_PRIV_KEY;
    address private _owner = vm.addr(DEPLOYER_PRIV_KEY);
    address private _bridger = makeAddr("bridger");

    NetworkConfigTest public activeNetworkConfigTest;

    constructor() {
        activeNetworkConfigTest = getNetworkConfig();
    }

    function getNetworkConfig() public view returns (NetworkConfigTest memory) {
        return NetworkConfigTest({deployerKey: _deployerKey, owner: _owner, bridger: _bridger});
    }
}

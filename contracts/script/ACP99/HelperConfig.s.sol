// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        uint256 deployerKey;
        bytes32 subnetID;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        // if (block.chainid == 43_113) {
        //     activeNetworkConfig = getAvalancheFujiConfig();
        // } else {
        activeNetworkConfig = getOrCreateAnvilConfig();
        // }
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        (, uint256 deployerKey) = makeAddrAndKey("subnetOwner");
        return NetworkConfig({
            deployerKey: deployerKey,
            subnetID: 0x5f4c8570d996184af03052f1b3acc1c7b432b0a41e7480de1b72d4c6f5983eb9
        });
    }
}

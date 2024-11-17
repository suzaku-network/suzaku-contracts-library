// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        uint256 proxyAdminOwnerKey;
        uint256 validatorManagerOwnerKey;
        bytes32 subnetID;
        uint64 churnPeriodSeconds;
        uint8 maximumChurnPercentage;
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
        (, uint256 proxyAdminOwnerKey) = makeAddrAndKey("proxyAdminOwner");
        (, uint256 validatorManagerOwnerKey) = makeAddrAndKey("validatorManagerOwner");
        return NetworkConfig({
            proxyAdminOwnerKey: proxyAdminOwnerKey,
            validatorManagerOwnerKey: validatorManagerOwnerKey,
            subnetID: 0x5f4c8570d996184af03052f1b3acc1c7b432b0a41e7480de1b72d4c6f5983eb9,
            churnPeriodSeconds: 1 hours,
            maximumChurnPercentage: 20
        });
    }
}

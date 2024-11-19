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
        if (block.chainid == 43_117) {
            activeNetworkConfig = getAvalancheEtnaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        (, uint256 proxyAdminOwnerKey) = makeAddrAndKey("proxyAdminOwner");
        (, uint256 validatorManagerOwnerKey) = makeAddrAndKey(
            "validatorManagerOwner"
        );
        return
            NetworkConfig({
                proxyAdminOwnerKey: proxyAdminOwnerKey,
                validatorManagerOwnerKey: validatorManagerOwnerKey,
                subnetID: 0x0bf528ffc3be7a65742ccdfe72d9c913685e2d5eee224a27ce0aff7502db855a,
                churnPeriodSeconds: 1 hours,
                maximumChurnPercentage: 20
            });
    }

    function getAvalancheEtnaConfig()
        public
        view
        returns (NetworkConfig memory)
    {
        uint256 proxyAdminOwnerKey = vm.envUint("PK");
        uint256 validatorManagerOwnerKey = vm.envUint("PK");
        return
            NetworkConfig({
                proxyAdminOwnerKey: proxyAdminOwnerKey,
                validatorManagerOwnerKey: validatorManagerOwnerKey,
                subnetID: 0x0bf528ffc3be7a65742ccdfe72d9c913685e2d5eee224a27ce0aff7502db855a,
                churnPeriodSeconds: 1 hours,
                maximumChurnPercentage: 20
            });
    }
}

// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {ACP99Manager} from "../../src/contracts/ACP99/ACP99Manager.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Script} from "forge-std/Script.sol";

contract DeployACP99Manager is Script {
    function run() external returns (ACP99Manager) {
        HelperConfig helperConfig = new HelperConfig();
        (uint256 deployerKey, bytes32 subnetID) = helperConfig.activeNetworkConfig();
        address deployerAddress = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        ACP99Manager validatorSetManager = new ACP99Manager(subnetID, deployerAddress);
        vm.stopBroadcast();

        return validatorSetManager;
    }
}

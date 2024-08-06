// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {ValidatorSetManager} from "../../src/contracts/ValidatorSetManager/ValidatorSetManager.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Script} from "forge-std/Script.sol";

contract DeployValidatorSetManager is Script {
    function run() external returns (ValidatorSetManager) {
        HelperConfig helperConfig = new HelperConfig();
        (uint256 deployerKey, bytes32 subnetID) = helperConfig.activeNetworkConfig();
        address deployerAddress = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        ValidatorSetManager validatorSetManager = new ValidatorSetManager(subnetID, deployerAddress);
        vm.stopBroadcast();

        return validatorSetManager;
    }
}

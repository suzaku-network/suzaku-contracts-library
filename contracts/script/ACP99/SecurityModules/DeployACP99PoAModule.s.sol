// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {ACP99Manager} from "../../../src/contracts/ACP99/ACP99Manager.sol";
import {ACP99PoAModule} from "../../../src/contracts/ACP99/SecurityModules/ACP99PoAModule.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {Script} from "forge-std/Script.sol";

contract DeployACP99PoAModule is Script {
    function run() external returns (ACP99Manager, ACP99PoAModule) {
        HelperConfig helperConfig = new HelperConfig();
        (uint256 deployerKey, bytes32 subnetID) = helperConfig.activeNetworkConfig();

        // Precompute the addresses of ACP99Manager and ACP99PoAModule
        address deployerAddress = vm.addr(deployerKey);
        uint256 deployerNonce = vm.getNonce(deployerAddress);
        address predictedManagerAddress = vm.computeCreateAddress(deployerAddress, deployerNonce);
        address predictedPoAModuleAddress =
            vm.computeCreateAddress(deployerAddress, deployerNonce + 1);

        vm.startBroadcast(deployerKey);

        // Deploy ACP99Manager first
        ACP99Manager manager = new ACP99Manager(subnetID, predictedPoAModuleAddress);

        // Deploy ACP99PoAModule
        ACP99PoAModule poaModule = new ACP99PoAModule(address(manager));

        // Verify the addresses match the predictions
        require(address(manager) == predictedManagerAddress, "Manager address mismatch");
        require(address(poaModule) == predictedPoAModuleAddress, "PoAModule address mismatch");

        vm.stopBroadcast();

        return (manager, poaModule);
    }
}

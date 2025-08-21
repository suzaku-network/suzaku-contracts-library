// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {
    BalancerValidatorManager,
    BalancerValidatorManagerSettings
} from "../../src/contracts/ValidatorManager/BalancerValidatorManager.sol";
import {PoASecurityModule} from
    "../../src/contracts/ValidatorManager/SecurityModule/PoASecurityModule.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

import {ACP77WarpMessengerTestMock} from "../../src/contracts/mocks/ACP77WarpMessengerTestMock.sol";
import {ValidatorManagerSettings} from
    "../../src/interfaces/ValidatorManager/IBalancerValidatorManager.sol";
import {ICMInitializable} from "@avalabs/icm-contracts/utilities/ICMInitializable.sol";
import {
    ValidatorManager,
    ValidatorManagerSettings as VMSettings
} from "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";

import {
    ConversionData,
    InitialValidator
} from "@avalabs/icm-contracts/validator-manager/interfaces/IACP99Manager.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Script} from "forge-std/Script.sol";

contract DeployBalancerValidatorManager is Script {
    /**
     * @notice Deploy BalancerValidatorManager with optional validator migration
     * @param initialSecurityModule Address of initial security module (0 to deploy PoASecurityModule)
     * @param initialSecurityModuleWeight Maximum weight for the security module
     * @param migratedValidators Array of validator node IDs to migrate from existing setup
     * @dev Pass extracted validators from ExtractValidators.s.sol or MigratePoAToBalancer.s.sol
     */
    function run(
        address initialSecurityModule,
        uint64 initialSecurityModuleWeight,
        bytes[] calldata migratedValidators
    ) external returns (address balancer, address securityModule, address vmAddress) {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint256 proxyAdminOwnerKey,
            uint256 validatorManagerOwnerKey,
            bytes32 subnetID,
            uint64 churnPeriodSeconds,
            uint8 maximumChurnPercentage
        ) = helperConfig.activeNetworkConfig();
        address proxyAdminOwnerAddress = vm.addr(proxyAdminOwnerKey);
        address validatorManagerOwnerAddress = vm.addr(validatorManagerOwnerKey);

        vm.startBroadcast(proxyAdminOwnerKey);

        // Deploy ValidatorManager proxy
        VMSettings memory vmSettings = VMSettings({
            admin: validatorManagerOwnerAddress,
            subnetID: subnetID,
            churnPeriodSeconds: churnPeriodSeconds,
            maximumChurnPercentage: maximumChurnPercentage
        });
        ValidatorManager vmImpl = new ValidatorManager(ICMInitializable.Allowed);
        vmAddress = UnsafeUpgrades.deployTransparentProxy(
            address(vmImpl),
            proxyAdminOwnerAddress,
            abi.encodeCall(ValidatorManager.initialize, (vmSettings))
        );
        vm.stopBroadcast();

        // Create memory copy of migratedValidators (calldata arrays are immutable)
        bytes[] memory actualMigratedValidators = new bytes[](migratedValidators.length);
        for (uint256 i = 0; i < migratedValidators.length; i++) {
            actualMigratedValidators[i] = migratedValidators[i];
        }

        // Set up mock warp messenger for test environment
        // vm.etch must be done outside of broadcast
        ACP77WarpMessengerTestMock warpMessengerTestMock = new ACP77WarpMessengerTestMock(vmAddress);
        address WARP_MESSENGER_ADDR = 0x0200000000000000000000000000000000000005;
        vm.etch(WARP_MESSENGER_ADDR, address(warpMessengerTestMock).code);

        // Pre-initialize VM validator set using the SAME values the mock hashes (messageIndex=2)
        {
            // Pull nodeIDs & chainID from the mock to avoid drift
            bytes memory node02 = warpMessengerTestMock.DEFAULT_NODE_ID_02();
            bytes memory node03 = warpMessengerTestMock.DEFAULT_NODE_ID_03();
            bytes32 chainId = warpMessengerTestMock.getBlockchainID();
            bytes32 l1Id = warpMessengerTestMock.DEFAULT_L1_ID();

            InitialValidator[] memory initialValidators = new InitialValidator[](2);
            initialValidators[0] =
                InitialValidator({nodeID: node02, blsPublicKey: new bytes(48), weight: 180});
            initialValidators[1] =
                InitialValidator({nodeID: node03, blsPublicKey: new bytes(48), weight: 20});
            ConversionData memory conversionData = ConversionData({
                subnetID: l1Id,
                validatorManagerBlockchainID: chainId,
                validatorManagerAddress: vmAddress,
                initialValidators: initialValidators
            });
            vm.startBroadcast(validatorManagerOwnerKey);
            ValidatorManager(vmAddress).initializeValidatorSet(conversionData, 2);
            vm.stopBroadcast();
        }

        vm.startBroadcast(proxyAdminOwnerKey);
        BalancerValidatorManager balancerImpl = new BalancerValidatorManager();

        // Deploy proxy without initialization
        balancer =
            UnsafeUpgrades.deployTransparentProxy(address(balancerImpl), proxyAdminOwnerAddress, "");

        // Deploy security module if not provided
        if (initialSecurityModule == address(0)) {
            initialSecurityModule =
                address(new PoASecurityModule(balancer, validatorManagerOwnerAddress));
        }

        // Transfer ValidatorManager ownership to Balancer
        vm.stopBroadcast();
        vm.startBroadcast(validatorManagerOwnerKey);
        ValidatorManager(vmAddress).transferOwnership(balancer);
        vm.stopBroadcast();

        // Initialize Balancer (must use non-admin due to transparent proxy pattern)
        vm.startBroadcast(validatorManagerOwnerKey);
        BalancerValidatorManagerSettings memory balancerSettings = BalancerValidatorManagerSettings({
            baseSettings: ValidatorManagerSettings({
                admin: address(0), // Will be set by ValidatorManager initialization
                subnetID: subnetID,
                churnPeriodSeconds: churnPeriodSeconds,
                maximumChurnPercentage: maximumChurnPercentage
            }),
            initialOwner: validatorManagerOwnerAddress,
            initialSecurityModule: initialSecurityModule,
            initialSecurityModuleMaxWeight: initialSecurityModuleWeight,
            migratedValidators: actualMigratedValidators
        });
        BalancerValidatorManager(balancer).initialize(balancerSettings, vmAddress);
        vm.stopBroadcast();

        // Set up security module if this is a fresh deployment (no migration)
        if (actualMigratedValidators.length == 0 && initialSecurityModule != address(0)) {
            vm.startBroadcast(validatorManagerOwnerKey);
            BalancerValidatorManager(balancer).setUpSecurityModule(
                initialSecurityModule, initialSecurityModuleWeight
            );
            vm.stopBroadcast();
        }

        return (balancer, initialSecurityModule, vmAddress);
    }
}

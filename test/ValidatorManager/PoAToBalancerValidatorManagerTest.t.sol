// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {HelperConfig} from "../../script/ValidatorManager/HelperConfig.s.sol";
import {PoAUpgradeConfig} from "../../script/ValidatorManager/PoAUpgradeConfigTypes.s.sol";
import {ExecutePoAManager} from "../../script/ValidatorManager/PoAValidatorManager.s.sol";
import {UpgradePoAToBalancer} from "../../script/ValidatorManager/UpgradePoAToBalancer.s.sol";

import {
    BalancerValidatorManager,
    BalancerValidatorManagerSettings
} from "../../src/contracts/ValidatorManager/BalancerValidatorManager.sol";
import {ACP77WarpMessengerTestMock} from "../../src/contracts/mocks/ACP77WarpMessengerTestMock.sol";
import {IBalancerValidatorManager} from
    "../../src/interfaces/ValidatorManager/IBalancerValidatorManager.sol";

import {ICMInitializable} from "@avalabs/icm-contracts/utilities/ICMInitializable.sol";
import {PoAManager} from "@avalabs/icm-contracts/validator-manager/PoAManager.sol";
import {ValidatorManager} from "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";
import {IValidatorManagerExternalOwnable} from
    "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManagerExternalOwnable.sol";

import {ValidatorManagerSettings} from
    "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";
import {
    ConversionData,
    InitialValidator,
    PChainOwner,
    Validator
} from "@avalabs/icm-contracts/validator-manager/interfaces/IACP99Manager.sol";
import {ValidatorStatus} from
    "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManager.sol";
import {IWarpMessenger} from
    "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {Test, console} from "forge-std/Test.sol";

contract PoAToBalancerValidatorManagerTest is Test {
    ExecutePoAManager poADeployer;
    address validatorManagerProxyAddress;
    PoAManager poAValidatorManager;
    ValidatorManager validatorManager;
    uint256 proxyAdminOwnerKey;
    uint256 validatorManagerOwnerKey;
    address validatorManagerOwnerAddress;
    address proxyAdminOwnerAddress;
    bytes32 l1ID;
    uint64 churnPeriodSeconds;
    uint8 maximumChurnPercentage;
    address[] testSecurityModules;
    PChainOwner pChainOwner;

    bytes32 constant ANVIL_CHAIN_ID_HEX =
        0x7a69000000000000000000000000000000000000000000000000000000000000;
    address constant WARP_MESSENGER_ADDR = 0x0200000000000000000000000000000000000005;
    uint32 constant INITIALIZE_VALIDATOR_SET_MESSAGE_INDEX = 2;
    uint32 constant COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX = 3;
    uint32 constant VALIDATOR_UPTIME_MESSAGE_INDEX = 4;
    uint32 constant COMPLETE_VALIDATOR_WEIGHT_UPDATE_MESSAGE_INDEX = 5;
    uint32 constant COMPLETE_VALIDATOR_WEIGHT_UPDATE_ZERO_MESSAGE_INDEX = 6;
    uint32 constant VALIDATOR_REGISTRATION_EXPIRED_MESSAGE_INDEX = 7;
    bytes constant VALIDATOR_NODE_ID_01 =
        bytes(hex"1234567812345678123456781234567812345678123456781234567812345678");
    bytes constant VALIDATOR_NODE_ID_02 =
        bytes(hex"2345678123456781234567812345678123456781234567812345678123456781");
    bytes constant VALIDATOR_NODE_ID_03 =
        bytes(hex"3456781234567812345678123456781234567812345678123456781234567812");
    bytes constant VALIDATOR_01_BLS_PUBLIC_KEY = new bytes(48);
    uint64 constant VALIDATOR_WEIGHT = 20;
    bytes32 constant VALIDATION_ID_01 =
        0x3a41d4db60b49389d4b121c2137a1382431a89369c5445c2a46877c3929dd9c6;
    bytes32 constant VALIDATION_ID_02 =
        0x0ff9e5c77da268eef8379d3ff1572d16d0fa519fcaa6f10b366c34ce3e97ca5a;
    bytes32 constant VALIDATION_ID_03 =
        0xff7f451c6758256d0b0a32a7e32aef5180693e6e296b329e80a8ee70cfb5f19a;
    uint64 constant DEFAULT_EXPIRY = 1_704_067_200 + 1 days;
    uint64 constant DEFAULT_MAX_WEIGHT = 100;

    function setUp() public {
        poADeployer = new ExecutePoAManager();

        HelperConfig helperConfig = new HelperConfig();
        (
            proxyAdminOwnerKey,
            validatorManagerOwnerKey,
            l1ID,
            churnPeriodSeconds,
            maximumChurnPercentage
        ) = helperConfig.activeNetworkConfig();
        validatorManagerOwnerAddress = vm.addr(validatorManagerOwnerKey);
        proxyAdminOwnerAddress = vm.addr(proxyAdminOwnerKey);

        testSecurityModules = new address[](3);
        testSecurityModules[0] = makeAddr("securityModule1");
        testSecurityModules[1] = makeAddr("securityModule2");
        testSecurityModules[2] = makeAddr("securityModule3");

        // Create PoAUpgradeConfig and deploy the PoA validator manager
        PoAUpgradeConfig memory poaConfig = PoAUpgradeConfig({
            l1ID: l1ID,
            churnPeriodSeconds: churnPeriodSeconds,
            maximumChurnPercentage: maximumChurnPercentage,
            proxyAdminOwnerAddress: proxyAdminOwnerAddress,
            validatorManagerOwnerAddress: validatorManagerOwnerAddress,
            proxyAddress: address(0), // Not used for deployment
            initialSecurityModuleMaxWeight: DEFAULT_MAX_WEIGHT,
            migratedValidators: new bytes[](0) // Not used for deployment
        });

        // Deploy ValidatorManager implementation
        validatorManager = new ValidatorManager(ICMInitializable.Allowed);

        // For testing purposes, we'll use the ValidatorManager directly
        // In production, this would be behind a proxy
        validatorManagerProxyAddress = address(validatorManager);

        // Initialize the ValidatorManager with settings
        ValidatorManagerSettings memory settings = ValidatorManagerSettings({
            subnetID: l1ID,
            admin: validatorManagerOwnerAddress, // Set proper admin for PoA
            churnPeriodSeconds: churnPeriodSeconds,
            maximumChurnPercentage: maximumChurnPercentage
        });
        validatorManager.initialize(settings);

        // Deploy PoAManager wrapper
        poAValidatorManager = new PoAManager(
            validatorManagerOwnerAddress,
            IValidatorManagerExternalOwnable(address(validatorManager))
        );

        ACP77WarpMessengerTestMock warpMessengerTestMock =
            new ACP77WarpMessengerTestMock(validatorManagerProxyAddress);
        vm.etch(WARP_MESSENGER_ADDR, address(warpMessengerTestMock).code);

        address[] memory addresses = new address[](1);
        addresses[0] = 0x1234567812345678123456781234567812345678;
        pChainOwner = PChainOwner({threshold: 1, addresses: addresses});

        // Initialize the validator set on the underlying ValidatorManager
        vm.prank(validatorManagerOwnerAddress);
        validatorManager.initializeValidatorSet(
            _generateTestConversionData(), INITIALIZE_VALIDATOR_SET_MESSAGE_INDEX
        );

        // Warp to 2024-01-01 00:00:00
        vm.warp(1_704_067_200);
    }

    modifier validatorRegistrationInitialized() {
        vm.prank(testSecurityModules[0]);
        (
            bytes memory nodeID,
            bytes memory blsPublicKey,
            PChainOwner memory remainingBalanceOwner,
            PChainOwner memory disableOwner
        ) = _getTestValidatorRegistrationParams();
        poAValidatorManager.initiateValidatorRegistration(
            nodeID, blsPublicKey, remainingBalanceOwner, disableOwner, VALIDATOR_WEIGHT
        );
        _;
    }

    modifier validatorRegistrationCompleted() {
        vm.startPrank(testSecurityModules[0]);
        (
            bytes memory nodeID,
            bytes memory blsPublicKey,
            PChainOwner memory remainingBalanceOwner,
            PChainOwner memory disableOwner
        ) = _getTestValidatorRegistrationParams();
        poAValidatorManager.initiateValidatorRegistration(
            nodeID, blsPublicKey, remainingBalanceOwner, disableOwner, VALIDATOR_WEIGHT
        );
        poAValidatorManager.completeValidatorRegistration(
            COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX
        );
        vm.stopPrank();
        _;
    }

    // Helper function to return validator registration parameters
    function _getTestValidatorRegistrationParams()
        private
        view
        returns (
            bytes memory nodeID,
            bytes memory blsPublicKey,
            PChainOwner memory remainingBalanceOwner,
            PChainOwner memory disableOwner
        )
    {
        return (VALIDATOR_NODE_ID_01, VALIDATOR_01_BLS_PUBLIC_KEY, pChainOwner, pChainOwner);
    }

    function _generateTestConversionData() private view returns (ConversionData memory) {
        InitialValidator[] memory initialValidators = new InitialValidator[](2);
        initialValidators[0] = InitialValidator({
            nodeID: VALIDATOR_NODE_ID_02,
            weight: 180,
            blsPublicKey: VALIDATOR_01_BLS_PUBLIC_KEY
        });
        initialValidators[1] = InitialValidator({
            nodeID: VALIDATOR_NODE_ID_03,
            weight: 20,
            blsPublicKey: VALIDATOR_01_BLS_PUBLIC_KEY
        });
        ConversionData memory conversionData = ConversionData({
            subnetID: l1ID,
            validatorManagerBlockchainID: ANVIL_CHAIN_ID_HEX,
            validatorManagerAddress: validatorManagerProxyAddress,
            initialValidators: initialValidators
        });
        return conversionData;
    }

    function _upgradePoAManagerToBalancerValidatorManager(
        bytes[] memory migratedValidators
    ) private returns (BalancerValidatorManager, address) {
        UpgradePoAToBalancer upgrader = new UpgradePoAToBalancer();

        // Create the upgrade config
        PoAUpgradeConfig memory upgradeConfig = PoAUpgradeConfig({
            l1ID: l1ID,
            churnPeriodSeconds: churnPeriodSeconds,
            maximumChurnPercentage: maximumChurnPercentage,
            proxyAdminOwnerAddress: proxyAdminOwnerAddress,
            validatorManagerOwnerAddress: validatorManagerOwnerAddress,
            proxyAddress: validatorManagerProxyAddress,
            initialSecurityModuleMaxWeight: 500,
            migratedValidators: migratedValidators
        });

        // Execute the upgrade
        (address proxyAddr, address securityModuleAddr) =
            upgrader.executeUpgradePoAToBalancer(upgradeConfig, proxyAdminOwnerKey);

        return (BalancerValidatorManager(proxyAddr), securityModuleAddr);
    }

    function testUpgradeToBalancerValidatorManagerInitializesCorrectly() public {
        bytes[] memory migratedValidators = new bytes[](2);
        migratedValidators[0] = VALIDATOR_NODE_ID_02;
        migratedValidators[1] = VALIDATOR_NODE_ID_03;

        (BalancerValidatorManager balancerValidatorManager, address securityModuleAddr) =
            _upgradePoAManagerToBalancerValidatorManager(migratedValidators);

        assertEq(balancerValidatorManager.owner(), validatorManagerOwnerAddress);
        assertEq(balancerValidatorManager.getChurnPeriodSeconds(), churnPeriodSeconds);
        address[] memory securityModules = balancerValidatorManager.getSecurityModules();
        assertEq(securityModules.length, 1);
        assertEq(securityModules[0], securityModuleAddr);
        (uint64 weight, uint64 maxWeight) =
            balancerValidatorManager.getSecurityModuleWeights(securityModuleAddr);
        assertEq(weight, 200);
        assertEq(maxWeight, 500);
        Validator memory validator = balancerValidatorManager.getValidator(VALIDATION_ID_02);
        assertEq(validator.nodeID, VALIDATOR_NODE_ID_02);
        assert(validator.status == ValidatorStatus.Active);
        assertEq(validator.weight, 180);
    }

    function testUpgradeToBalancerValidatorManagerRevertsIfMissingMigratedValidators() public {
        bytes[] memory migratedValidators = new bytes[](1);
        migratedValidators[0] = VALIDATOR_NODE_ID_02;

        UpgradePoAToBalancer upgrader = new UpgradePoAToBalancer();

        // Create the upgrade config with missing validators
        PoAUpgradeConfig memory upgradeConfig = PoAUpgradeConfig({
            l1ID: l1ID,
            churnPeriodSeconds: churnPeriodSeconds,
            maximumChurnPercentage: maximumChurnPercentage,
            proxyAdminOwnerAddress: proxyAdminOwnerAddress,
            validatorManagerOwnerAddress: validatorManagerOwnerAddress,
            proxyAddress: validatorManagerProxyAddress,
            initialSecurityModuleMaxWeight: 500,
            migratedValidators: migratedValidators
        });

        // The upgrade should fail because one validator is missing
        vm.expectRevert(
            abi.encodeWithSelector(
                IBalancerValidatorManager
                    .BalancerValidatorManager__MigratedValidatorsTotalWeightMismatch
                    .selector,
                180,
                200
            )
        );
        upgrader.executeUpgradePoAToBalancer(upgradeConfig, proxyAdminOwnerKey);
    }

    function testUpgradeToBalancerValidatorManagerWithPoAValidator() public {
        // Add another validator before upgrading
        vm.startPrank(validatorManagerOwnerAddress);
        poAValidatorManager.initiateValidatorRegistration(
            VALIDATOR_NODE_ID_01, VALIDATOR_01_BLS_PUBLIC_KEY, pChainOwner, pChainOwner, 20
        );
        poAValidatorManager.completeValidatorRegistration(
            COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX
        );
        vm.stopPrank();

        bytes[] memory migratedValidators = new bytes[](3);
        migratedValidators[0] = VALIDATOR_NODE_ID_01;
        migratedValidators[1] = VALIDATOR_NODE_ID_02;
        migratedValidators[2] = VALIDATOR_NODE_ID_03;

        (BalancerValidatorManager balancerValidatorManager, address securityModuleAddr) =
            _upgradePoAManagerToBalancerValidatorManager(migratedValidators);

        Validator memory validator = balancerValidatorManager.getValidator(VALIDATION_ID_01);
        (uint64 weight,) = balancerValidatorManager.getSecurityModuleWeights(securityModuleAddr);
        assertEq(validator.nodeID, VALIDATOR_NODE_ID_01);
        assert(validator.status == ValidatorStatus.Active);
        assertEq(validator.weight, 20);
        assertEq(weight, 220);

        // Remove the validator
        vm.startPrank(securityModuleAddr);
        balancerValidatorManager.initiateValidatorRemovalWithSecurityModule(VALIDATION_ID_01);
        balancerValidatorManager.completeValidatorRemovalWithSecurityModule(
            VALIDATOR_REGISTRATION_EXPIRED_MESSAGE_INDEX
        );

        validator = balancerValidatorManager.getValidator(VALIDATION_ID_01);
        (weight,) = balancerValidatorManager.getSecurityModuleWeights(securityModuleAddr);
        assert(validator.status == ValidatorStatus.Completed);
        assertEq(validator.endTime, block.timestamp);
        assertEq(validator.weight, 0);
        assertEq(weight, 200);
    }

    // TODO: Add more tests with validators brought over from PoA
}

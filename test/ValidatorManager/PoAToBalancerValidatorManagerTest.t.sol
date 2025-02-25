// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {DeployTestPoAValidatorManager} from
    "../../script/ValidatorManager/DeployPoAValidatorManager.s.sol";
import {HelperConfig} from "../../script/ValidatorManager/HelperConfig.s.sol";
import {
    BalancerValidatorManager,
    BalancerValidatorManagerSettings
} from "../../src/contracts/ValidatorManager/BalancerValidatorManager.sol";
import {ACP77WarpMessengerTestMock} from "../../src/contracts/mocks/ACP77WarpMessengerTestMock.sol";
import {IBalancerValidatorManager} from
    "../../src/interfaces/ValidatorManager/IBalancerValidatorManager.sol";
import {PoAValidatorManager} from "@avalabs/icm-contracts/validator-manager/PoAValidatorManager.sol";
import {
    ConversionData,
    InitialValidator,
    PChainOwner,
    Validator,
    ValidatorManagerSettings,
    ValidatorRegistrationInput,
    ValidatorStatus
} from "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManager.sol";
import {IWarpMessenger} from
    "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";

import {Options} from "@openzeppelin/foundry-upgrades/Options.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test, console} from "forge-std/Test.sol";

contract PoAToBalancerValidatorManagerTest is Test {
    DeployTestPoAValidatorManager poADeployer;
    address validatorManagerProxyAddress;
    PoAValidatorManager poAValidatorManager;
    uint256 proxyAdminOwnerKey;
    uint256 validatorManagerOwnerKey;
    address validatorManagerOwnerAddress;
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
        poADeployer = new DeployTestPoAValidatorManager();

        HelperConfig helperConfig = new HelperConfig();
        (
            proxyAdminOwnerKey,
            validatorManagerOwnerKey,
            l1ID,
            churnPeriodSeconds,
            maximumChurnPercentage
        ) = helperConfig.activeNetworkConfig();
        validatorManagerOwnerAddress = vm.addr(validatorManagerOwnerKey);

        testSecurityModules = new address[](3);
        testSecurityModules[0] = makeAddr("securityModule1");
        testSecurityModules[1] = makeAddr("securityModule2");
        testSecurityModules[2] = makeAddr("securityModule3");

        validatorManagerProxyAddress = poADeployer.run();
        poAValidatorManager = PoAValidatorManager(validatorManagerProxyAddress);

        ACP77WarpMessengerTestMock warpMessengerTestMock =
            new ACP77WarpMessengerTestMock(validatorManagerProxyAddress);
        vm.etch(WARP_MESSENGER_ADDR, address(warpMessengerTestMock).code);

        address[] memory addresses = new address[](1);
        addresses[0] = 0x1234567812345678123456781234567812345678;
        pChainOwner = PChainOwner({threshold: 1, addresses: addresses});

        // Initialize the validator set of the PoA Validator Manager
        poAValidatorManager.initializeValidatorSet(
            _generateTestConversionData(), INITIALIZE_VALIDATOR_SET_MESSAGE_INDEX
        );

        // Warp to 2024-01-01 00:00:00
        vm.warp(1_704_067_200);
    }

    modifier validatorRegistrationInitialized() {
        vm.prank(testSecurityModules[0]);
        poAValidatorManager.initializeValidatorRegistration(
            _generateTestValidatorRegistrationInput(), VALIDATOR_WEIGHT
        );
        _;
    }

    modifier validatorRegistrationCompleted() {
        vm.startPrank(testSecurityModules[0]);
        poAValidatorManager.initializeValidatorRegistration(
            _generateTestValidatorRegistrationInput(), VALIDATOR_WEIGHT
        );
        poAValidatorManager.completeValidatorRegistration(
            COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX
        );
        vm.stopPrank();
        _;
    }

    function _generateTestValidatorRegistrationInput()
        private
        view
        returns (ValidatorRegistrationInput memory)
    {
        return ValidatorRegistrationInput({
            nodeID: VALIDATOR_NODE_ID_01,
            blsPublicKey: VALIDATOR_01_BLS_PUBLIC_KEY,
            registrationExpiry: DEFAULT_EXPIRY,
            remainingBalanceOwner: pChainOwner,
            disableOwner: pChainOwner
        });
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
            l1ID: l1ID,
            validatorManagerBlockchainID: ANVIL_CHAIN_ID_HEX,
            validatorManagerAddress: validatorManagerProxyAddress,
            initialValidators: initialValidators
        });
        return conversionData;
    }

    function _generateTestBalancerValidatorManagerSettings(
        bytes[] memory migratedValidators
    ) private view returns (BalancerValidatorManagerSettings memory) {
        return BalancerValidatorManagerSettings({
            baseSettings: ValidatorManagerSettings({
                l1ID: l1ID,
                churnPeriodSeconds: churnPeriodSeconds,
                maximumChurnPercentage: maximumChurnPercentage
            }),
            initialOwner: validatorManagerOwnerAddress,
            initialSecurityModule: testSecurityModules[0],
            initialSecurityModuleMaxWeight: 500,
            migratedValidators: migratedValidators
        });
    }

    function _upgradePoAValidatorManagerToBalancerValidatorManager(
        bytes[] memory migratedValidators
    ) private returns (BalancerValidatorManager) {
        Options memory opts;
        opts.unsafeAllow = "missing-initializer-call";
        vm.startBroadcast(proxyAdminOwnerKey);
        Upgrades.upgradeProxy(
            validatorManagerProxyAddress,
            "BalancerValidatorManager.sol:BalancerValidatorManager",
            "",
            opts
        );
        BalancerValidatorManager balancerValidatorManager =
            BalancerValidatorManager(validatorManagerProxyAddress);
        balancerValidatorManager.initialize(
            _generateTestBalancerValidatorManagerSettings(migratedValidators)
        );
        vm.stopBroadcast();

        return balancerValidatorManager;
    }

    function testUpgradeToBalancerValidatorManagerInitializesCorrectly() public {
        bytes[] memory migratedValidators = new bytes[](2);
        migratedValidators[0] = VALIDATOR_NODE_ID_02;
        migratedValidators[1] = VALIDATOR_NODE_ID_03;

        BalancerValidatorManager balancerValidatorManager =
            _upgradePoAValidatorManagerToBalancerValidatorManager(migratedValidators);

        assertEq(balancerValidatorManager.owner(), validatorManagerOwnerAddress);
        assertEq(balancerValidatorManager.getChurnPeriodSeconds(), churnPeriodSeconds);
        address[] memory securityModules = balancerValidatorManager.getSecurityModules();
        assertEq(securityModules.length, 1);
        assertEq(securityModules[0], testSecurityModules[0]);
        (uint64 weight, uint64 maxWeight) =
            balancerValidatorManager.getSecurityModuleWeights(testSecurityModules[0]);
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

        Options memory opts;
        opts.unsafeAllow = "missing-initializer-call";
        vm.startBroadcast(proxyAdminOwnerKey);
        Upgrades.upgradeProxy(
            validatorManagerProxyAddress,
            "BalancerValidatorManager.sol:BalancerValidatorManager",
            "",
            opts
        );
        BalancerValidatorManager balancerValidatorManager =
            BalancerValidatorManager(validatorManagerProxyAddress);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBalancerValidatorManager
                    .BalancerValidatorManager__MigratedValidatorsTotalWeightMismatch
                    .selector,
                180,
                200
            )
        );
        balancerValidatorManager.initialize(
            _generateTestBalancerValidatorManagerSettings(migratedValidators)
        );
        vm.stopBroadcast();
    }

    function testUpgradeToBalancerValidatorManagerWithPoAValidator() public {
        // Add another validator before upgrading
        vm.startPrank(validatorManagerOwnerAddress);
        poAValidatorManager.initializeValidatorRegistration(
            ValidatorRegistrationInput({
                nodeID: VALIDATOR_NODE_ID_01,
                blsPublicKey: VALIDATOR_01_BLS_PUBLIC_KEY,
                registrationExpiry: DEFAULT_EXPIRY,
                remainingBalanceOwner: pChainOwner,
                disableOwner: pChainOwner
            }),
            20
        );
        poAValidatorManager.completeValidatorRegistration(
            COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX
        );
        vm.stopPrank();

        bytes[] memory migratedValidators = new bytes[](3);
        migratedValidators[0] = VALIDATOR_NODE_ID_01;
        migratedValidators[1] = VALIDATOR_NODE_ID_02;
        migratedValidators[2] = VALIDATOR_NODE_ID_03;

        BalancerValidatorManager balancerValidatorManager =
            _upgradePoAValidatorManagerToBalancerValidatorManager(migratedValidators);

        Validator memory validator = balancerValidatorManager.getValidator(VALIDATION_ID_01);
        (uint64 weight,) = balancerValidatorManager.getSecurityModuleWeights(testSecurityModules[0]);
        assertEq(validator.nodeID, VALIDATOR_NODE_ID_01);
        assert(validator.status == ValidatorStatus.Active);
        assertEq(validator.weight, 20);
        assertEq(weight, 220);

        // Remove the validator
        vm.prank(testSecurityModules[0]);
        balancerValidatorManager.initializeEndValidation(VALIDATION_ID_01);

        validator = balancerValidatorManager.getValidator(VALIDATION_ID_01);
        (weight,) = balancerValidatorManager.getSecurityModuleWeights(testSecurityModules[0]);
        assert(validator.status == ValidatorStatus.PendingRemoved);
        assertEq(validator.endedAt, block.timestamp);
        assertEq(validator.weight, 0);
        assertEq(weight, 200);
    }

    // TODO: Add more tests with validators brought over from PoA
}

// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {DeployBalancerValidatorManager} from
    "../../script/ValidatorManager/DeployBalancerValidatorManager.s.sol";
import {HelperConfig} from "../../script/ValidatorManager/HelperConfig.s.sol";
import {BalancerValidatorManager} from
    "../../src/contracts/ValidatorManager/BalancerValidatorManager.sol";
import {ACP77WarpMessengerTestMock} from "../../src/contracts/mocks/ACP77WarpMessengerTestMock.sol";
import {IBalancerValidatorManager} from
    "../../src/interfaces/ValidatorManager/IBalancerValidatorManager.sol";

import {
    ConversionData,
    InitialValidator,
    PChainOwner,
    Validator,
    ValidatorChurnPeriod,
    ValidatorRegistrationInput,
    ValidatorStatus
} from "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManager.sol";
import {IWarpMessenger} from
    "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {Test, console} from "forge-std/Test.sol";

contract BalancerValidatorManagerTest is Test {
    DeployBalancerValidatorManager deployer;
    BalancerValidatorManager validatorManager;
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
        deployer = new DeployBalancerValidatorManager();

        HelperConfig helperConfig = new HelperConfig();
        (, validatorManagerOwnerKey, l1ID, churnPeriodSeconds, maximumChurnPercentage) =
            helperConfig.activeNetworkConfig();
        validatorManagerOwnerAddress = vm.addr(validatorManagerOwnerKey);

        testSecurityModules = new address[](3);
        testSecurityModules[0] = makeAddr("securityModule1");
        testSecurityModules[1] = makeAddr("securityModule2");
        testSecurityModules[2] = makeAddr("securityModule3");

        (address validatorManagerAddress,) =
            deployer.run(testSecurityModules[0], DEFAULT_MAX_WEIGHT, new bytes[](0));
        validatorManager = BalancerValidatorManager(validatorManagerAddress);

        ACP77WarpMessengerTestMock warpMessengerTestMock =
            new ACP77WarpMessengerTestMock(validatorManagerAddress);
        vm.etch(WARP_MESSENGER_ADDR, address(warpMessengerTestMock).code);

        address[] memory addresses = new address[](1);
        addresses[0] = 0x1234567812345678123456781234567812345678;
        pChainOwner = PChainOwner({threshold: 1, addresses: addresses});

        // Warp to 2024-01-01 00:00:00
        vm.warp(1_704_067_200);
    }

    modifier validatorSetInitialized() {
        validatorManager.initializeValidatorSet(
            _generateTestConversionData(), INITIALIZE_VALIDATOR_SET_MESSAGE_INDEX
        );
        _;
    }

    modifier securityModulesSetUp() {
        vm.prank(validatorManagerOwnerAddress);
        validatorManager.setUpSecurityModule(testSecurityModules[1], DEFAULT_MAX_WEIGHT);
        _;
    }

    modifier validatorRegistrationInitialized() {
        vm.prank(testSecurityModules[0]);
        validatorManager.initializeValidatorRegistration(
            _generateTestValidatorRegistrationInput(), VALIDATOR_WEIGHT
        );
        _;
    }

    modifier validatorRegistrationCompleted() {
        vm.startPrank(testSecurityModules[0]);
        validatorManager.initializeValidatorRegistration(
            _generateTestValidatorRegistrationInput(), VALIDATOR_WEIGHT
        );
        validatorManager.completeValidatorRegistration(
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
            validatorManagerAddress: address(validatorManager),
            initialValidators: initialValidators
        });
        return conversionData;
    }

    function testBalancerValidatorManagerInitializesCorrectly() public view {
        assertEq(validatorManager.owner(), validatorManagerOwnerAddress);
        assertEq(validatorManager.getChurnPeriodSeconds(), churnPeriodSeconds);
        address[] memory securityModules = validatorManager.getSecurityModules();
        assertEq(securityModules.length, 1);
        assertEq(securityModules[0], testSecurityModules[0]);
    }

    function testSetUpSecurityModule() public {
        // Call setUpSecurityModule as owner
        vm.prank(validatorManagerOwnerAddress);
        validatorManager.setUpSecurityModule(testSecurityModules[1], DEFAULT_MAX_WEIGHT);

        // Check that the security module was registered
        address[] memory securityModules = validatorManager.getSecurityModules();
        (uint64 weight, uint64 maxWeight) =
            validatorManager.getSecurityModuleWeights(testSecurityModules[1]);
        assertEq(securityModules.length, 2);
        assertEq(securityModules[1], testSecurityModules[1]);
        assertEq(weight, 0);
        assertEq(maxWeight, DEFAULT_MAX_WEIGHT);
    }

    function testSetUpSecurityModuleWithZeroMaxWeightReverts() public {
        vm.prank(validatorManagerOwnerAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBalancerValidatorManager
                    .BalancerValidatorManager__SecurityModuleNotRegistered
                    .selector,
                testSecurityModules[1]
            )
        );
        validatorManager.setUpSecurityModule(testSecurityModules[1], 0);
    }

    function testSetUpSecurityModuleRevertsIfMaxWeightLowerThanCurrentWeight()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        vm.prank(validatorManagerOwnerAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBalancerValidatorManager
                    .BalancerValidatorManager__SecurityModuleNewMaxWeightLowerThanCurrentWeight
                    .selector,
                testSecurityModules[0],
                10,
                20
            )
        );
        validatorManager.setUpSecurityModule(testSecurityModules[0], 10);
    }

    function testSetUpSecurityModuleEmitsEvent() public {
        vm.prank(validatorManagerOwnerAddress);
        vm.expectEmit(true, false, false, true);
        emit IBalancerValidatorManager.SetUpSecurityModule(
            testSecurityModules[1], DEFAULT_MAX_WEIGHT
        );
        validatorManager.setUpSecurityModule(testSecurityModules[1], DEFAULT_MAX_WEIGHT);
    }

    function testInitializeValidatorRegistration() public validatorSetInitialized {
        vm.prank(testSecurityModules[0]);
        validatorManager.initializeValidatorRegistration(
            _generateTestValidatorRegistrationInput(), VALIDATOR_WEIGHT
        );

        Validator memory validator = validatorManager.getValidator(VALIDATION_ID_01);
        assertEq(validator.nodeID, VALIDATOR_NODE_ID_01);
        assert(validator.status == ValidatorStatus.PendingAdded);
        assertEq(validator.messageNonce, 0);
        assertEq(validator.weight, VALIDATOR_WEIGHT);
        assertEq(validator.startedAt, 0);
        assertEq(validator.endedAt, 0);
        (uint64 weight,) = validatorManager.getSecurityModuleWeights(testSecurityModules[0]);
        assertEq(weight, VALIDATOR_WEIGHT);
    }

    function testCompleteValidatorRegistration()
        public
        validatorSetInitialized
        validatorRegistrationInitialized
    {
        vm.prank(testSecurityModules[0]);
        validatorManager.completeValidatorRegistration(
            COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX
        );

        Validator memory validator = validatorManager.getValidator(VALIDATION_ID_01);
        assert(validator.status == ValidatorStatus.Active);
        assertEq(validator.startedAt, block.timestamp);
    }

    function testInitializeValidatorWeightUpdate()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        // Warp to 2024-01-01 02:00:00 to exit the churn period (1 hour)
        vm.warp(1_704_067_200 + 2 hours);

        vm.prank(testSecurityModules[0]);
        validatorManager.initializeValidatorWeightUpdate(VALIDATION_ID_01, 40);

        Validator memory validator = validatorManager.getValidator(VALIDATION_ID_01);
        assertEq(validator.weight, 40);
        assertEq(validator.messageNonce, 1);
        assert(validatorManager.isValidatorPendingWeightUpdate(VALIDATION_ID_01));
    }

    function testInitializeValidatorWeightUpdateRevertsIfWrongSecurityModule()
        public
        validatorSetInitialized
        securityModulesSetUp
        validatorRegistrationCompleted
    {
        vm.prank(testSecurityModules[1]);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBalancerValidatorManager
                    .BalancerValidatorManager__ValidatorNotBelongingToSecurityModule
                    .selector,
                VALIDATION_ID_01,
                testSecurityModules[1]
            )
        );
        validatorManager.initializeValidatorWeightUpdate(VALIDATION_ID_01, 40);
    }

    function testInitializeValidatorWeightUpdateRevertsIfPendingUpdate()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        // Warp to 2024-01-01 02:00:00 to exit the churn period (1 hour)
        vm.warp(1_704_067_200 + 2 hours);

        vm.startPrank(testSecurityModules[0]);
        validatorManager.initializeValidatorWeightUpdate(VALIDATION_ID_01, 40);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBalancerValidatorManager.BalancerValidatorManager__PendingWeightUpdate.selector,
                VALIDATION_ID_01
            )
        );
        validatorManager.initializeValidatorWeightUpdate(VALIDATION_ID_01, 50);
    }

    function testInitializeValidatorWeightUpdateRevertsIfExceedsMaxWeight()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        // Lower the max weight of the security module
        vm.prank(validatorManagerOwnerAddress);
        validatorManager.setUpSecurityModule(testSecurityModules[0], 30);

        // Warp to 2024-01-01 02:00:00 to exit the churn period (1 hour)
        vm.warp(1_704_067_200 + 2 hours);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBalancerValidatorManager
                    .BalancerValidatorManager__SecurityModuleMaxWeightExceeded
                    .selector,
                testSecurityModules[0],
                40,
                30
            )
        );
        vm.prank(testSecurityModules[0]);
        validatorManager.initializeValidatorWeightUpdate(VALIDATION_ID_01, 40);
    }

    function testCompleteValidatorWeightUpdate()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        // Warp to 2024-01-01 02:00:00 to exit the churn period (1 hour)
        vm.warp(1_704_067_200 + 2 hours);

        vm.startPrank(testSecurityModules[0]);
        validatorManager.initializeValidatorWeightUpdate(VALIDATION_ID_01, 40);

        validatorManager.completeValidatorWeightUpdate(
            VALIDATION_ID_01, COMPLETE_VALIDATOR_WEIGHT_UPDATE_MESSAGE_INDEX
        );

        Validator memory validator = validatorManager.getValidator(VALIDATION_ID_01);
        assertEq(validator.weight, 40);
        assert(!validatorManager.isValidatorPendingWeightUpdate(VALIDATION_ID_01));
        (uint64 weight,) = validatorManager.getSecurityModuleWeights(testSecurityModules[0]);
        assertEq(weight, 40);
    }

    function testResendValidatorWeightUpdate()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        // Warp to 2024-01-01 02:00:00 to exit the churn period (1 hour)
        vm.warp(1_704_067_200 + 2 hours);

        vm.startPrank(testSecurityModules[0]);
        validatorManager.initializeValidatorWeightUpdate(VALIDATION_ID_01, 40);

        vm.warp(1_704_067_200 + 3 hours);

        validatorManager.resendValidatorWeightUpdate(VALIDATION_ID_01);
    }

    function testInitializeEndValidation()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        vm.prank(testSecurityModules[0]);
        validatorManager.initializeEndValidation(VALIDATION_ID_01);

        Validator memory validator = validatorManager.getValidator(VALIDATION_ID_01);
        (uint64 weight,) = validatorManager.getSecurityModuleWeights(testSecurityModules[0]);
        assert(validator.status == ValidatorStatus.PendingRemoved);
        assertEq(validator.endedAt, block.timestamp);
        assertEq(validator.weight, 0);
        assertEq(weight, 0);
    }

    function testInitializeEndValidationRevertsIfWrongSecurityModule()
        public
        validatorSetInitialized
        securityModulesSetUp
        validatorRegistrationCompleted
    {
        vm.prank(testSecurityModules[1]);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBalancerValidatorManager
                    .BalancerValidatorManager__ValidatorNotBelongingToSecurityModule
                    .selector,
                VALIDATION_ID_01,
                testSecurityModules[1]
            )
        );
        validatorManager.initializeEndValidation(VALIDATION_ID_01);
    }

    function testCompleteEndValidation()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        vm.prank(testSecurityModules[0]);

        validatorManager.initializeEndValidation(VALIDATION_ID_01);
        validatorManager.completeEndValidation(VALIDATOR_REGISTRATION_EXPIRED_MESSAGE_INDEX);

        Validator memory validator = validatorManager.getValidator(VALIDATION_ID_01);
        bytes32 validationID = validatorManager.registeredValidators(VALIDATOR_NODE_ID_01);
        assert(validator.status == ValidatorStatus.Completed);
        assertEq(validationID, bytes32(0));
    }

    function testCompleteEndValidationExpired()
        public
        validatorSetInitialized
        validatorRegistrationInitialized
    {
        // Warp to 2024-01-03 00:00:00 to expire the validation
        vm.warp(1_704_067_200 + 2 days);

        vm.prank(testSecurityModules[0]);
        validatorManager.completeEndValidation(VALIDATOR_REGISTRATION_EXPIRED_MESSAGE_INDEX);

        Validator memory validator = validatorManager.getValidator(VALIDATION_ID_01);
        assert(validator.status == ValidatorStatus.Invalidated);
        assertEq(validator.startedAt, 0);
        assertEq(validator.endedAt, 0);
    }

    function testGetChurnPeriodSeconds() public view {
        assertEq(validatorManager.getChurnPeriodSeconds(), churnPeriodSeconds);
    }

    function testGetMaximumChurnPercentage() public view {
        assertEq(validatorManager.getMaximumChurnPercentage(), maximumChurnPercentage);
    }

    function testGetCurrentChurnPeriod() public validatorSetInitialized {
        ValidatorChurnPeriod memory churnPeriod = validatorManager.getCurrentChurnPeriod();

        assertEq(churnPeriod.startedAt, 0);
        assertEq(churnPeriod.initialWeight, 0);
        assertEq(churnPeriod.totalWeight, 200);
        assertEq(churnPeriod.churnAmount, 0);
    }

    function testGetSecurityModules() public securityModulesSetUp {
        address[] memory modules = validatorManager.getSecurityModules();
        assertEq(modules.length, 2);
        assertEq(modules[0], testSecurityModules[0]);
        assertEq(modules[1], testSecurityModules[1]);
    }

    function testGetSecurityModuleWeights()
        public
        validatorSetInitialized
        securityModulesSetUp
        validatorRegistrationCompleted
    {
        (uint64 weight, uint64 maxWeight) =
            validatorManager.getSecurityModuleWeights(testSecurityModules[0]);
        assertEq(weight, 20);
        assertEq(maxWeight, 100);

        (weight, maxWeight) = validatorManager.getSecurityModuleWeights(testSecurityModules[1]);
        assertEq(weight, 0);
        assertEq(maxWeight, 100);
    }
}

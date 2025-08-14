// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {DeployBalancerValidatorManager} from
    "../../script/ValidatorManager/DeployBalancerValidatorManager.s.sol";
import {HelperConfig} from "../../script/ValidatorManager/HelperConfig.s.sol";
import {BalancerValidatorManager} from
    "../../src/contracts/ValidatorManager/BalancerValidatorManager.sol";
import {PoASecurityModule} from
    "../../src/contracts/ValidatorManager/SecurityModule/PoASecurityModule.sol";

import {ACP77WarpMessengerTestMock} from "../../src/contracts/mocks/ACP77WarpMessengerTestMock.sol";
import {IBalancerValidatorManager} from
    "../../src/interfaces/ValidatorManager/IBalancerValidatorManager.sol";

import {
    ConversionData,
    InitialValidator,
    PChainOwner,
    Validator,
    ValidatorStatus
} from "@avalabs/icm-contracts/validator-manager/interfaces/IACP99Manager.sol";

import {ValidatorRegistrationInput} from
    "../../src/interfaces/ValidatorManager/IBalancerValidatorManager.sol";
import {IWarpMessenger} from
    "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {Test, console} from "forge-std/Test.sol";

contract BalancerValidatorManagerTest is Test {
    DeployBalancerValidatorManager deployer;
    BalancerValidatorManager validatorManager;
    uint256 validatorManagerOwnerKey;
    address validatorManagerOwnerAddress;
    address vmAddress; // Store VM2 address for test setup
    bytes32 subnetID;
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
    // Node IDs must be exactly 20 bytes
    bytes constant VALIDATOR_NODE_ID_01 = bytes(hex"1234567812345678123456781234567812345678");
    bytes constant VALIDATOR_NODE_ID_02 = bytes(hex"2345678123456781234567812345678123456781");
    bytes constant VALIDATOR_NODE_ID_03 = bytes(hex"3456781234567812345678123456781234567812");
    bytes constant VALIDATOR_01_BLS_PUBLIC_KEY = new bytes(48);
    uint64 constant VALIDATOR_WEIGHT = 20;
    // Validation IDs calculated from 20-byte node IDs
    bytes32 constant VALIDATION_ID_01 =
        0xbf7a1a38fbdfbc95c69a680620bf7651bac6065038ac761cf65c8ed19ac0f1b1;
    bytes32 constant VALIDATION_ID_02 =
        0x0ff9e5c77da268eef8379d3ff1572d16d0fa519fcaa6f10b366c34ce3e97ca5a;
    bytes32 constant VALIDATION_ID_03 =
        0xff7f451c6758256d0b0a32a7e32aef5180693e6e296b329e80a8ee70cfb5f19a;
    uint64 constant DEFAULT_EXPIRY = 1_704_067_200 + 1 days;
    uint64 constant DEFAULT_MAX_WEIGHT = 100;

    function setUp() public {
        deployer = new DeployBalancerValidatorManager();

        HelperConfig helperConfig = new HelperConfig();
        (, validatorManagerOwnerKey, subnetID, churnPeriodSeconds, maximumChurnPercentage) =
            helperConfig.activeNetworkConfig();
        validatorManagerOwnerAddress = vm.addr(validatorManagerOwnerKey);

        testSecurityModules = new address[](2);

        (address validatorManagerAddress, address securityModuleAddress, address _vmAddress) =
            deployer.run(address(0), DEFAULT_MAX_WEIGHT, new bytes[](0));
        validatorManager = BalancerValidatorManager(validatorManagerAddress);
        vmAddress = _vmAddress; // Store for use in tests
        testSecurityModules[0] = securityModuleAddress;
        testSecurityModules[1] =
            address(new PoASecurityModule(validatorManagerAddress, validatorManagerOwnerAddress));

        // Initialize mock with VM2 address (not BalancerValidatorManager)
        ACP77WarpMessengerTestMock warpMessengerTestMock = new ACP77WarpMessengerTestMock(vmAddress);
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
        vm.prank(validatorManagerOwnerAddress);
        PoASecurityModule(testSecurityModules[0]).initiateValidatorRegistration(
            _generateTestValidatorRegistrationInput(), VALIDATOR_WEIGHT
        );
        _;
    }

    modifier validatorRegistrationCompleted() {
        vm.startPrank(validatorManagerOwnerAddress);
        PoASecurityModule(testSecurityModules[0]).initiateValidatorRegistration(
            _generateTestValidatorRegistrationInput(), VALIDATOR_WEIGHT
        );
        PoASecurityModule(testSecurityModules[0]).completeValidatorRegistration(
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
            subnetID: subnetID,
            validatorManagerBlockchainID: ANVIL_CHAIN_ID_HEX,
            validatorManagerAddress: vmAddress, // Use VM2 address, not BalancerValidatorManager
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

    function testInitiateValidatorRegistration() public validatorSetInitialized {
        vm.prank(validatorManagerOwnerAddress);
        PoASecurityModule(testSecurityModules[0]).initiateValidatorRegistration(
            _generateTestValidatorRegistrationInput(), VALIDATOR_WEIGHT
        );

        Validator memory validator = validatorManager.getValidator(VALIDATION_ID_01);
        assertEq(validator.nodeID, VALIDATOR_NODE_ID_01);
        assert(validator.status == ValidatorStatus.PendingAdded);
        assertEq(validator.sentNonce, 0);
        assertEq(validator.weight, VALIDATOR_WEIGHT);
        assertEq(validator.startTime, 0);
        assertEq(validator.endTime, 0);
        (uint64 weight,) = validatorManager.getSecurityModuleWeights(testSecurityModules[0]);
        assertEq(weight, VALIDATOR_WEIGHT);
    }

    function testCompleteValidatorRegistration()
        public
        validatorSetInitialized
        validatorRegistrationInitialized
    {
        vm.prank(validatorManagerOwnerAddress);
        PoASecurityModule(testSecurityModules[0]).completeValidatorRegistration(
            COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX
        );

        Validator memory validator = validatorManager.getValidator(VALIDATION_ID_01);
        assert(validator.status == ValidatorStatus.Active);
        assertEq(validator.startTime, block.timestamp);
    }

    function testInitiateValidatorRemoval()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        vm.prank(validatorManagerOwnerAddress);
        PoASecurityModule(testSecurityModules[0]).initiateValidatorRemoval(VALIDATION_ID_01);

        Validator memory validator = validatorManager.getValidator(VALIDATION_ID_01);
        (uint64 weight,) = validatorManager.getSecurityModuleWeights(testSecurityModules[0]);
        assert(validator.status == ValidatorStatus.PendingRemoved);
        assertEq(validator.endTime, block.timestamp);
        assertEq(validator.weight, 0);
        assertEq(weight, 0);
    }

    function testInitiateValidatorRemovalRevertsIfWrongSecurityModule()
        public
        validatorSetInitialized
        securityModulesSetUp
        validatorRegistrationCompleted
    {
        vm.prank(validatorManagerOwnerAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBalancerValidatorManager
                    .BalancerValidatorManager__ValidatorNotBelongingToSecurityModule
                    .selector,
                VALIDATION_ID_01,
                testSecurityModules[1]
            )
        );
        PoASecurityModule(testSecurityModules[1]).initiateValidatorRemoval(VALIDATION_ID_01);
    }

    function testCompleteValidatorRemoval()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        vm.prank(validatorManagerOwnerAddress);
        PoASecurityModule(testSecurityModules[0]).initiateValidatorRemoval(VALIDATION_ID_01);
        PoASecurityModule(testSecurityModules[0]).completeValidatorRemoval(
            VALIDATOR_REGISTRATION_EXPIRED_MESSAGE_INDEX
        );

        Validator memory validator = validatorManager.getValidator(VALIDATION_ID_01);
        bytes32 validationID = validatorManager.getNodeValidationID(VALIDATOR_NODE_ID_01);
        assert(validator.status == ValidatorStatus.Completed);
        assertEq(validationID, bytes32(0));
    }

    function testCompleteValidatorRemovalExpired()
        public
        validatorSetInitialized
        validatorRegistrationInitialized
    {
        // Warp to 2024-01-03 00:00:00 to expire the validation
        vm.warp(1_704_067_200 + 2 days);

        vm.prank(validatorManagerOwnerAddress);
        PoASecurityModule(testSecurityModules[0]).completeValidatorRemoval(
            VALIDATOR_REGISTRATION_EXPIRED_MESSAGE_INDEX
        );

        Validator memory validator = validatorManager.getValidator(VALIDATION_ID_01);
        assert(validator.status == ValidatorStatus.Invalidated);
        assertEq(validator.startTime, 0);
        assertEq(validator.endTime, 0);
    }
}

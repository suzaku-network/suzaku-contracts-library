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

import {ValidatorChurnPeriod} from
    "../../src/interfaces/ValidatorManager/IBalancerValidatorManager.sol";

import {PoASecurityModule} from
    "../../src/contracts/ValidatorManager/SecurityModule/PoASecurityModule.sol";
import {ValidatorMessages} from "@avalabs/icm-contracts/validator-manager/ValidatorMessages.sol";
import {
    ConversionData,
    InitialValidator,
    PChainOwner,
    Validator,
    ValidatorStatus
} from "@avalabs/icm-contracts/validator-manager/interfaces/IACP99Manager.sol";
import {IWarpMessenger} from
    "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {OwnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable@5.0.2/access/OwnableUpgradeable.sol";
import {Test, console} from "forge-std/Test.sol";

contract BalancerValidatorManagerTest is Test {
    DeployBalancerValidatorManager deployer;
    BalancerValidatorManager validatorManager;
    uint256 validatorManagerOwnerKey;
    address vmAddress;
    address validatorManagerOwnerAddress;
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
    uint64 constant VALIDATOR_WEIGHT = 100_000;
    // Validation IDs calculated dynamically in setUp
    bytes32 VALIDATION_ID_01;
    bytes32 VALIDATION_ID_02;
    bytes32 VALIDATION_ID_03;
    uint64 constant DEFAULT_EXPIRY = 1_704_067_200 + 1 days;
    uint64 constant DEFAULT_MAX_WEIGHT = 2_000_000; // 2 million
    uint64 constant INITIAL_VM_WEIGHT = 1_000_000; // 500000 + 500000

    function setUp() public {
        deployer = new DeployBalancerValidatorManager();

        HelperConfig helperConfig = new HelperConfig();
        (, validatorManagerOwnerKey, subnetID, churnPeriodSeconds, maximumChurnPercentage) =
            helperConfig.activeNetworkConfig();
        validatorManagerOwnerAddress = vm.addr(validatorManagerOwnerKey);

        // Pass the migrated validators (matches warp mock initialize set)
        bytes[] memory migrated = new bytes[](2);
        migrated[0] = VALIDATOR_NODE_ID_02; // 180
        migrated[1] = VALIDATOR_NODE_ID_03; // 20

        // Deploy with address(0) to let the deployer create a PoASecurityModule
        (address validatorManagerAddress, address deployedSecurityModule, address _vmAddress) =
            deployer.run(address(0), DEFAULT_MAX_WEIGHT, migrated);

        // Deploy additional security modules for testing
        testSecurityModules = new address[](3);
        testSecurityModules[0] = deployedSecurityModule;
        testSecurityModules[1] =
            address(new PoASecurityModule(validatorManagerAddress, validatorManagerOwnerAddress));
        testSecurityModules[2] =
            address(new PoASecurityModule(validatorManagerAddress, validatorManagerOwnerAddress));
        vmAddress = _vmAddress;
        validatorManager = BalancerValidatorManager(validatorManagerAddress);

        address[] memory addresses = new address[](1);
        addresses[0] = 0x1234567812345678123456781234567812345678;
        pChainOwner = PChainOwner({threshold: 1, addresses: addresses});

        // Calculate validation IDs
        VALIDATION_ID_01 = _calculateValidationID01();
        VALIDATION_ID_02 = sha256(abi.encodePacked(subnetID, uint32(0))); // Initial validator index 0
        VALIDATION_ID_03 = sha256(abi.encodePacked(subnetID, uint32(1))); // Initial validator index 1

        // Warp to 2024-01-01 00:00:00
        vm.warp(1_704_067_200);
    }

    modifier validatorSetInitialized() {
        // Deployer already initializes the VM; tolerate duplicate calls here
        try validatorManager.initializeValidatorSet(
            _generateTestConversionData(), INITIALIZE_VALIDATOR_SET_MESSAGE_INDEX
        ) {} catch {}
        _;
    }

    modifier securityModulesSetUp() {
        vm.prank(validatorManagerOwnerAddress);
        validatorManager.setUpSecurityModule(testSecurityModules[1], DEFAULT_MAX_WEIGHT);
        _;
    }

    modifier validatorRegistrationInitialized() {
        vm.prank(testSecurityModules[0]);
        validatorManager.initiateValidatorRegistration(
            VALIDATOR_NODE_ID_01,
            VALIDATOR_01_BLS_PUBLIC_KEY,
            pChainOwner,
            pChainOwner,
            VALIDATOR_WEIGHT
        );
        _;
    }

    modifier validatorRegistrationCompleted() {
        vm.startPrank(testSecurityModules[0]);
        validatorManager.initiateValidatorRegistration(
            VALIDATOR_NODE_ID_01,
            VALIDATOR_01_BLS_PUBLIC_KEY,
            pChainOwner,
            pChainOwner,
            VALIDATOR_WEIGHT
        );
        validatorManager.completeValidatorRegistration(
            COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX
        );
        vm.stopPrank();
        _;
    }

    function _generateTestConversionData() private view returns (ConversionData memory) {
        InitialValidator[] memory initialValidators = new InitialValidator[](2);
        initialValidators[0] = InitialValidator({
            nodeID: VALIDATOR_NODE_ID_02,
            weight: 500_000,
            blsPublicKey: VALIDATOR_01_BLS_PUBLIC_KEY
        });
        initialValidators[1] = InitialValidator({
            nodeID: VALIDATOR_NODE_ID_03,
            weight: 500_000,
            blsPublicKey: VALIDATOR_01_BLS_PUBLIC_KEY
        });
        ConversionData memory conversionData = ConversionData({
            subnetID: subnetID,
            validatorManagerBlockchainID: ANVIL_CHAIN_ID_HEX,
            validatorManagerAddress: vmAddress, // This should be the VM2 address
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
                INITIAL_VM_WEIGHT + VALIDATOR_WEIGHT
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
        validatorManager.initiateValidatorRegistration(
            VALIDATOR_NODE_ID_01,
            VALIDATOR_01_BLS_PUBLIC_KEY,
            pChainOwner,
            pChainOwner,
            VALIDATOR_WEIGHT
        );

        Validator memory validator = validatorManager.getValidator(VALIDATION_ID_01);
        assertEq(validator.nodeID, VALIDATOR_NODE_ID_01);
        assert(validator.status == ValidatorStatus.PendingAdded);
        assertEq(validator.sentNonce, 0);
        assertEq(validator.weight, VALIDATOR_WEIGHT);
        assertEq(validator.startTime, 0);
        assertEq(validator.endTime, 0);
        (uint64 weight,) = validatorManager.getSecurityModuleWeights(testSecurityModules[0]);
        assertEq(weight, INITIAL_VM_WEIGHT + VALIDATOR_WEIGHT);
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
        assertEq(validator.startTime, block.timestamp);
    }

    function testInitializeValidatorWeightUpdate()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        // Warp to 2024-01-01 02:00:00 to exit the churn period (1 hour)
        vm.warp(1_704_067_200 + 2 hours);

        vm.prank(testSecurityModules[0]);
        validatorManager.initiateValidatorWeightUpdate(VALIDATION_ID_01, 2 * VALIDATOR_WEIGHT);

        Validator memory validator = validatorManager.getValidator(VALIDATION_ID_01);
        assertEq(validator.weight, 2 * VALIDATOR_WEIGHT);
        assertEq(validator.sentNonce, 1);
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
        validatorManager.initiateValidatorWeightUpdate(VALIDATION_ID_01, 2 * VALIDATOR_WEIGHT);
    }

    function testInitializeValidatorWeightUpdateRevertsIfPendingUpdate()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        // Warp to 2024-01-01 02:00:00 to exit the churn period (1 hour)
        vm.warp(1_704_067_200 + 2 hours);

        vm.startPrank(testSecurityModules[0]);
        validatorManager.initiateValidatorWeightUpdate(VALIDATION_ID_01, 2 * VALIDATOR_WEIGHT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBalancerValidatorManager.BalancerValidatorManager__PendingWeightUpdate.selector,
                VALIDATION_ID_01
            )
        );
        validatorManager.initiateValidatorWeightUpdate(VALIDATION_ID_01, 50);
    }

    function testInitializeValidatorWeightUpdateRevertsIfExceedsMaxWeight()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        // Lower the max weight of the security module (but high enough to not fail immediately)
        vm.prank(validatorManagerOwnerAddress);
        validatorManager.setUpSecurityModule(testSecurityModules[0], 1_100_000);

        // Warp to 2024-01-01 02:00:00 to exit the churn period (1 hour)
        vm.warp(1_704_067_200 + 2 hours);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBalancerValidatorManager
                    .BalancerValidatorManager__SecurityModuleMaxWeightExceeded
                    .selector,
                testSecurityModules[0],
                1_200_000, // 1_100_000 + 2 * VALIDATOR_WEIGHT - VALIDATOR_WEIGHT
                1_100_000
            )
        );
        vm.prank(testSecurityModules[0]);
        validatorManager.initiateValidatorWeightUpdate(VALIDATION_ID_01, 2 * VALIDATOR_WEIGHT);
    }

    function testCompleteValidatorWeightUpdate()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        // Warp to 2024-01-01 02:00:00 to exit the churn period (1 hour)
        vm.warp(1_704_067_200 + 2 hours);

        vm.startPrank(testSecurityModules[0]);
        validatorManager.initiateValidatorWeightUpdate(VALIDATION_ID_01, 2 * VALIDATOR_WEIGHT);

        validatorManager.completeValidatorWeightUpdate(
            COMPLETE_VALIDATOR_WEIGHT_UPDATE_MESSAGE_INDEX
        );

        Validator memory validator = validatorManager.getValidator(VALIDATION_ID_01);
        assertEq(validator.weight, 2 * VALIDATOR_WEIGHT);
        assert(!validatorManager.isValidatorPendingWeightUpdate(VALIDATION_ID_01));
        (uint64 weight,) = validatorManager.getSecurityModuleWeights(testSecurityModules[0]);
        assertEq(weight, INITIAL_VM_WEIGHT + 2 * VALIDATOR_WEIGHT);
    }

    function testResendValidatorWeightUpdate()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        // Warp to 2024-01-01 02:00:00 to exit the churn period (1 hour)
        vm.warp(1_704_067_200 + 2 hours);

        vm.startPrank(testSecurityModules[0]);
        validatorManager.initiateValidatorWeightUpdate(VALIDATION_ID_01, 2 * VALIDATOR_WEIGHT);

        vm.warp(1_704_067_200 + 3 hours);

        validatorManager.resendValidatorWeightUpdate(VALIDATION_ID_01);
    }

    function testInitializeEndValidation()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        vm.prank(testSecurityModules[0]);
        validatorManager.initiateValidatorRemoval(VALIDATION_ID_01);

        Validator memory validator = validatorManager.getValidator(VALIDATION_ID_01);
        (uint64 weight,) = validatorManager.getSecurityModuleWeights(testSecurityModules[0]);
        assert(validator.status == ValidatorStatus.PendingRemoved);
        assertEq(validator.endTime, block.timestamp);
        assertEq(validator.weight, 0);
        assertEq(weight, INITIAL_VM_WEIGHT);
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
        validatorManager.initiateValidatorRemoval(VALIDATION_ID_01);
    }

    function testCompleteEndValidation()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        vm.startPrank(testSecurityModules[0]);
        validatorManager.initiateValidatorRemoval(VALIDATION_ID_01);
        validatorManager.completeValidatorRemoval(VALIDATOR_REGISTRATION_EXPIRED_MESSAGE_INDEX);
        vm.stopPrank();

        Validator memory validator = validatorManager.getValidator(VALIDATION_ID_01);
        bytes32 validationID = validatorManager.getNodeValidationID(VALIDATOR_NODE_ID_01);
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
        validatorManager.completeValidatorRemoval(VALIDATOR_REGISTRATION_EXPIRED_MESSAGE_INDEX);

        Validator memory validator = validatorManager.getValidator(VALIDATION_ID_01);
        assert(validator.status == ValidatorStatus.Invalidated);
        assertEq(validator.startTime, 0);
        assertEq(validator.endTime, 0);

        // Expired validators that were invalidated have their weight subtracted
        (uint64 weight,) = validatorManager.getSecurityModuleWeights(testSecurityModules[0]);
        assertEq(weight, INITIAL_VM_WEIGHT); // returns to pre-registration weight
    }

    function testGetChurnPeriodSeconds() public view {
        assertEq(validatorManager.getChurnPeriodSeconds(), churnPeriodSeconds);
    }

    function testGetMaximumChurnPercentage() public view {
        assertEq(validatorManager.getMaximumChurnPercentage(), maximumChurnPercentage);
    }

    function testGetCurrentChurnPeriod() public validatorSetInitialized {
        ValidatorChurnPeriod memory churnPeriod = validatorManager.getCurrentChurnPeriod();

        assertEq(churnPeriod.startTime, 0);
        assertEq(churnPeriod.initialWeight, 0);
        assertEq(churnPeriod.totalWeight, 1_000_000);
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
        assertEq(weight, INITIAL_VM_WEIGHT + VALIDATOR_WEIGHT);
        assertEq(maxWeight, DEFAULT_MAX_WEIGHT);

        (weight, maxWeight) = validatorManager.getSecurityModuleWeights(testSecurityModules[1]);
        assertEq(weight, 0);
        assertEq(maxWeight, DEFAULT_MAX_WEIGHT);
    }

    function testGetValidatorSecurityModule()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        address securityModule = validatorManager.getValidatorSecurityModule(VALIDATION_ID_01);
        assertEq(securityModule, testSecurityModules[0]);

        // Test unregistered validator
        bytes32 unknownValidationID = keccak256("unknown");
        address unknownModule = validatorManager.getValidatorSecurityModule(unknownValidationID);
        assertEq(unknownModule, address(0));
    }

    function testIsValidatorPendingWeightUpdate()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        // Initially no pending update
        assertFalse(validatorManager.isValidatorPendingWeightUpdate(VALIDATION_ID_01));

        // Warp to exit churn period
        vm.warp(1_704_067_200 + 2 hours);

        // Initiate weight update
        vm.prank(testSecurityModules[0]);
        validatorManager.initiateValidatorWeightUpdate(VALIDATION_ID_01, 2 * VALIDATOR_WEIGHT);

        // Now should have pending update
        assertTrue(validatorManager.isValidatorPendingWeightUpdate(VALIDATION_ID_01));

        // Complete the update
        vm.prank(testSecurityModules[0]);
        validatorManager.completeValidatorWeightUpdate(
            COMPLETE_VALIDATOR_WEIGHT_UPDATE_MESSAGE_INDEX
        );

        // No longer pending
        assertFalse(validatorManager.isValidatorPendingWeightUpdate(VALIDATION_ID_01));
    }

    function testResendRegisterValidatorMessage()
        public
        validatorSetInitialized
        validatorRegistrationInitialized
    {
        // Anyone can call resend
        vm.prank(makeAddr("randomUser"));
        validatorManager.resendRegisterValidatorMessage(VALIDATION_ID_01);
    }

    function testResendValidatorRemovalMessage()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        // First initiate removal
        vm.prank(testSecurityModules[0]);
        validatorManager.initiateValidatorRemoval(VALIDATION_ID_01);

        // Anyone can resend
        vm.prank(makeAddr("randomUser"));
        validatorManager.resendValidatorRemovalMessage(VALIDATION_ID_01);
    }

    function testL1TotalWeight() public validatorSetInitialized validatorRegistrationCompleted {
        // Initial weight from validator set initialization (500_000 + 500_000) + new validator (100_000)
        uint64 totalWeight = validatorManager.l1TotalWeight();
        assertEq(totalWeight, 1_100_000);
    }

    function testSubnetID() public view {
        bytes32 retrievedSubnetID = validatorManager.subnetID();
        assertEq(retrievedSubnetID, subnetID);
    }

    function testRemoveSecurityModule() public securityModulesSetUp {
        // First verify module is registered
        (uint64 weight, uint64 maxWeight) =
            validatorManager.getSecurityModuleWeights(testSecurityModules[1]);
        assertEq(weight, 0);
        assertEq(maxWeight, DEFAULT_MAX_WEIGHT);

        // Remove by setting maxWeight to 0
        vm.prank(validatorManagerOwnerAddress);
        validatorManager.setUpSecurityModule(testSecurityModules[1], 0);

        // Verify module is removed
        address[] memory modules = validatorManager.getSecurityModules();
        assertEq(modules.length, 1);
        assertEq(modules[0], testSecurityModules[0]);

        (weight, maxWeight) = validatorManager.getSecurityModuleWeights(testSecurityModules[1]);
        assertEq(weight, 0);
        assertEq(maxWeight, 0);
    }

    function testCannotRemoveSecurityModuleWithActiveValidators()
        public
        validatorSetInitialized
        validatorRegistrationCompleted
    {
        // Try to remove module with active validators
        vm.prank(validatorManagerOwnerAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBalancerValidatorManager
                    .BalancerValidatorManager__SecurityModuleNewMaxWeightLowerThanCurrentWeight
                    .selector,
                testSecurityModules[0],
                0,
                INITIAL_VM_WEIGHT + VALIDATOR_WEIGHT
            )
        );
        validatorManager.setUpSecurityModule(testSecurityModules[0], 0);
    }

    // Helper function to calculate validation ID for NODE_ID_01
    function _calculateValidationID01() internal view returns (bytes32) {
        ValidatorMessages.ValidationPeriod memory period = ValidatorMessages.ValidationPeriod({
            subnetID: subnetID,
            nodeID: VALIDATOR_NODE_ID_01,
            blsPublicKey: VALIDATOR_01_BLS_PUBLIC_KEY,
            registrationExpiry: DEFAULT_EXPIRY,
            remainingBalanceOwner: pChainOwner,
            disableOwner: pChainOwner,
            weight: VALIDATOR_WEIGHT
        });
        (bytes32 validationID,) = ValidatorMessages.packRegisterL1ValidatorMessage(period);
        return validationID;
    }
}

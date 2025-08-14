// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {MigratePoAToBalancer} from "../../script/ValidatorManager/MigratePoAToBalancer.s.sol";
import {ExtractValidators} from "../../script/ValidatorManager/ExtractValidators.s.sol";
import {BalancerValidatorManager} from
    "../../src/contracts/ValidatorManager/BalancerValidatorManager.sol";
import {PoASecurityModule} from
    "../../src/contracts/ValidatorManager/SecurityModule/PoASecurityModule.sol";
import {
    ValidatorManager as VM2,
    ValidatorManagerSettings as VM2Settings
} from "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";
import {IValidatorManagerExternalOwnable} from "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManagerExternalOwnable.sol";
import {
    ConversionData,
    InitialValidator,
    PChainOwner,
    Validator,
    ValidatorStatus
} from "@avalabs/icm-contracts/validator-manager/interfaces/IACP99Manager.sol";
import {ICMInitializable} from "@avalabs/icm-contracts/utilities/ICMInitializable.sol";
import {PoAManager} from "@avalabs/icm-contracts/validator-manager/PoAManager.sol";
import {ACP77WarpMessengerTestMock} from "../../src/contracts/mocks/ACP77WarpMessengerTestMock.sol";
import {Test, console} from "forge-std/Test.sol";

contract MigratePoAToBalancerTest is Test {
    MigratePoAToBalancer migrator;
    ExtractValidators extractor;
    
    address constant WARP_MESSENGER_ADDR = 0x0200000000000000000000000000000000000005;
    bytes32 constant TEST_SUBNET_ID = 0x5f4c8570d996184af03052f1b3acc1c7b432b0a41e7480de1b72d4c6f5983eb9;
    bytes32 constant ANVIL_CHAIN_ID_HEX = 0x7a69000000000000000000000000000000000000000000000000000000000000;
    uint32 constant INITIALIZE_VALIDATOR_SET_MESSAGE_INDEX = 2;
    uint64 constant CHURN_PERIOD = 1 hours;
    uint8 constant MAX_CHURN_PERCENTAGE = 20;
    uint64 constant DEFAULT_WEIGHT = 100;
    uint64 constant SECURITY_MODULE_MAX_WEIGHT = 1000;
    
    // Test validator node IDs (20 bytes each) - matching mock expectations
    bytes constant NODE_ID_1 = hex"2345678123456781234567812345678123456781";
    bytes constant NODE_ID_2 = hex"3456781234567812345678123456781234567812";
    bytes constant NODE_ID_3 = hex"4567812345678123456781234567812345678123";
    
    address owner;
    address existingVM;
    address existingPoAManager;
    
    function setUp() public {
        owner = makeAddr("owner");
        
        // Deploy mock warp messenger
        ACP77WarpMessengerTestMock warpMock = new ACP77WarpMessengerTestMock(address(0));
        vm.etch(WARP_MESSENGER_ADDR, address(warpMock).code);
        
        // Deploy existing ValidatorManager with some validators
        _deployExistingSetup();
        
        // Deploy migration scripts
        migrator = new MigratePoAToBalancer();
        extractor = new ExtractValidators();
    }
    
    function _deployExistingSetup() internal {
        // Deploy existing ValidatorManager
        VM2Settings memory settings = VM2Settings({
            admin: owner,
            subnetID: TEST_SUBNET_ID,
            churnPeriodSeconds: CHURN_PERIOD,
            maximumChurnPercentage: MAX_CHURN_PERCENTAGE
        });
        
        vm.startPrank(owner);
        VM2 vmImpl = new VM2(ICMInitializable.Allowed);
        existingVM = address(vmImpl);
        VM2(existingVM).initialize(settings);
        
        // Deploy PoAManager to manage it
        existingPoAManager = address(new PoAManager(owner, IValidatorManagerExternalOwnable(existingVM)));
        VM2(existingVM).transferOwnership(existingPoAManager);
        
        // Update warp mock with the VM address
        ACP77WarpMessengerTestMock warpMock = new ACP77WarpMessengerTestMock(existingVM);
        vm.etch(WARP_MESSENGER_ADDR, address(warpMock).code);
        
        // Initialize validator set with test validators
        _initializeValidatorSet();
        
        vm.stopPrank();
    }
    
    function _initializeValidatorSet() internal {
        InitialValidator[] memory initialValidators = new InitialValidator[](2);
        
        // Setup initial validators matching mock expectations
        initialValidators[0] = InitialValidator({
            nodeID: NODE_ID_1,
            blsPublicKey: new bytes(48),
            weight: 180
        });
        
        initialValidators[1] = InitialValidator({
            nodeID: NODE_ID_2,
            blsPublicKey: new bytes(48),
            weight: 20
        });
        
        ConversionData memory conversionData = ConversionData({
            subnetID: TEST_SUBNET_ID,
            validatorManagerBlockchainID: ANVIL_CHAIN_ID_HEX,
            validatorManagerAddress: existingVM,
            initialValidators: initialValidators
        });
        
        // Call initializeValidatorSet directly on VM2
        VM2(existingVM).initializeValidatorSet(conversionData, INITIALIZE_VALIDATOR_SET_MESSAGE_INDEX);
    }
    
    function testExtractValidators() public view {
        // Test the extractor to see what validators we have
        bytes[] memory nodeIds = new bytes[](3);
        nodeIds[0] = NODE_ID_1;
        nodeIds[1] = NODE_ID_2;
        nodeIds[2] = NODE_ID_3; // This one shouldn't exist
        
        bytes[] memory activeValidators = extractor.extractActive(existingVM, nodeIds);
        
        // Should find 2 active validators
        assertEq(activeValidators.length, 2, "Should have 2 active validators");
        assertEq(activeValidators[0], NODE_ID_1, "First validator should be NODE_ID_1");
        assertEq(activeValidators[1], NODE_ID_2, "Second validator should be NODE_ID_2");
    }
    
    function testMigratePoAToBalancer() public {
        // Since we can't do a real P-Chain conversion in tests, we'll manually set up
        // the scenario that would exist after conversion
        
        // 1. Deploy new VM2
        vm.startPrank(owner);
        VM2Settings memory settings = VM2Settings({
            admin: owner,
            subnetID: TEST_SUBNET_ID,
            churnPeriodSeconds: CHURN_PERIOD,
            maximumChurnPercentage: MAX_CHURN_PERCENTAGE
        });
        
        VM2 newVMImpl = new VM2(ICMInitializable.Allowed);
        address newVM = address(newVMImpl);
        VM2(newVM).initialize(settings);
        
        // 2. Initialize validator set in new VM (simulating P-Chain conversion)
        // Update warp mock to work with new VM
        ACP77WarpMessengerTestMock warpMock = new ACP77WarpMessengerTestMock(newVM);
        vm.etch(WARP_MESSENGER_ADDR, address(warpMock).code);
        
        InitialValidator[] memory initialValidators = new InitialValidator[](2);
        initialValidators[0] = InitialValidator({
            nodeID: NODE_ID_1,
            blsPublicKey: new bytes(48),
            weight: 180
        });
        initialValidators[1] = InitialValidator({
            nodeID: NODE_ID_2,
            blsPublicKey: new bytes(48),
            weight: 20
        });
        
        ConversionData memory conversionData = ConversionData({
            subnetID: TEST_SUBNET_ID,
            validatorManagerBlockchainID: ANVIL_CHAIN_ID_HEX,
            validatorManagerAddress: newVM,
            initialValidators: initialValidators
        });
        
        VM2(newVM).initializeValidatorSet(conversionData, INITIALIZE_VALIDATOR_SET_MESSAGE_INDEX);
        
        // 3. Deploy BalancerValidatorManager
        BalancerValidatorManager balancerImpl = new BalancerValidatorManager();
        address balancer = address(balancerImpl);
        
        // 4. Deploy PoASecurityModule
        address securityModule = address(new PoASecurityModule(balancer, owner));
        
        // 5. Transfer VM ownership to Balancer
        VM2(newVM).transferOwnership(balancer);
        
        // 6. Prepare list of validators to migrate
        bytes[] memory migratedValidators = new bytes[](2);
        migratedValidators[0] = NODE_ID_1;
        migratedValidators[1] = NODE_ID_2;
        
        // 7. Initialize BalancerValidatorManager
        BalancerValidatorManagerSettings memory balancerSettings = BalancerValidatorManagerSettings({
            baseSettings: ValidatorManagerSettings({
                subnetID: TEST_SUBNET_ID,
                churnPeriodSeconds: CHURN_PERIOD,
                maximumChurnPercentage: MAX_CHURN_PERCENTAGE
            }),
            initialOwner: owner,
            initialSecurityModule: securityModule,
            initialSecurityModuleMaxWeight: SECURITY_MODULE_MAX_WEIGHT,
            migratedValidators: migratedValidators
        });
        
        BalancerValidatorManager(balancer).initialize(balancerSettings, newVM);
        
        vm.stopPrank();
        
        // Verify deployment
        assertTrue(balancer != address(0), "Balancer should be deployed");
        assertTrue(securityModule != address(0), "Security module should be deployed");
        assertTrue(newVM != address(0), "New VM should be deployed");
        
        // Verify the balancer owns the new VM
        assertEq(VM2(newVM).owner(), balancer, "Balancer should own the new VM");
        
        // Verify the security module is registered
        BalancerValidatorManager balancerVM = BalancerValidatorManager(balancer);
        address[] memory modules = balancerVM.getSecurityModules();
        assertEq(modules.length, 1, "Should have one security module");
        assertEq(modules[0], securityModule, "Security module should be registered");
        
        // Verify security module weight
        (uint64 weight, uint64 maxWeight) = balancerVM.getSecurityModuleWeights(securityModule);
        assertEq(maxWeight, SECURITY_MODULE_MAX_WEIGHT, "Max weight should match");
        assertEq(weight, 200, "Current weight should be sum of migrated validators (180 + 20)");
        
        // Verify validators are associated with the security module
        bytes32 validationId1 = balancerVM.getNodeValidationID(NODE_ID_1);
        bytes32 validationId2 = balancerVM.getNodeValidationID(NODE_ID_2);
        
        assertEq(
            balancerVM.getValidatorSecurityModule(validationId1),
            securityModule,
            "Validator 1 should belong to security module"
        );
        assertEq(
            balancerVM.getValidatorSecurityModule(validationId2),
            securityModule,
            "Validator 2 should belong to security module"
        );
    }
    
    function testMigrationWithNoValidators() public {
        // Create a new empty VM
        VM2Settings memory settings = VM2Settings({
            admin: owner,
            subnetID: TEST_SUBNET_ID,
            churnPeriodSeconds: CHURN_PERIOD,
            maximumChurnPercentage: MAX_CHURN_PERCENTAGE
        });
        
        vm.startPrank(owner);
        VM2 emptyVM = new VM2(ICMInitializable.Allowed);
        emptyVM.initialize(settings);
        vm.stopPrank();
        
        bytes[] memory emptyNodeIds = new bytes[](0);
        
        // Should revert with no active validators
        vm.expectRevert(MigratePoAToBalancer.NoActiveValidatorsFound.selector);
        migrator.run(
            address(emptyVM),
            address(0),
            emptyNodeIds,
            SECURITY_MODULE_MAX_WEIGHT
        );
    }
}
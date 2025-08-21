// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {BalancerMigrationConfig} from "../../script/ValidatorManager/BalancerConfigTypes.s.sol";
import {MigratePoAToBalancer} from "../../script/ValidatorManager/ExecuteMigratePoAToBalancer.s.sol";
import {ExtractValidators} from "../../script/ValidatorManager/ExtractValidators.s.sol";

import {BalancerValidatorManager} from
    "../../src/contracts/ValidatorManager/BalancerValidatorManager.sol";
import {PoASecurityModule} from
    "../../src/contracts/ValidatorManager/SecurityModule/PoASecurityModule.sol";

import {ACP77WarpMessengerTestMock} from "../../src/contracts/mocks/ACP77WarpMessengerTestMock.sol";
import {ICMInitializable} from "@avalabs/icm-contracts/utilities/ICMInitializable.sol";
import {PoAManager} from "@avalabs/icm-contracts/validator-manager/PoAManager.sol";
import {
    ValidatorManager,
    ValidatorManagerSettings as VMSettings
} from "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";
import {
    ConversionData,
    InitialValidator,
    PChainOwner,
    Validator,
    ValidatorStatus
} from "@avalabs/icm-contracts/validator-manager/interfaces/IACP99Manager.sol";
import {IValidatorManagerExternalOwnable} from
    "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManagerExternalOwnable.sol";

import {Test, console} from "forge-std/Test.sol";

contract MigratePoAToBalancerTest is Test {
    MigratePoAToBalancer migrator;
    ExtractValidators extractor;

    address constant WARP_MESSENGER_ADDR = 0x0200000000000000000000000000000000000005;
    bytes32 constant TEST_SUBNET_ID =
        0x5f4c8570d996184af03052f1b3acc1c7b432b0a41e7480de1b72d4c6f5983eb9;
    bytes32 constant ANVIL_CHAIN_ID_HEX =
        0x7a69000000000000000000000000000000000000000000000000000000000000;
    uint32 constant INITIALIZE_VALIDATOR_SET_MESSAGE_INDEX = 2;
    uint64 constant CHURN_PERIOD = 1 hours;
    uint8 constant MAX_CHURN_PERCENTAGE = 20;
    uint64 constant DEFAULT_WEIGHT = 100;
    uint64 constant SECURITY_MODULE_MAX_WEIGHT = 1000;

    // Test validator node IDs (20 bytes each) - matching mock expectations
    bytes constant NODE_ID_1 = hex"2345678123456781234567812345678123456781";
    bytes constant NODE_ID_2 = hex"3456781234567812345678123456781234567812";
    bytes constant NODE_ID_3 = hex"4567812345678123456781234567812345678123";

    // Keys used by the migration script broadcasts
    uint256 constant PROXY_ADMIN_OWNER_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // anvil[0]
    uint256 constant VALIDATOR_MANAGER_OWNER_KEY =
        0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d; // anvil[1]

    address owner;
    address validatorManager;
    address poaManager;

    function setUp() public {
        // The PoAManager owner must match the key we broadcast with in the migration script
        owner = vm.addr(VALIDATOR_MANAGER_OWNER_KEY);

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
        VMSettings memory settings = VMSettings({
            admin: owner,
            subnetID: TEST_SUBNET_ID,
            churnPeriodSeconds: CHURN_PERIOD,
            maximumChurnPercentage: MAX_CHURN_PERCENTAGE
        });

        vm.startPrank(owner);
        ValidatorManager vmImpl = new ValidatorManager(ICMInitializable.Allowed);
        validatorManager = address(vmImpl);
        ValidatorManager(validatorManager).initialize(settings);

        // Deploy PoAManager to manage it
        poaManager =
            address(new PoAManager(owner, IValidatorManagerExternalOwnable(validatorManager)));
        ValidatorManager(validatorManager).transferOwnership(poaManager);

        // Update warp mock with the VM address
        ACP77WarpMessengerTestMock warpMock = new ACP77WarpMessengerTestMock(validatorManager);
        vm.etch(WARP_MESSENGER_ADDR, address(warpMock).code);

        // Initialize validator set with test validators
        _initializeValidatorSet();

        vm.stopPrank();
    }

    function _initializeValidatorSet() internal {
        InitialValidator[] memory initialValidators = new InitialValidator[](2);

        // Setup initial validators matching mock expectations
        initialValidators[0] =
            InitialValidator({nodeID: NODE_ID_1, blsPublicKey: new bytes(48), weight: 180});

        initialValidators[1] =
            InitialValidator({nodeID: NODE_ID_2, blsPublicKey: new bytes(48), weight: 20});

        ConversionData memory conversionData = ConversionData({
            subnetID: TEST_SUBNET_ID,
            validatorManagerBlockchainID: ANVIL_CHAIN_ID_HEX,
            validatorManagerAddress: validatorManager,
            initialValidators: initialValidators
        });

        // Call initializeValidatorSet directly on ValidatorManager
        ValidatorManager(validatorManager).initializeValidatorSet(
            conversionData, INITIALIZE_VALIDATOR_SET_MESSAGE_INDEX
        );
    }

    function testExtractValidators() public view {
        // Test the extractor to see what validators we have
        bytes[] memory nodeIds = new bytes[](3);
        nodeIds[0] = NODE_ID_1;
        nodeIds[1] = NODE_ID_2;
        nodeIds[2] = NODE_ID_3; // This one shouldn't exist

        bytes[] memory activeValidators = extractor.extractActive(validatorManager, nodeIds);

        // Should find 2 active validators
        assertEq(activeValidators.length, 2, "Should have 2 active validators");
        assertEq(activeValidators[0], NODE_ID_1, "First validator should be NODE_ID_1");
        assertEq(activeValidators[1], NODE_ID_2, "Second validator should be NODE_ID_2");
    }

    function testMigratePoAToBalancer() public {
        // Build migratedValidators so that sum(weight) == ValidatorManager(validatorManager).l1TotalWeight()
        bytes[] memory nodeIds = new bytes[](3);
        nodeIds[0] = NODE_ID_1;
        nodeIds[1] = NODE_ID_2;
        nodeIds[2] = NODE_ID_3; // should be ignored
        bytes[] memory migratedValidators =
            extractor.extractActiveOrPendingAdded(validatorManager, nodeIds);

        // Prepare config for the migration script
        BalancerMigrationConfig memory cfg = BalancerMigrationConfig({
            proxyAddress: address(0), // unused by this script
            validatorManagerProxy: validatorManager,
            poaManager: poaManager,
            initialSecurityModuleMaxWeight: SECURITY_MODULE_MAX_WEIGHT,
            migratedValidators: migratedValidators,
            proxyAdminOwnerAddress: vm.addr(PROXY_ADMIN_OWNER_KEY),
            validatorManagerOwnerAddress: owner,
            subnetID: TEST_SUBNET_ID,
            churnPeriodSeconds: CHURN_PERIOD,
            maximumChurnPercentage: MAX_CHURN_PERCENTAGE
        });

        // Execute migration
        MigratePoAToBalancer _migrator = new MigratePoAToBalancer();
        (address balancerProxy, address poaSecurityModule, address vmAddress) = _migrator
            .executeMigratePoAToBalancer(cfg, PROXY_ADMIN_OWNER_KEY, VALIDATOR_MANAGER_OWNER_KEY);

        // ValidatorManager ownership moved to Balancer
        assertEq(vmAddress, validatorManager, "returned VM address should match");
        assertEq(
            ValidatorManager(vmAddress).owner(),
            balancerProxy,
            "ValidatorManager owner must be Balancer"
        );

        // Balancer registered the PoA module
        BalancerValidatorManager bal = BalancerValidatorManager(balancerProxy);
        address[] memory modules = bal.getSecurityModules();
        assertEq(modules.length, 1, "Should have one security module");
        assertEq(modules[0], poaSecurityModule, "Security module should be registered");

        // Security module weights
        (uint64 curWeight, uint64 maxWeight) = bal.getSecurityModuleWeights(poaSecurityModule);
        assertEq(maxWeight, SECURITY_MODULE_MAX_WEIGHT, "Max weight should match");
        assertEq(
            curWeight,
            ValidatorManager(validatorManager).l1TotalWeight(),
            "Module weight must equal VM total"
        );

        // Validators map to the PoA module
        bytes32 validationId1 = bal.getNodeValidationID(NODE_ID_1);
        bytes32 validationId2 = bal.getNodeValidationID(NODE_ID_2);
        assertEq(
            bal.getValidatorSecurityModule(validationId1),
            poaSecurityModule,
            "Validator 1 should belong to security module"
        );
        assertEq(
            bal.getValidatorSecurityModule(validationId2),
            poaSecurityModule,
            "Validator 2 should belong to security module"
        );
    }

    function testMigratePoAToBalancer_allValidatorsPlusUnknown_setsZeroKey() public {
        // Build list manually with an unknown third node
        bytes[] memory migrated = new bytes[](3);
        migrated[0] = NODE_ID_1;
        migrated[1] = NODE_ID_2;
        migrated[2] = hex"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"; // unknown

        BalancerMigrationConfig memory cfg = BalancerMigrationConfig({
            proxyAddress: address(0),
            validatorManagerProxy: validatorManager,
            poaManager: poaManager,
            initialSecurityModuleMaxWeight: SECURITY_MODULE_MAX_WEIGHT,
            migratedValidators: migrated,
            proxyAdminOwnerAddress: vm.addr(PROXY_ADMIN_OWNER_KEY),
            validatorManagerOwnerAddress: owner,
            subnetID: TEST_SUBNET_ID,
            churnPeriodSeconds: CHURN_PERIOD,
            maximumChurnPercentage: MAX_CHURN_PERCENTAGE
        });

        // Rejects unknown nodeIDs
        vm.expectRevert(bytes("migrated nodeID not registered"));
        migrator.executeMigratePoAToBalancer(
            cfg, PROXY_ADMIN_OWNER_KEY, VALIDATOR_MANAGER_OWNER_KEY
        );
    }
}

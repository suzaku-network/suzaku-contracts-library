// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {BalancerMigrationConfig} from "../../script/ValidatorManager/BalancerConfigTypes.s.sol";
import {MigratePoAToBalancer} from "../../script/ValidatorManager/ExecuteMigratePoAToBalancer.s.sol";

import {ExecutePoAValidatorManager} from
    "../../script/ValidatorManager/ExecutePoAValidatorManager.s.sol";
import {ExtractValidators} from "../../script/ValidatorManager/ExtractValidators.s.sol";

import {BalancerValidatorManager} from
    "../../src/contracts/ValidatorManager/BalancerValidatorManager.sol";
import {PoASecurityModule} from
    "../../src/contracts/ValidatorManager/SecurityModule/PoASecurityModule.sol";

import {ACP77WarpMessengerTestMock} from "../../src/contracts/mocks/ACP77WarpMessengerTestMock.sol";
import {ICMInitializable} from "@avalabs/icm-contracts/utilities/ICMInitializable.sol";
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
import {IPoAManager} from "@avalabs/icm-contracts/validator-manager/interfaces/IPoAManager.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts@5.0.2/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Test, console} from "forge-std/Test.sol";

// V2 implementation for upgradeability tests: same storage layout, adds one new function
contract BalancerValidatorManagerV2 is BalancerValidatorManager {
    function version() external pure returns (string memory) {
        return "v2";
    }
}

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
    uint64 constant SECURITY_MODULE_MAX_WEIGHT = 2_000_000; // 2 million for testing

    // Test validator node IDs (20 bytes each) - matching mock expectations
    bytes constant NODE_ID_1 = hex"2345678123456781234567812345678123456781";
    bytes constant NODE_ID_2 = hex"3456781234567812345678123456781234567812";
    bytes constant NODE_ID_3 = hex"4567812345678123456781234567812345678123";

    // Keys used by the migration script broadcasts
    uint256 constant PROXY_ADMIN_OWNER_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // anvil[0]
    uint256 constant VALIDATOR_MANAGER_OWNER_KEY =
        0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d; // anvil[1]
    uint256 constant MIGRATION_DEPLOYER_KEY =
        0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a; // anvil[2] - for migration deployments

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
        // Deploy PoA VM + PoAManager via the deploy script
        BalancerMigrationConfig memory cfg = BalancerMigrationConfig({
            proxyAddress: address(0),
            validatorManagerProxy: address(0),
            poaManager: address(0),
            initialSecurityModuleMaxWeight: 0,
            migratedValidators: new bytes[](0),
            proxyAdminOwnerAddress: vm.addr(MIGRATION_DEPLOYER_KEY),
            validatorManagerOwnerAddress: owner,
            subnetID: TEST_SUBNET_ID,
            churnPeriodSeconds: CHURN_PERIOD,
            maximumChurnPercentage: MAX_CHURN_PERCENTAGE
        });

        ExecutePoAValidatorManager poaDeployer = new ExecutePoAValidatorManager();
        (address vmProxy, address poaMgr) =
            poaDeployer.executeDeployPoA(cfg, PROXY_ADMIN_OWNER_KEY, VALIDATOR_MANAGER_OWNER_KEY);

        validatorManager = vmProxy;
        poaManager = poaMgr;

        // Bind the warp mock to the freshly deployed VM
        ACP77WarpMessengerTestMock warpMock2 = new ACP77WarpMessengerTestMock(validatorManager);
        vm.etch(WARP_MESSENGER_ADDR, address(warpMock2).code);

        // Initialize validator set with test validators
        _initializeValidatorSet();
    }

    function _initializeValidatorSet() internal {
        InitialValidator[] memory initialValidators = new InitialValidator[](2);

        // Setup initial validators matching mock expectations
        initialValidators[0] =
            InitialValidator({nodeID: NODE_ID_1, blsPublicKey: new bytes(48), weight: 500_000});

        initialValidators[1] =
            InitialValidator({nodeID: NODE_ID_2, blsPublicKey: new bytes(48), weight: 500_000});

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
            proxyAdminOwnerAddress: vm.addr(MIGRATION_DEPLOYER_KEY),
            validatorManagerOwnerAddress: owner,
            subnetID: TEST_SUBNET_ID,
            churnPeriodSeconds: CHURN_PERIOD,
            maximumChurnPercentage: MAX_CHURN_PERCENTAGE
        });

        // Execute migration (deploys and initializes, but does NOT transfer ownership)
        MigratePoAToBalancer _migrator = new MigratePoAToBalancer();
        (address balancerProxy, address poaSecurityModule, address vmAddress) = _migrator
            .executeMigratePoAToBalancer(cfg, MIGRATION_DEPLOYER_KEY, VALIDATOR_MANAGER_OWNER_KEY);

        assertEq(vmAddress, validatorManager, "returned VM address should match");

        // Ownership still with PoAManager after script
        assertEq(
            ValidatorManager(vmAddress).owner(),
            poaManager,
            "ValidatorManager owner should still be PoAManager"
        );

        // Manually transfer ownership (simulating what user does after verifying config)
        vm.prank(owner);
        IPoAManager(poaManager).transferValidatorManagerOwnership(balancerProxy);

        // Now ValidatorManager ownership is with Balancer
        assertEq(
            ValidatorManager(vmAddress).owner(),
            balancerProxy,
            "ValidatorManager owner must be Balancer after manual transfer"
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
            proxyAdminOwnerAddress: vm.addr(MIGRATION_DEPLOYER_KEY),
            validatorManagerOwnerAddress: owner,
            subnetID: TEST_SUBNET_ID,
            churnPeriodSeconds: CHURN_PERIOD,
            maximumChurnPercentage: MAX_CHURN_PERCENTAGE
        });

        // Rejects unknown nodeIDs
        vm.expectRevert(bytes("migrated nodeID not registered"));
        migrator.executeMigratePoAToBalancer(
            cfg, MIGRATION_DEPLOYER_KEY, VALIDATOR_MANAGER_OWNER_KEY
        );
    }

    // Upgradeability tests
    function testUpgradeability_PreservesStateAndExposesNewLogic() public {
        // First perform the migration
        bytes[] memory nodeIds = new bytes[](2);
        nodeIds[0] = NODE_ID_1;
        nodeIds[1] = NODE_ID_2;
        bytes[] memory migratedValidators =
            extractor.extractActiveOrPendingAdded(validatorManager, nodeIds);

        BalancerMigrationConfig memory cfg = BalancerMigrationConfig({
            proxyAddress: address(0),
            validatorManagerProxy: validatorManager,
            poaManager: poaManager,
            initialSecurityModuleMaxWeight: SECURITY_MODULE_MAX_WEIGHT,
            migratedValidators: migratedValidators,
            proxyAdminOwnerAddress: vm.addr(MIGRATION_DEPLOYER_KEY),
            validatorManagerOwnerAddress: owner,
            subnetID: TEST_SUBNET_ID,
            churnPeriodSeconds: CHURN_PERIOD,
            maximumChurnPercentage: MAX_CHURN_PERCENTAGE
        });

        (address balancerProxy,,) = migrator.executeMigratePoAToBalancer(
            cfg, MIGRATION_DEPLOYER_KEY, VALIDATOR_MANAGER_OWNER_KEY
        );

        BalancerValidatorManager bal = BalancerValidatorManager(balancerProxy);

        // Pre-upgrade state snapshot
        address[] memory beforeModules = bal.getSecurityModules();
        (uint64 wBefore, uint64 maxBefore) = bal.getSecurityModuleWeights(beforeModules[0]);
        bytes32 val1IdBefore = bal.getNodeValidationID(NODE_ID_1);
        address val1ModuleBefore = bal.getValidatorSecurityModule(val1IdBefore);

        // Deploy new implementation
        BalancerValidatorManagerV2 v2 = new BalancerValidatorManagerV2();

        // Upgrade as proxy admin (now owned by MIGRATION_DEPLOYER_KEY)
        UnsafeUpgrades.upgradeProxy(balancerProxy, address(v2), "", vm.addr(MIGRATION_DEPLOYER_KEY));

        // New logic is live (called via the proxy from a non-admin)
        string memory ver = BalancerValidatorManagerV2(balancerProxy).version();
        assertEq(keccak256(bytes(ver)), keccak256(bytes("v2")), "new logic not active");

        // State is preserved
        address[] memory afterModules = bal.getSecurityModules();
        (uint64 wAfter, uint64 maxAfter) = bal.getSecurityModuleWeights(afterModules[0]);
        assertEq(afterModules.length, beforeModules.length, "modules length changed");
        assertEq(afterModules[0], beforeModules[0], "module address changed");
        assertEq(wAfter, wBefore, "module weight changed across upgrade");
        assertEq(maxAfter, maxBefore, "module maxWeight changed across upgrade");

        // Validator mappings preserved
        bytes32 val1IdAfter = bal.getNodeValidationID(NODE_ID_1);
        address val1ModuleAfter = bal.getValidatorSecurityModule(val1IdAfter);
        assertEq(val1IdAfter, val1IdBefore, "validation ID changed");
        assertEq(val1ModuleAfter, val1ModuleBefore, "validator module mapping changed");
    }

    function testTransparentProxy_AdminCannotCallLogic() public {
        // First perform the migration to get the balancer proxy
        bytes[] memory nodeIds = new bytes[](2);
        nodeIds[0] = NODE_ID_1;
        nodeIds[1] = NODE_ID_2;
        bytes[] memory migratedValidators =
            extractor.extractActiveOrPendingAdded(validatorManager, nodeIds);

        BalancerMigrationConfig memory cfg = BalancerMigrationConfig({
            proxyAddress: address(0),
            validatorManagerProxy: validatorManager,
            poaManager: poaManager,
            initialSecurityModuleMaxWeight: SECURITY_MODULE_MAX_WEIGHT,
            migratedValidators: migratedValidators,
            proxyAdminOwnerAddress: vm.addr(MIGRATION_DEPLOYER_KEY),
            validatorManagerOwnerAddress: owner,
            subnetID: TEST_SUBNET_ID,
            churnPeriodSeconds: CHURN_PERIOD,
            maximumChurnPercentage: MAX_CHURN_PERCENTAGE
        });

        (address balancerProxy,,) = migrator.executeMigratePoAToBalancer(
            cfg, MIGRATION_DEPLOYER_KEY, VALIDATOR_MANAGER_OWNER_KEY
        );

        // The proxy admin must not be able to reach implementation functions via fallback
        // (transparent proxy safety).
        // Get the actual proxy admin address (which is a ProxyAdmin contract, not the owner)
        address proxyAdmin = UnsafeUpgrades.getAdminAddress(balancerProxy);

        vm.startPrank(proxyAdmin);
        vm.expectRevert();
        BalancerValidatorManager(balancerProxy).getChurnPeriodSeconds();
        vm.stopPrank();
    }
}

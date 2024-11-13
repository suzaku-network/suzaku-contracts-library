// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity ^0.8.0;

import {HelperConfig} from "../../script/ACP99/HelperConfig.s.sol";
import {DeployACP99PoAModule} from "../../script/ACP99/SecurityModules/DeployACP99PoAModule.s.sol";
import {ACP99Manager, IACP99Manager} from "../../src/contracts/ACP99/ACP99Manager.sol";
import {
    ACP99PoAModule,
    IACP99SecurityModule
} from "../../src/contracts/ACP99/SecurityModules/ACP99PoAModule.sol";
import {ACP77WarpMessengerTestMock} from "../../src/mocks/ACP77WarpMessengerTestMock.sol";
import {PChainOwner} from "@avalabs/teleporter/validator-manager/interfaces/IValidatorManager.sol";
import {Test, console} from "forge-std/Test.sol";

contract ACP99PoAModuleTest is Test {
    event SetSecurityModule(address indexed securityModule);
    event ValidatorAdded(bytes32 indexed nodeID, uint64 weight);
    event ValidatorRemoved(bytes32 indexed nodeID);
    event ValidatorWeightUpdated(bytes32 indexed nodeID, uint64 newWeight);

    uint32 constant COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX = 3;
    uint32 constant VALIDATOR_UPTIME_MESSAGE_INDEX = 4;
    uint32 constant COMPLETE_VALIDATOR_WEIGHT_UPDATE_MESSAGE_INDEX = 5;
    address constant WARP_MESSENGER_ADDR = 0x0200000000000000000000000000000000000005;
    bytes public constant VALIDATOR_NODE_ID_01 =
        bytes(hex"1234567812345678123456781234567812345678123456781234567812345678");
    bytes public constant VALIDATOR_NODE_ID_02 =
        bytes(hex"2345678123456781234567812345678123456781234567812345678123456781");
    bytes constant VALIDATOR_BLS_PUBLIC_KEY = new bytes(48);
    uint64 constant VALIDATOR_WEIGHT = 20;
    bytes32 constant VALIDATION_ID =
        0x3a41d4db60b49389d4b121c2137a1382431a89369c5445c2a46877c3929dd9c6;
    PChainOwner public P_CHAIN_OWNER;

    ACP99PoAModule poaModule;
    uint256 deployerKey;
    address deployerAddress;
    bytes32 subnetID;
    ACP99Manager manager;

    function setUp() external {
        HelperConfig helperConfig = new HelperConfig();
        (deployerKey, subnetID) = helperConfig.activeNetworkConfig();
        deployerAddress = vm.addr(deployerKey);

        DeployACP99PoAModule poaModuleDeployer = new DeployACP99PoAModule();
        (manager, poaModule) = poaModuleDeployer.run();

        ACP77WarpMessengerTestMock warpMessengerTestMock =
            new ACP77WarpMessengerTestMock(address(manager));
        vm.etch(WARP_MESSENGER_ADDR, address(warpMessengerTestMock).code);

        address[] memory addresses = new address[](1);
        addresses[0] = 0x1234567812345678123456781234567812345678;
        P_CHAIN_OWNER = PChainOwner({threshold: 1, addresses: addresses});

        // Warp to 2024-01-01 00:00:00
        vm.warp(1_704_067_200);
    }

    modifier validatorRegistrationInitiated(bytes memory nodeID, uint64 weight) {
        uint64 registrationExpiry = uint64(block.timestamp + 1 days);

        vm.prank(deployerAddress);
        // validationID = 0xe2d4e0a460dd3674dbc90edafc676f80d5a6b402a5c028cdf6c0796c60b2b372
        poaModule.addValidator(
            nodeID,
            VALIDATOR_BLS_PUBLIC_KEY,
            registrationExpiry,
            P_CHAIN_OWNER,
            P_CHAIN_OWNER,
            weight
        );
        _;
    }

    modifier validatorRegistrationCompleted(bytes memory nodeID, uint64 weight) {
        uint64 registrationExpiry = uint64(block.timestamp + 1 days);

        vm.startPrank(deployerAddress);
        // validationID = 0xe2d4e0a460dd3674dbc90edafc676f80d5a6b402a5c028cdf6c0796c60b2b372
        poaModule.addValidator(
            nodeID,
            VALIDATOR_BLS_PUBLIC_KEY,
            registrationExpiry,
            P_CHAIN_OWNER,
            P_CHAIN_OWNER,
            weight
        );
        manager.completeValidatorRegistration(COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX);
        vm.stopPrank();
        _;
    }

    function testPoAModuleConstructsCorrectly() external view {
        // Arrange: Setup is done in the setUp() function

        // Act: No explicit action needed as we're testing the initial state

        // Assert: Check if the module is constructed correctly
        assertEq(poaModule.owner(), deployerAddress);
        assertEq(poaModule.getManagerAddress(), address(manager));
        assertEq(manager.getSecurityModule(), address(poaModule));
    }

    function testAddValidatorUpdatesState() external {
        // Arrange
        uint64 registrationExpiry = uint64(block.timestamp + 1 days);

        // Act
        vm.prank(deployerAddress);
        poaModule.addValidator(
            VALIDATOR_NODE_ID_01,
            VALIDATOR_BLS_PUBLIC_KEY,
            registrationExpiry,
            P_CHAIN_OWNER,
            P_CHAIN_OWNER,
            VALIDATOR_WEIGHT
        );

        // Assert
        ACP99Manager.Validation memory validation = manager.getValidation(VALIDATION_ID);
        assert(validation.status == IACP99Manager.ValidationStatus.Registering);
        assert(validation.nodeID == bytes32(VALIDATOR_NODE_ID_01));
        assert(validation.periods[0].weight == VALIDATOR_WEIGHT);
    }

    function testUpdateValidatorWeight()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID_01, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 40;
        vm.warp(1_706_745_600); // Warp to 2024-02-01 00:00:00

        // Act
        vm.prank(deployerAddress);
        poaModule.updateValidatorWeight(VALIDATOR_NODE_ID_01, newWeight);

        // Assert: Check the validation status after initiating the update
        IACP99Manager.Validation memory validation = manager.getValidation(VALIDATION_ID);
        assert(validation.status == IACP99Manager.ValidationStatus.Updating);
        assertEq(validation.periods.length, 2);
        assertEq(validation.periods[1].weight, newWeight);

        // Act: Complete the weight update
        vm.prank(address(poaModule));
        manager.completeValidatorWeightUpdate(COMPLETE_VALIDATOR_WEIGHT_UPDATE_MESSAGE_INDEX);

        // Assert: Check the validation status after completing the update
        validation = manager.getValidation(VALIDATION_ID);
        assert(validation.status == IACP99Manager.ValidationStatus.Active);
        assertEq(validation.periods.length, 2);
        assertEq(validation.periods[1].weight, newWeight);
        assertEq(validation.periods[1].startTime, block.timestamp);
        assertEq(manager.getValidatorActiveValidation(VALIDATOR_NODE_ID_01), VALIDATION_ID);
        assertEq(manager.l1TotalWeight(), newWeight);
    }

    function testRemoveValidatorUpdatesState()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID_01, VALIDATOR_WEIGHT)
    {
        // Arrange
        vm.warp(1_706_745_600); // Warp to 2024-02-01 00:00:00

        // Act
        vm.prank(deployerAddress);
        poaModule.removeValidator(VALIDATOR_NODE_ID_01, true, VALIDATOR_UPTIME_MESSAGE_INDEX);

        // Assert
        IACP99Manager.Validation memory validation = manager.getValidation(VALIDATION_ID);
        assert(validation.status == IACP99Manager.ValidationStatus.Removing);
        assert(validation.periods[0].uptimeSeconds > 0);
        assertEq(validation.periods.length, 1);
        assertEq(validation.periods[0].endTime, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                IACP99Manager.ACP99Manager__NodeIDNotActiveValidator.selector, VALIDATOR_NODE_ID_01
            )
        );
        manager.getValidatorActiveValidation(VALIDATOR_NODE_ID_01);
    }

    function testOnlyManagerFunctionsRevertProperly() external {
        // Arrange
        address nonManagerAddress = address(0x1234);
        vm.startPrank(nonManagerAddress);

        // Act & Assert: Test handleValidatorRegistration
        vm.expectRevert(
            abi.encodeWithSelector(
                IACP99SecurityModule.ACP99SecurityModule__OnlyManager.selector,
                nonManagerAddress,
                address(manager)
            )
        );
        poaModule.handleValidatorRegistration(
            IACP99SecurityModule.ValidatorRegistrationInfo({
                nodeID: bytes32(VALIDATOR_NODE_ID_01),
                validationID: VALIDATION_ID,
                weight: VALIDATOR_WEIGHT,
                startTime: uint64(block.timestamp)
            })
        );

        // Act & Assert: Test handleValidatorWeightChange
        vm.expectRevert(
            abi.encodeWithSelector(
                IACP99SecurityModule.ACP99SecurityModule__OnlyManager.selector,
                nonManagerAddress,
                address(manager)
            )
        );
        poaModule.handleValidatorWeightChange(
            IACP99SecurityModule.ValidatorWeightChangeInfo({
                nodeID: bytes32(VALIDATOR_NODE_ID_01),
                validationID: VALIDATION_ID,
                nonce: 0,
                newWeight: VALIDATOR_WEIGHT,
                uptimeInfo: IACP99Manager.ValidatorUptimeInfo({
                    activeSeconds: 1000,
                    uptimeSeconds: 900,
                    activeWeightSeconds: 1000 * VALIDATOR_WEIGHT,
                    uptimeWeightSeconds: 900 * VALIDATOR_WEIGHT
                })
            })
        );
    }
}

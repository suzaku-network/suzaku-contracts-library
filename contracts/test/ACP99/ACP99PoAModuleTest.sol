// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {HelperConfig} from "../../script/ACP99/HelperConfig.s.sol";
import {DeployACP99PoAModule} from "../../script/ACP99/SecurityModules/DeployACP99PoAModule.s.sol";
import {ACP99Manager, IACP99Manager} from "../../src/contracts/ACP99/ACP99Manager.sol";
import {
    ACP99PoAModule,
    IACP99SecurityModule
} from "../../src/contracts/ACP99/SecurityModules/ACP99PoAModule.sol";
import {WarpMessengerTestMock} from "../../src/mocks/WarpMessengerTestMock.sol";
import {Test, console} from "forge-std/Test.sol";

contract ACP99PoAModuleTest is Test {
    event SetSecurityModule(address indexed securityModule);
    event ValidatorAdded(bytes32 indexed nodeID, uint64 weight);
    event ValidatorRemoved(bytes32 indexed nodeID);
    event ValidatorWeightUpdated(bytes32 indexed nodeID, uint64 newWeight);

    uint32 constant COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX = 2;
    uint32 constant VALIDATOR_UPTIME_MESSAGE_INDEX = 3;
    uint32 constant COMPLETE_VALIDATOR_WEIGHT_UPDATE_MESSAGE_INDEX = 4;
    address constant WARP_MESSENGER_ADDRESS = 0x0200000000000000000000000000000000000005;
    bytes32 constant VALIDATOR_NODE_ID = bytes32(uint256(1));
    bytes constant VALIDATOR_BLS_PUBLIC_KEY = new bytes(48);
    uint64 constant VALIDATOR_WEIGHT = 100;
    bytes32 constant VALIDATION_ID =
        0x5b95b95601dce19048a51e797c1910a7da3514f77ed33a75ef69bd8aaf29a3d2;

    ACP99PoAModule poaModule;
    uint256 deployerKey;
    address deployerAddress;
    bytes32 subnetID;
    ACP99Manager manager;

    function setUp() external {
        HelperConfig helperConfig = new HelperConfig();
        (deployerKey, subnetID) = helperConfig.activeNetworkConfig();
        deployerAddress = vm.addr(deployerKey);

        WarpMessengerTestMock warpMessengerTestMock =
            new WarpMessengerTestMock(makeAddr("tokenHome"), makeAddr("tokenRemote"));
        vm.etch(WARP_MESSENGER_ADDRESS, address(warpMessengerTestMock).code);

        DeployACP99PoAModule poaModuleDeployer = new DeployACP99PoAModule();
        (manager, poaModule) = poaModuleDeployer.run();

        // Warp to 2024-01-01 00:00:00
        vm.warp(1_704_067_200);
    }

    modifier validatorRegistrationInitiated(bytes32 nodeID, uint64 weight) {
        uint64 registrationExpiry = uint64(block.timestamp + 1 days);

        vm.prank(deployerAddress);
        // validationID = 0x5b95b95601dce19048a51e797c1910a7da3514f77ed33a75ef69bd8aaf29a3d2
        poaModule.addValidator(
            VALIDATOR_NODE_ID, VALIDATOR_WEIGHT, registrationExpiry, VALIDATOR_BLS_PUBLIC_KEY
        );
        _;
    }

    modifier validatorRegistrationCompleted(bytes32 nodeID, uint64 weight) {
        uint64 registrationExpiry = uint64(block.timestamp + 1 days);

        vm.startPrank(deployerAddress);
        // validationID = 0x5b95b95601dce19048a51e797c1910a7da3514f77ed33a75ef69bd8aaf29a3d2
        poaModule.addValidator(
            VALIDATOR_NODE_ID, VALIDATOR_WEIGHT, registrationExpiry, VALIDATOR_BLS_PUBLIC_KEY
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
            VALIDATOR_NODE_ID, VALIDATOR_WEIGHT, registrationExpiry, VALIDATOR_BLS_PUBLIC_KEY
        );

        // Assert
        ACP99Manager.Validation memory validation = manager.getValidation(VALIDATION_ID);
        assert(validation.status == IACP99Manager.ValidationStatus.Registering);
        assert(validation.nodeID == VALIDATOR_NODE_ID);
        assert(validation.periods[0].weight == VALIDATOR_WEIGHT);
    }

    function testUpdateValidatorWeight()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 200;
        vm.warp(1_706_745_600); // Warp to 2024-02-01 00:00:00

        // Act
        vm.prank(deployerAddress);
        poaModule.updateValidatorWeight(VALIDATOR_NODE_ID, newWeight);

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
        assertEq(manager.getValidatorActiveValidation(VALIDATOR_NODE_ID), VALIDATION_ID);
        assertEq(manager.subnetTotalWeight(), newWeight);
    }

    function testRemoveValidatorUpdatesState()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Arrange
        vm.warp(1_706_745_600); // Warp to 2024-02-01 00:00:00

        // Act
        vm.prank(deployerAddress);
        poaModule.removeValidator(VALIDATOR_NODE_ID, true, VALIDATOR_UPTIME_MESSAGE_INDEX);

        // Assert
        IACP99Manager.Validation memory validation = manager.getValidation(VALIDATION_ID);
        assert(validation.status == IACP99Manager.ValidationStatus.Removing);
        assertEq(validation.endTime, block.timestamp);
        assertEq(validation.activeSeconds, block.timestamp - validation.startTime);
        assert(validation.uptimeSeconds > 0);
        assertEq(validation.periods.length, 1);
        assertEq(validation.periods[0].endTime, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                IACP99Manager.ACP99Manager__NodeIDNotActiveValidator.selector, VALIDATOR_NODE_ID
            )
        );
        manager.getValidatorActiveValidation(VALIDATOR_NODE_ID);
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
            IACP99SecurityModule.ValidatiorRegistrationInfo({
                nodeID: VALIDATOR_NODE_ID,
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
                nodeID: VALIDATOR_NODE_ID,
                validationID: VALIDATION_ID,
                nonce: 0,
                newWeight: VALIDATOR_WEIGHT,
                uptimeInfo: IACP99SecurityModule.ValidatorUptimeInfo({
                    activeSeconds: 1000,
                    uptimeSeconds: 900,
                    averageWeight: VALIDATOR_WEIGHT
                })
            })
        );
    }
}

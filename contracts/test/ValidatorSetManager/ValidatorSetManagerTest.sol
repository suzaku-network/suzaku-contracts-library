// (c) 2024, ADDPHO All rights reserved.
// See the file LICENSE_MIT for licensing terms.

// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {DeployValidatorSetManager} from
    "../../script/ValidatorSetManager/DeployValidatorSetManager.s.sol";
import {HelperConfig} from "../../script/ValidatorSetManager/HelperConfig.s.sol";
import {ValidatorSetManager} from "../../src/contracts/ValidatorSetManager/ValidatorSetManager.sol";
import {IValidatorSetManager} from
    "../../src/interfaces/ValidatorSetManager/IValidatorSetManager.sol";
import {WarpMessengerTestMock} from "../../src/mocks/WarpMessengerTestMock.sol";
import {Test, console} from "forge-std/Test.sol";

contract ValidatorSetManagerTest is Test {
    event SetSecurityModule(address indexed securityModule);
    event InitiateValidatorRegistration(
        bytes32 indexed nodeID,
        bytes32 indexed validationID,
        bytes32 registrationMessageID,
        uint64 weight,
        uint64 registrationExpiry
    );
    event CompleteValidatorRegistration(
        bytes32 indexed nodeID,
        bytes32 indexed validationID,
        uint64 weight,
        uint64 validationPeriodStartTime
    );
    event InitiateValidatorWeightUpdate(
        bytes32 indexed nodeID,
        bytes32 indexed validationID,
        bytes32 weightUpdateMessageID,
        uint64 weight
    );
    event CompleteValidatorWeightUpdate(
        bytes32 indexed nodeID, bytes32 indexed validationID, uint64 nonce, uint64 weight
    );

    uint32 constant COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX = 2;
    uint32 constant VALIDATOR_UPTIME_MESSAGE_INDEX = 3;
    uint32 constant SET_SUBNET_VALIDATOR_WEIGHT_MESSAGE_INDEX = 4;
    uint32 constant COMPLETE_VALIDATION_MESSAGE_INDEX = 5;
    address constant WARP_MESSENGER_ADDRESS = 0x0200000000000000000000000000000000000005;
    bytes32 constant VALIDATOR_NODE_ID = bytes32(uint256(1));
    uint64 constant VALIDATOR_WEIGHT = 100;
    bytes32 constant VALIDATION_ID =
        0x8f1e3878d6f56add95f8f62db483fcb58b75a7c8b15064135d207828be5dbf6b;

    ValidatorSetManager validatorSetManager;
    uint256 deployerKey;
    address deployerAddress;
    bytes32 subnetID;

    function setUp() external {
        HelperConfig helperConfig = new HelperConfig();
        (deployerKey, subnetID) = helperConfig.activeNetworkConfig();
        deployerAddress = vm.addr(deployerKey);

        WarpMessengerTestMock warpMessengerTestMock =
            new WarpMessengerTestMock(makeAddr("tokenHome"), makeAddr("tokenRemote"));
        vm.etch(WARP_MESSENGER_ADDRESS, address(warpMessengerTestMock).code);

        DeployValidatorSetManager validatorSetManagerDeployer = new DeployValidatorSetManager();
        (validatorSetManager) = validatorSetManagerDeployer.run();

        // Warp to 2024-01-01 00:00:00
        vm.warp(1_704_067_200);
    }

    modifier validatorRegistrationInitiated(bytes32 nodeID, uint64 weight) {
        uint64 registrationExpiry = uint64(block.timestamp + 1 days);
        bytes memory signature = new bytes(64);

        vm.prank(deployerAddress);
        // validationID = 0x8f1e3878d6f56add95f8f62db483fcb58b75a7c8b15064135d207828be5dbf6b
        validatorSetManager.initiateValidatorRegistration(
            nodeID, weight, registrationExpiry, signature
        );
        _;
    }

    modifier validatorRegistrationCompleted(bytes32 nodeID, uint64 weight) {
        uint64 registrationExpiry = uint64(block.timestamp + 1 days);
        bytes memory signature = new bytes(64);

        vm.startPrank(deployerAddress);
        // validationID = 0x8f1e3878d6f56add95f8f62db483fcb58b75a7c8b15064135d207828be5dbf6b
        validatorSetManager.initiateValidatorRegistration(
            nodeID, weight, registrationExpiry, signature
        );
        validatorSetManager.completeValidatorRegistration(
            COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX
        );
        vm.stopPrank();
        _;
    }

    function testValidatorSetManagerConstructsCorrectly() external view {
        assertEq(validatorSetManager.owner(), deployerAddress);
        assertEq(validatorSetManager.subnetID(), subnetID);
        assertEq(validatorSetManager.securityModule(), deployerAddress);
    }

    function testSetSecurityModuleUpdatesState() external {
        // Arrange
        address newSecurityModule = makeAddr("newSecurityModule");

        // Act
        vm.prank(deployerAddress);
        validatorSetManager.setSecurityModule(newSecurityModule);

        // Assert
        assertEq(validatorSetManager.securityModule(), newSecurityModule);
    }

    function testSetSecurityModuleEmitsEvent() external {
        // Arrange
        address newSecurityModule = makeAddr("newSecurityModule");

        // Act
        vm.prank(deployerAddress);
        vm.expectEmit(true, false, false, false, address(validatorSetManager));
        emit SetSecurityModule(newSecurityModule);
        validatorSetManager.setSecurityModule(newSecurityModule);
    }

    function testInitiateValidatorRegistrationUpdatesState() external {
        // Arrange
        bytes32 nodeID = bytes32(uint256(1));
        uint64 weight = 100;
        uint64 registrationExpiry = uint64(block.timestamp + 1 days);
        bytes memory signature = new bytes(64);

        // Act
        vm.prank(deployerAddress);
        bytes32 validationID = validatorSetManager.initiateValidatorRegistration(
            nodeID, weight, registrationExpiry, signature
        );

        // Assert
        IValidatorSetManager.Validation memory validation =
            validatorSetManager.getSubnetValidation(validationID);
        assert(validation.status == IValidatorSetManager.ValidationStatus.Registering);
        assert(validatorSetManager.pendingRegisterValidationMessages(validationID).length > 0);
        assertEq(validation.nodeID, nodeID);
        assertEq(validation.periods.length, 1);
        assertEq(validation.periods[0].weight, weight);
        assertEq(validation.periods[0].startTime, 0);
        assertEq(validation.periods[0].endTime, 0);
        assertEq(validation.periods[0].uptimeSeconds, 0);
        assertEq(validation.totalUptimeSeconds, 0);
    }

    function testInitiateValidatorRegistrationEmitsEvent() external {
        // Arrange
        bytes32 nodeID = bytes32(uint256(1));
        uint64 weight = 100;
        uint64 registrationExpiry = uint64(block.timestamp + 1 days);
        bytes memory signature = new bytes(64);

        // Act
        vm.prank(deployerAddress);
        vm.expectEmit(true, false, false, false, address(validatorSetManager));
        emit InitiateValidatorRegistration(
            nodeID, bytes32(0), bytes32(0), weight, registrationExpiry
        );
        validatorSetManager.initiateValidatorRegistration(
            nodeID, weight, registrationExpiry, signature
        );
    }

    function testInitiateValidatorRegistrationRevertsInvalidExpiry() external {
        // Arrange
        bytes32 nodeID = bytes32(uint256(2));
        uint64 weight = 100;
        uint64 registrationExpiryTooSoon = uint64(block.timestamp - 1 days);
        uint64 registrationExpiryTooLate = uint64(block.timestamp + 3 days);
        bytes memory signature = new bytes(64);

        // Act
        vm.startPrank(deployerAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                IValidatorSetManager.ValidatorSetManager__InvalidExpiry.selector,
                registrationExpiryTooSoon,
                block.timestamp
            )
        );
        validatorSetManager.initiateValidatorRegistration(
            nodeID, weight, registrationExpiryTooSoon, signature
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IValidatorSetManager.ValidatorSetManager__InvalidExpiry.selector,
                registrationExpiryTooLate,
                block.timestamp
            )
        );
        validatorSetManager.initiateValidatorRegistration(
            nodeID, weight, registrationExpiryTooLate, signature
        );
    }

    function testInitiateValidatorRegistrationRevertsInvalidNodeID()
        external
        validatorRegistrationInitiated(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 weight = 100;
        uint64 registrationExpiry = uint64(block.timestamp + 1 days);
        bytes memory signature = new bytes(64);

        // Act
        vm.prank(deployerAddress);
        vm.expectRevert(IValidatorSetManager.ValidatorSetManager__ZeroNodeID.selector);
        validatorSetManager.initiateValidatorRegistration(
            bytes32(0), weight, registrationExpiry, signature
        );
    }

    function testCompleteValidatorRegistrationUpdatesState()
        external
        validatorRegistrationInitiated(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Act
        vm.prank(deployerAddress);
        validatorSetManager.completeValidatorRegistration(
            COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX
        );

        // Assert
        IValidatorSetManager.Validation memory validation =
            validatorSetManager.getSubnetValidation(VALIDATION_ID);
        assert(validation.status == IValidatorSetManager.ValidationStatus.Active);
        assertEq(validation.periods[0].startTime, block.timestamp);

        bytes32 validationID = validatorSetManager.activeValidators(VALIDATOR_NODE_ID);
        assertEq(validationID, VALIDATION_ID);
    }

    function testCompleteValidatorRegistrationEmitsEvent()
        external
        validatorRegistrationInitiated(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Act
        vm.prank(deployerAddress);
        vm.expectEmit(true, true, false, false, address(validatorSetManager));
        emit CompleteValidatorRegistration(
            VALIDATOR_NODE_ID, VALIDATION_ID, VALIDATOR_WEIGHT, uint64(block.timestamp)
        );
        validatorSetManager.completeValidatorRegistration(
            COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX
        );
    }

    function testInitiateValidatorWeightUpdateUpdatesState()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 200;
        // Warp to 2024-02-01 00:00:00
        vm.warp(1_706_745_600);

        // Act
        vm.prank(deployerAddress);
        validatorSetManager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );

        // Assert
        IValidatorSetManager.Validation memory validation =
            validatorSetManager.getSubnetValidation(VALIDATION_ID);
        assert(validation.status == IValidatorSetManager.ValidationStatus.Updating);
        assertEq(validation.periods[0].endTime, block.timestamp);
        assert(validation.periods[0].uptimeSeconds > 0);
        assertEq(validation.periods.length, 2);
        assertEq(validation.periods[1].weight, newWeight);
        assertEq(validation.periods[1].startTime, 0);
        assertEq(validation.periods[1].endTime, 0);
        assertEq(validation.periods[1].uptimeSeconds, 0);
    }

    function testInitiateValidatorWeightUpdateEmitsEvent()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 200;
        // Warp to 2024-02-01 00:00:00
        vm.warp(1_706_745_600);

        // Act
        vm.prank(deployerAddress);
        vm.expectEmit(true, true, false, false, address(validatorSetManager));
        emit InitiateValidatorWeightUpdate(VALIDATOR_NODE_ID, VALIDATION_ID, bytes32(0), newWeight);
        validatorSetManager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );
    }

    function testInitiateValidatorWeightUpdateRevertsInvalidNodeID()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 200;

        // Act
        vm.startPrank(deployerAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                IValidatorSetManager.ValidatorSetManager__NodeIDNotActiveValidator.selector,
                bytes32(uint256(2))
            )
        );
        validatorSetManager.initiateValidatorWeightUpdate(
            bytes32(uint256(2)), newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );
    }

    function testCompleteValidatorWeightUpdateUpdatesState()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 200;
        // Warp to 2024-02-01 00:00:00
        vm.warp(1_706_745_600);
        vm.startPrank(deployerAddress);
        validatorSetManager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );

        // Act
        skip(3600);
        validatorSetManager.completeValidatorWeightUpdate(SET_SUBNET_VALIDATOR_WEIGHT_MESSAGE_INDEX);

        // Assert
        IValidatorSetManager.Validation memory validation =
            validatorSetManager.getSubnetValidation(VALIDATION_ID);
        assert(validation.status == IValidatorSetManager.ValidationStatus.Active);
        assertEq(validation.periods[1].weight, newWeight);
        assertEq(validation.periods[1].startTime, block.timestamp);
        assertEq(validation.periods[1].endTime, 0);
        assertEq(validation.periods[1].uptimeSeconds, -3600);
    }

    function testCompleteValidatorWeightUpdateEmitsEvent()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 200;
        // Warp to 2024-02-01 00:00:00
        vm.warp(1_706_745_600);
        vm.startPrank(deployerAddress);
        validatorSetManager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );

        // Act
        skip(3600);
        vm.expectEmit(true, true, false, true, address(validatorSetManager));
        emit CompleteValidatorWeightUpdate(VALIDATOR_NODE_ID, VALIDATION_ID, 1, newWeight);
        validatorSetManager.completeValidatorWeightUpdate(SET_SUBNET_VALIDATOR_WEIGHT_MESSAGE_INDEX);
    }

    function testCompleteValidationUpdatesState()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 0;
        // Warp to 2024-02-01 00:00:00
        vm.warp(1_706_745_600);
        vm.startPrank(deployerAddress);
        validatorSetManager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );

        // Act
        skip(3600);
        validatorSetManager.completeValidatorWeightUpdate(COMPLETE_VALIDATION_MESSAGE_INDEX);

        // Assert
        IValidatorSetManager.Validation memory validation =
            validatorSetManager.getSubnetValidation(VALIDATION_ID);
        assert(validation.status == IValidatorSetManager.ValidationStatus.Completed);
    }

    function testCompleteValidationEmitsEvent()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 0;
        // Warp to 2024-02-01 00:00:00
        vm.warp(1_706_745_600);
        vm.startPrank(deployerAddress);
        validatorSetManager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );

        // Act
        skip(3600);
        vm.expectEmit(true, true, false, true, address(validatorSetManager));
        emit CompleteValidatorWeightUpdate(VALIDATOR_NODE_ID, VALIDATION_ID, 1, newWeight);
        validatorSetManager.completeValidatorWeightUpdate(COMPLETE_VALIDATION_MESSAGE_INDEX);
    }
}

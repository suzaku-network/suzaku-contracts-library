// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity ^0.8.0;

import {HelperConfig} from "../../script/ACP99/HelperConfig.s.sol";
import {DeployACP99PoAModule} from "../../script/ACP99/SecurityModules/DeployACP99PoAModule.s.sol";
import {ACP99Manager} from "../../src/contracts/ACP99/ACP99Manager.sol";
import {ACP99PoAModule} from "../../src/contracts/ACP99/SecurityModules/ACP99PoAModule.sol";
import {ValidatorMessages} from "../../src/contracts/ACP99/ValidatorMessages.sol";
import {IACP99Manager} from "../../src/interfaces/ACP99/IACP99Manager.sol";
import {WarpMessengerTestMock} from "../../src/mocks/WarpMessengerTestMock.sol";
import {Test, console} from "forge-std/Test.sol";

contract ACP99ManagerTest is Test {
    event RegisterInitialValidator(
        bytes32 indexed nodeID, bytes32 indexed validationID, uint64 weight
    );
    event SetSecurityModule(address indexed securityModule);
    event InitiateValidatorRegistration(
        bytes32 indexed nodeID,
        bytes32 indexed validationID,
        bytes32 registrationMessageID,
        uint64 weight,
        uint64 registrationExpiry
    );
    event CompleteValidatorRegistration(
        bytes32 indexed nodeID, bytes32 indexed validationID, uint64 weight
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

    bytes32 private constant ANVIL_CHAIN_ID_HEX =
        0x7a69000000000000000000000000000000000000000000000000000000000000;
    uint32 constant INITIALIZE_VALIDATOR_SET_MESSAGE_INDEX = 2;
    uint32 constant COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX = 3;
    uint32 constant VALIDATOR_UPTIME_MESSAGE_INDEX = 4;
    uint32 constant COMPLETE_VALIDATOR_WEIGHT_UPDATE_MESSAGE_INDEX = 5;
    uint32 constant COMPLETE_VALIDATION_MESSAGE_INDEX = 6;
    address constant WARP_MESSENGER_ADDRESS = 0x0200000000000000000000000000000000000005;
    bytes32 constant VALIDATOR_NODE_ID = bytes32(uint256(1));
    bytes constant VALIDATOR_BLS_PUBLIC_KEY = new bytes(48);
    uint64 constant VALIDATOR_WEIGHT = 100;
    bytes32 constant VALIDATION_ID =
        0xe2d4e0a460dd3674dbc90edafc676f80d5a6b402a5c028cdf6c0796c60b2b372;

    ACP99Manager manager;
    ACP99PoAModule poaModule;
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

        DeployACP99PoAModule validatorSetManagerDeployer = new DeployACP99PoAModule();
        (manager, poaModule) = validatorSetManagerDeployer.run();

        // Warp to 2024-01-01 00:00:00
        vm.warp(1_704_067_200);
    }

    modifier validatorRegistrationInitiated(bytes32 nodeID, uint64 weight) {
        uint64 registrationExpiry = uint64(block.timestamp + 1 days);

        vm.prank(address(poaModule));
        // validationID = 0xe2d4e0a460dd3674dbc90edafc676f80d5a6b402a5c028cdf6c0796c60b2b372
        manager.initiateValidatorRegistration(
            nodeID, weight, registrationExpiry, VALIDATOR_BLS_PUBLIC_KEY
        );
        vm.stopPrank();
        _;
    }

    modifier validatorRegistrationCompleted(bytes32 nodeID, uint64 weight) {
        uint64 registrationExpiry = uint64(block.timestamp + 1 days);

        vm.startPrank(address(poaModule));
        // validationID = 0xe2d4e0a460dd3674dbc90edafc676f80d5a6b402a5c028cdf6c0796c60b2b372
        manager.initiateValidatorRegistration(
            nodeID, weight, registrationExpiry, VALIDATOR_BLS_PUBLIC_KEY
        );
        manager.completeValidatorRegistration(COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX);
        vm.stopPrank();
        _;
    }

    function testValidatorSetManagerConstructsCorrectly() external view {
        assertEq(manager.owner(), deployerAddress);
        assertEq(manager.subnetID(), subnetID);
        assertEq(manager.getSecurityModule(), address(poaModule));
    }

    function testSetSecurityModuleUpdatesState() external {
        // Arrange
        address newSecurityModule = makeAddr("newSecurityModule");

        // Act
        vm.prank(deployerAddress);
        manager.setSecurityModule(newSecurityModule);

        // Assert
        assertEq(manager.getSecurityModule(), newSecurityModule);
    }

    function testSetSecurityModuleEmitsEvent() external {
        // Arrange
        address newSecurityModule = makeAddr("newSecurityModule");

        // Act
        vm.prank(deployerAddress);
        vm.expectEmit(true, false, false, false, address(manager));
        emit SetSecurityModule(newSecurityModule);
        manager.setSecurityModule(newSecurityModule);
    }

    function generateSubnetConversionData()
        private
        view
        returns (ValidatorMessages.SubnetConversionData memory)
    {
        ValidatorMessages.InitialValidator[] memory initialValidators =
            new ValidatorMessages.InitialValidator[](2);
        initialValidators[0] = ValidatorMessages.InitialValidator({
            nodeID: bytes32(uint256(2)),
            weight: 100,
            blsPublicKey: VALIDATOR_BLS_PUBLIC_KEY
        });
        initialValidators[1] = ValidatorMessages.InitialValidator({
            nodeID: bytes32(uint256(3)),
            weight: 100,
            blsPublicKey: VALIDATOR_BLS_PUBLIC_KEY
        });
        ValidatorMessages.SubnetConversionData memory subnetConversionData = ValidatorMessages
            .SubnetConversionData({
            convertSubnetTxID: bytes32(uint256(1)),
            validatorManagerBlockchainID: ANVIL_CHAIN_ID_HEX,
            validatorManagerAddress: address(manager),
            initialValidators: initialValidators
        });
        return subnetConversionData;
    }

    function testInitializeValidatiorSetUpdatesState() external {
        // Arrange
        ValidatorMessages.SubnetConversionData memory subnetConversionData =
            generateSubnetConversionData();

        // Act
        vm.prank(deployerAddress);
        manager.initializeValidatorSet(subnetConversionData, INITIALIZE_VALIDATOR_SET_MESSAGE_INDEX);

        // Assert
        assert(manager.initializedValidatorSet());
        assertEq(manager.subnetTotalWeight(), 200);
        assertEq(manager.getActiveValidatorSet().length, 2);
        assertEq(manager.getActiveValidatorSet()[0], bytes32(uint256(2)));
        assertEq(manager.getActiveValidatorSet()[1], bytes32(uint256(3)));
        IACP99Manager.Validation memory validation = manager.getValidation(
            sha256(abi.encodePacked(subnetConversionData.convertSubnetTxID, uint32(0)))
        );
        assertEq(validation.nodeID, bytes32(uint256(2)));
        assertEq(validation.periods[0].weight, 100);
        assertEq(validation.periods[0].startTime, block.timestamp);
    }

    function testInitializeValidatorSetEmitsEvent() external {
        // Arrange
        ValidatorMessages.SubnetConversionData memory subnetConversionData =
            generateSubnetConversionData();

        // Act
        vm.prank(deployerAddress);
        // We don't check the validationID
        vm.expectEmit(true, false, false, false, address(manager));
        emit RegisterInitialValidator(bytes32(uint256(2)), VALIDATION_ID, 100);
        emit RegisterInitialValidator(bytes32(uint256(3)), VALIDATION_ID, 100);
        manager.initializeValidatorSet(subnetConversionData, INITIALIZE_VALIDATOR_SET_MESSAGE_INDEX);
    }

    function testInitializeValidatorSetRevertsIfAlreadyInitialized() external {
        // Arrange
        ValidatorMessages.SubnetConversionData memory subnetConversionData =
            generateSubnetConversionData();
        vm.prank(deployerAddress);
        manager.initializeValidatorSet(subnetConversionData, INITIALIZE_VALIDATOR_SET_MESSAGE_INDEX);

        // Act
        vm.prank(deployerAddress);
        vm.expectRevert(IACP99Manager.ACP99Manager__ValidatorSetAlreadyInitialized.selector);
        manager.initializeValidatorSet(subnetConversionData, INITIALIZE_VALIDATOR_SET_MESSAGE_INDEX);
    }

    function testInitiateValidatorRegistrationUpdatesState() external {
        // Arrange
        uint64 registrationExpiry = uint64(block.timestamp + 1 days);

        // Act
        vm.prank(address(poaModule));
        bytes32 validationID = manager.initiateValidatorRegistration(
            VALIDATOR_NODE_ID, VALIDATOR_WEIGHT, registrationExpiry, VALIDATOR_BLS_PUBLIC_KEY
        );

        // Assert
        IACP99Manager.Validation memory validation = manager.getValidation(validationID);
        assert(validation.status == IACP99Manager.ValidationStatus.Registering);
        assert(manager.pendingRegisterValidationMessages(validationID).length > 0);
        assertEq(validation.nodeID, VALIDATOR_NODE_ID);
        assertEq(validation.periods.length, 1);
        assertEq(validation.periods[0].weight, VALIDATOR_WEIGHT);
        assertEq(validation.periods[0].startTime, 0);
        assertEq(validation.periods[0].endTime, 0);
        assertEq(validation.uptimeSeconds, 0);
    }

    function testInitiateValidatorRegistrationEmitsEvent() external {
        // Arrange
        uint64 registrationExpiry = uint64(block.timestamp + 1 days);

        // Act
        vm.prank(address(poaModule));
        vm.expectEmit(true, false, false, false, address(manager));
        emit InitiateValidatorRegistration(
            VALIDATOR_NODE_ID, bytes32(0), bytes32(0), VALIDATOR_WEIGHT, registrationExpiry
        );
        manager.initiateValidatorRegistration(
            VALIDATOR_NODE_ID, VALIDATOR_WEIGHT, registrationExpiry, VALIDATOR_BLS_PUBLIC_KEY
        );
    }

    function testInitiateValidatorRegistrationRevertsInvalidExpiry() external {
        // Arrange
        uint64 registrationExpiryTooSoon = uint64(block.timestamp - 1 days);
        uint64 registrationExpiryTooLate = uint64(block.timestamp + 3 days);

        // Act
        vm.startPrank(address(poaModule));
        vm.expectRevert(
            abi.encodeWithSelector(
                IACP99Manager.ACP99Manager__InvalidExpiry.selector,
                registrationExpiryTooSoon,
                block.timestamp
            )
        );
        manager.initiateValidatorRegistration(
            VALIDATOR_NODE_ID, VALIDATOR_WEIGHT, registrationExpiryTooSoon, VALIDATOR_BLS_PUBLIC_KEY
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IACP99Manager.ACP99Manager__InvalidExpiry.selector,
                registrationExpiryTooLate,
                block.timestamp
            )
        );
        manager.initiateValidatorRegistration(
            VALIDATOR_NODE_ID, VALIDATOR_WEIGHT, registrationExpiryTooLate, VALIDATOR_BLS_PUBLIC_KEY
        );
    }

    function testInitiateValidatorRegistrationRevertsInvalidNodeID()
        external
        validatorRegistrationInitiated(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 registrationExpiry = uint64(block.timestamp + 1 days);

        // Act
        vm.prank(address(poaModule));
        vm.expectRevert(IACP99Manager.ACP99Manager__ZeroNodeID.selector);
        manager.initiateValidatorRegistration(
            bytes32(0), VALIDATOR_WEIGHT, registrationExpiry, VALIDATOR_BLS_PUBLIC_KEY
        );
    }

    function testCompleteValidatorRegistrationUpdatesState()
        external
        validatorRegistrationInitiated(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Act
        vm.prank(address(poaModule));
        manager.completeValidatorRegistration(COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX);

        // Assert
        IACP99Manager.Validation memory validation = manager.getValidation(VALIDATION_ID);
        assert(validation.status == IACP99Manager.ValidationStatus.Active);
        assertEq(validation.periods[0].startTime, block.timestamp);

        bytes32 validationID = manager.getValidatorActiveValidation(VALIDATOR_NODE_ID);
        assertEq(validationID, VALIDATION_ID);

        assertEq(manager.subnetTotalWeight(), VALIDATOR_WEIGHT);
    }

    function testCompleteValidatorRegistrationEmitsEvent()
        external
        validatorRegistrationInitiated(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Act
        vm.prank(address(poaModule));
        vm.expectEmit(true, true, false, false, address(manager));
        emit CompleteValidatorRegistration(VALIDATOR_NODE_ID, VALIDATION_ID, VALIDATOR_WEIGHT);
        manager.completeValidatorRegistration(COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX);
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
        vm.prank(address(poaModule));
        manager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );

        // Assert
        IACP99Manager.Validation memory validation = manager.getValidation(VALIDATION_ID);
        assert(validation.status == IACP99Manager.ValidationStatus.Updating);
        assertEq(validation.activeSeconds, block.timestamp - validation.startTime);
        assert(validation.uptimeSeconds > 0);
        assertEq(validation.periods.length, 2);
        assertEq(validation.periods[0].endTime, block.timestamp);
        assertEq(validation.periods[1].weight, newWeight);
        assertEq(validation.periods[1].startTime, 0);
        assertEq(validation.periods[1].endTime, 0);
        assertEq(manager.subnetTotalWeight(), VALIDATOR_WEIGHT);
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
        vm.prank(address(poaModule));
        vm.expectEmit(true, true, false, false, address(manager));
        emit InitiateValidatorWeightUpdate(VALIDATOR_NODE_ID, VALIDATION_ID, bytes32(0), newWeight);
        manager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );
    }

    function testInitiateValidatorRemovalUpdatesState()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 0;
        // Warp to 2024-02-01 00:00:00
        vm.warp(1_706_745_600);

        // Act
        vm.prank(address(poaModule));
        manager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );

        // Assert
        IACP99Manager.Validation memory validation = manager.getValidation(VALIDATION_ID);
        assert(validation.status == IACP99Manager.ValidationStatus.Removing);
        assertEq(validation.endTime, block.timestamp);
        assertEq(validation.activeSeconds, block.timestamp - validation.startTime);
        assert(validation.uptimeSeconds > 0);
        assertEq(validation.periods.length, 1);
        assertEq(validation.periods[0].endTime, block.timestamp);
        assertEq(manager.subnetTotalWeight(), VALIDATOR_WEIGHT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IACP99Manager.ACP99Manager__NodeIDNotActiveValidator.selector, VALIDATOR_NODE_ID
            )
        );
        manager.getValidatorActiveValidation(VALIDATOR_NODE_ID);
    }

    function testInitiateValidatorWeightUpdateRevertsInvalidNodeID()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 200;

        // Act
        vm.startPrank(address(poaModule));
        vm.expectRevert(
            abi.encodeWithSelector(
                IACP99Manager.ACP99Manager__NodeIDNotActiveValidator.selector, bytes32(uint256(2))
            )
        );
        manager.initiateValidatorWeightUpdate(
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
        vm.startPrank(address(poaModule));
        manager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );

        // Act
        skip(3600);
        manager.completeValidatorWeightUpdate(COMPLETE_VALIDATOR_WEIGHT_UPDATE_MESSAGE_INDEX);

        // Assert
        IACP99Manager.Validation memory validation = manager.getValidation(VALIDATION_ID);
        assert(validation.status == IACP99Manager.ValidationStatus.Active);
        assertEq(validation.periods[1].weight, newWeight);
        assertEq(validation.periods[1].startTime, block.timestamp);
        assertEq(validation.periods[1].endTime, 0);
        assertEq(manager.subnetTotalWeight(), newWeight);
    }

    function testCompleteValidatorWeightUpdateEmitsEvent()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 200;
        // Warp to 2024-02-01 00:00:00
        vm.warp(1_706_745_600);
        vm.startPrank(address(poaModule));
        manager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );

        // Act
        skip(3600);
        vm.expectEmit(true, true, false, true, address(manager));
        emit CompleteValidatorWeightUpdate(VALIDATOR_NODE_ID, VALIDATION_ID, 1, newWeight);
        manager.completeValidatorWeightUpdate(COMPLETE_VALIDATOR_WEIGHT_UPDATE_MESSAGE_INDEX);
    }

    function testCompleteValidatorRemovalUpdatesState()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 0;
        // Warp to 2024-02-01 00:00:00
        vm.warp(1_706_745_600);
        vm.startPrank(address(poaModule));
        manager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );

        // Act
        skip(3600);
        manager.completeValidatorWeightUpdate(COMPLETE_VALIDATION_MESSAGE_INDEX);

        // Assert
        IACP99Manager.Validation memory validation = manager.getValidation(VALIDATION_ID);
        assert(validation.status == IACP99Manager.ValidationStatus.Completed);
        assertEq(manager.subnetTotalWeight(), 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IACP99Manager.ACP99Manager__NodeIDNotActiveValidator.selector, VALIDATOR_NODE_ID
            )
        );
        manager.getValidatorActiveValidation(VALIDATOR_NODE_ID);
    }

    function testCompleteValidatorRemovalEmitsEvent()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 0;
        // Warp to 2024-02-01 00:00:00
        vm.warp(1_706_745_600);
        vm.startPrank(address(poaModule));
        manager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );

        // Act
        skip(3600);
        vm.expectEmit(true, true, false, true, address(manager));
        emit CompleteValidatorWeightUpdate(VALIDATOR_NODE_ID, VALIDATION_ID, 1, newWeight);
        manager.completeValidatorWeightUpdate(COMPLETE_VALIDATION_MESSAGE_INDEX);
    }
}

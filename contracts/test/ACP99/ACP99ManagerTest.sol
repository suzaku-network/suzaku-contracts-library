// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity ^0.8.0;

import {HelperConfig} from "../../script/ACP99/HelperConfig.s.sol";
import {DeployACP99PoAModule} from "../../script/ACP99/SecurityModules/DeployACP99PoAModule.s.sol";
import {ACP99Manager} from "../../src/contracts/ACP99/ACP99Manager.sol";
import {ACP99PoAModule} from "../../src/contracts/ACP99/SecurityModules/ACP99PoAModule.sol";
import {IACP99Manager} from "../../src/interfaces/ACP99/IACP99Manager.sol";
import {ACP77WarpMessengerTestMock} from "../../src/mocks/ACP77WarpMessengerTestMock.sol";
import {
    ConversionData,
    ValidatorMessages
} from "@avalabs/teleporter/validator-manager/ValidatorMessages.sol";
import {
    InitialValidator,
    PChainOwner
} from "@avalabs/teleporter/validator-manager/interfaces/IValidatorManager.sol";
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
    address constant WARP_MESSENGER_ADDR = 0x0200000000000000000000000000000000000005;
    bytes public constant VALIDATOR_NODE_ID_01 =
        bytes(hex"1234567812345678123456781234567812345678123456781234567812345678");
    bytes public constant VALIDATOR_NODE_ID_02 =
        bytes(hex"2345678123456781234567812345678123456781234567812345678123456781");
    bytes public constant VALIDATOR_NODE_ID_03 =
        bytes(hex"3456781234567812345678123456781234567812345678123456781234567812");
    bytes constant VALIDATOR_BLS_PUBLIC_KEY = new bytes(48);
    uint64 constant VALIDATOR_WEIGHT = 100;
    bytes32 constant VALIDATION_ID =
        0x6bc851f1cf9fe68ddb8c6fe4b72f467aeeff662677d4d65e1a387085bfdda283;
    PChainOwner public P_CHAIN_OWNER;

    ACP99Manager manager;
    ACP99PoAModule poaModule;
    uint256 deployerKey;
    address deployerAddress;
    bytes32 subnetID;

    function setUp() external {
        HelperConfig helperConfig = new HelperConfig();
        (deployerKey, subnetID) = helperConfig.activeNetworkConfig();
        deployerAddress = vm.addr(deployerKey);

        ACP77WarpMessengerTestMock warpMessengerTestMock =
            new ACP77WarpMessengerTestMock(makeAddr("tokenHome"), makeAddr("tokenRemote"));
        vm.etch(WARP_MESSENGER_ADDR, address(warpMessengerTestMock).code);

        DeployACP99PoAModule validatorSetManagerDeployer = new DeployACP99PoAModule();
        (manager, poaModule) = validatorSetManagerDeployer.run();

        address[] memory addresses = new address[](1);
        addresses[0] = 0x1234567812345678123456781234567812345678;
        P_CHAIN_OWNER = PChainOwner({threshold: 1, addresses: addresses});

        // Warp to 2024-01-01 00:00:00
        vm.warp(1_704_067_200);
    }

    modifier validatorRegistrationInitiated(bytes memory nodeID, uint64 weight) {
        uint64 registrationExpiry = uint64(block.timestamp + 1 days);

        vm.prank(address(poaModule));
        // validationID = 0xe2d4e0a460dd3674dbc90edafc676f80d5a6b402a5c028cdf6c0796c60b2b372
        manager.initiateValidatorRegistration(
            nodeID,
            VALIDATOR_BLS_PUBLIC_KEY,
            registrationExpiry,
            P_CHAIN_OWNER,
            P_CHAIN_OWNER,
            weight
        );
        vm.stopPrank();
        _;
    }

    modifier validatorRegistrationCompleted(bytes memory nodeID, uint64 weight) {
        uint64 registrationExpiry = uint64(block.timestamp + 1 days);

        vm.startPrank(address(poaModule));
        // validationID = 0xe2d4e0a460dd3674dbc90edafc676f80d5a6b402a5c028cdf6c0796c60b2b372
        manager.initiateValidatorRegistration(
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

    function generateConversionData() private view returns (ConversionData memory) {
        InitialValidator[] memory initialValidators = new InitialValidator[](2);
        initialValidators[0] = InitialValidator({
            nodeID: VALIDATOR_NODE_ID_02,
            weight: 100,
            blsPublicKey: VALIDATOR_BLS_PUBLIC_KEY
        });
        initialValidators[1] = InitialValidator({
            nodeID: VALIDATOR_NODE_ID_03,
            weight: 100,
            blsPublicKey: VALIDATOR_BLS_PUBLIC_KEY
        });
        ConversionData memory conversionData = ConversionData({
            subnetID: subnetID,
            validatorManagerBlockchainID: ANVIL_CHAIN_ID_HEX,
            validatorManagerAddress: address(manager),
            initialValidators: initialValidators
        });
        return conversionData;
    }

    function testInitializeValidatiorSetUpdatesState() external {
        // Arrange
        ConversionData memory conversionData = generateConversionData();

        // Act
        vm.prank(deployerAddress);
        manager.initializeValidatorSet(conversionData, INITIALIZE_VALIDATOR_SET_MESSAGE_INDEX);

        // Assert
        assert(manager.initializedValidatorSet());
        assertEq(manager.l1TotalWeight(), 200);
        assertEq(manager.getActiveValidatorSet().length, 2);
        assertEq(manager.getActiveValidatorSet()[0], bytes32(VALIDATOR_NODE_ID_02));
        assertEq(manager.getActiveValidatorSet()[1], bytes32(VALIDATOR_NODE_ID_03));
        IACP99Manager.Validation memory validation =
            manager.getValidation(sha256(abi.encodePacked(conversionData.subnetID, uint32(0))));
        assertEq(validation.nodeID, bytes32(VALIDATOR_NODE_ID_02));
        assertEq(validation.periods[0].weight, 100);
        assertEq(validation.periods[0].startTime, block.timestamp);
    }

    function testInitializeValidatorSetEmitsEvent() external {
        // Arrange
        ConversionData memory conversionData = generateConversionData();

        // Act
        vm.prank(deployerAddress);
        // We don't check the validationID
        vm.expectEmit(true, false, false, false, address(manager));
        emit RegisterInitialValidator(bytes32(VALIDATOR_NODE_ID_02), VALIDATION_ID, 100);
        emit RegisterInitialValidator(bytes32(VALIDATOR_NODE_ID_03), VALIDATION_ID, 100);
        manager.initializeValidatorSet(conversionData, INITIALIZE_VALIDATOR_SET_MESSAGE_INDEX);
    }

    function testInitializeValidatorSetRevertsIfAlreadyInitialized() external {
        // Arrange
        ConversionData memory conversionData = generateConversionData();
        vm.prank(deployerAddress);
        manager.initializeValidatorSet(conversionData, INITIALIZE_VALIDATOR_SET_MESSAGE_INDEX);

        // Act
        vm.prank(deployerAddress);
        vm.expectRevert(IACP99Manager.ACP99Manager__ValidatorSetAlreadyInitialized.selector);
        manager.initializeValidatorSet(conversionData, INITIALIZE_VALIDATOR_SET_MESSAGE_INDEX);
    }

    function testInitiateValidatorRegistrationUpdatesState() external {
        // Arrange
        uint64 registrationExpiry = uint64(block.timestamp + 1 days);

        // Act
        vm.prank(address(poaModule));
        bytes32 validationID = manager.initiateValidatorRegistration(
            VALIDATOR_NODE_ID_01,
            VALIDATOR_BLS_PUBLIC_KEY,
            registrationExpiry,
            P_CHAIN_OWNER,
            P_CHAIN_OWNER,
            VALIDATOR_WEIGHT
        );

        // Assert
        IACP99Manager.Validation memory validation = manager.getValidation(validationID);
        assert(validation.status == IACP99Manager.ValidationStatus.Registering);
        assert(manager.pendingRegisterValidationMessages(validationID).length > 0);
        assertEq(validation.nodeID, bytes32(VALIDATOR_NODE_ID_01));
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
            bytes32(VALIDATOR_NODE_ID_01),
            bytes32(0),
            bytes32(0),
            registrationExpiry,
            VALIDATOR_WEIGHT
        );
        manager.initiateValidatorRegistration(
            VALIDATOR_NODE_ID_01,
            VALIDATOR_BLS_PUBLIC_KEY,
            registrationExpiry,
            P_CHAIN_OWNER,
            P_CHAIN_OWNER,
            VALIDATOR_WEIGHT
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
            VALIDATOR_NODE_ID_01,
            VALIDATOR_BLS_PUBLIC_KEY,
            registrationExpiryTooSoon,
            P_CHAIN_OWNER,
            P_CHAIN_OWNER,
            VALIDATOR_WEIGHT
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IACP99Manager.ACP99Manager__InvalidExpiry.selector,
                registrationExpiryTooLate,
                block.timestamp
            )
        );
        manager.initiateValidatorRegistration(
            VALIDATOR_NODE_ID_01,
            VALIDATOR_BLS_PUBLIC_KEY,
            registrationExpiryTooLate,
            P_CHAIN_OWNER,
            P_CHAIN_OWNER,
            VALIDATOR_WEIGHT
        );
    }

    function testInitiateValidatorRegistrationRevertsInvalidNodeID()
        external
        validatorRegistrationInitiated(VALIDATOR_NODE_ID_01, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 registrationExpiry = uint64(block.timestamp + 1 days);

        // Act
        vm.prank(address(poaModule));
        vm.expectRevert(IACP99Manager.ACP99Manager__ZeroNodeID.selector);
        manager.initiateValidatorRegistration(
            bytes(hex"00"),
            VALIDATOR_BLS_PUBLIC_KEY,
            registrationExpiry,
            P_CHAIN_OWNER,
            P_CHAIN_OWNER,
            VALIDATOR_WEIGHT
        );
    }

    function testCompleteValidatorRegistrationUpdatesState()
        external
        validatorRegistrationInitiated(VALIDATOR_NODE_ID_01, VALIDATOR_WEIGHT)
    {
        // Act
        vm.prank(address(poaModule));
        manager.completeValidatorRegistration(COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX);

        // Assert
        IACP99Manager.Validation memory validation = manager.getValidation(VALIDATION_ID);
        assert(validation.status == IACP99Manager.ValidationStatus.Active);
        assertEq(validation.periods[0].startTime, block.timestamp);

        bytes32 validationID = manager.getValidatorActiveValidation(VALIDATOR_NODE_ID_01);
        assertEq(validationID, VALIDATION_ID);

        assertEq(manager.l1TotalWeight(), VALIDATOR_WEIGHT);
    }

    function testCompleteValidatorRegistrationEmitsEvent()
        external
        validatorRegistrationInitiated(VALIDATOR_NODE_ID_01, VALIDATOR_WEIGHT)
    {
        // Act
        vm.prank(address(poaModule));
        vm.expectEmit(true, true, false, false, address(manager));
        emit CompleteValidatorRegistration(
            bytes32(VALIDATOR_NODE_ID_01), VALIDATION_ID, VALIDATOR_WEIGHT
        );
        manager.completeValidatorRegistration(COMPLETE_VALIDATOR_REGISTRATION_MESSAGE_INDEX);
    }

    function testInitiateValidatorWeightUpdateUpdatesState()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID_01, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 200;
        // Warp to 2024-02-01 00:00:00
        vm.warp(1_706_745_600);

        // Act
        vm.prank(address(poaModule));
        manager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID_01, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
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
        assertEq(manager.l1TotalWeight(), VALIDATOR_WEIGHT);
    }

    function testInitiateValidatorWeightUpdateEmitsEvent()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID_01, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 200;
        // Warp to 2024-02-01 00:00:00
        vm.warp(1_706_745_600);

        // Act
        vm.prank(address(poaModule));
        vm.expectEmit(true, true, false, false, address(manager));
        emit InitiateValidatorWeightUpdate(
            bytes32(VALIDATOR_NODE_ID_01), VALIDATION_ID, bytes32(0), newWeight
        );
        manager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID_01, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );
    }

    function testInitiateValidatorRemovalUpdatesState()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID_01, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 0;
        // Warp to 2024-02-01 00:00:00
        vm.warp(1_706_745_600);

        // Act
        vm.prank(address(poaModule));
        manager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID_01, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );

        // Assert
        IACP99Manager.Validation memory validation = manager.getValidation(VALIDATION_ID);
        assert(validation.status == IACP99Manager.ValidationStatus.Removing);
        assertEq(validation.endTime, block.timestamp);
        assertEq(validation.activeSeconds, block.timestamp - validation.startTime);
        assert(validation.uptimeSeconds > 0);
        assertEq(validation.periods.length, 1);
        assertEq(validation.periods[0].endTime, block.timestamp);
        assertEq(manager.l1TotalWeight(), VALIDATOR_WEIGHT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IACP99Manager.ACP99Manager__NodeIDNotActiveValidator.selector, VALIDATOR_NODE_ID_01
            )
        );
        manager.getValidatorActiveValidation(VALIDATOR_NODE_ID_01);
    }

    function testInitiateValidatorWeightUpdateRevertsInvalidNodeID()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID_01, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 200;

        // Act
        vm.startPrank(address(poaModule));
        vm.expectRevert(
            abi.encodeWithSelector(
                IACP99Manager.ACP99Manager__NodeIDNotActiveValidator.selector, VALIDATOR_NODE_ID_02
            )
        );
        manager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID_02, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );
    }

    function testCompleteValidatorWeightUpdateUpdatesState()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID_01, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 200;
        // Warp to 2024-02-01 00:00:00
        vm.warp(1_706_745_600);
        vm.startPrank(address(poaModule));
        manager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID_01, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
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
        assertEq(manager.l1TotalWeight(), newWeight);
    }

    function testCompleteValidatorWeightUpdateEmitsEvent()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID_01, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 200;
        // Warp to 2024-02-01 00:00:00
        vm.warp(1_706_745_600);
        vm.startPrank(address(poaModule));
        manager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID_01, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );

        // Act
        skip(3600);
        vm.expectEmit(true, true, false, true, address(manager));
        emit CompleteValidatorWeightUpdate(
            bytes32(VALIDATOR_NODE_ID_01), VALIDATION_ID, 1, newWeight
        );
        manager.completeValidatorWeightUpdate(COMPLETE_VALIDATOR_WEIGHT_UPDATE_MESSAGE_INDEX);
    }

    function testCompleteValidatorRemovalUpdatesState()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID_01, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 0;
        // Warp to 2024-02-01 00:00:00
        vm.warp(1_706_745_600);
        vm.startPrank(address(poaModule));
        manager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID_01, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );

        // Act
        skip(3600);
        manager.completeValidatorWeightUpdate(COMPLETE_VALIDATION_MESSAGE_INDEX);

        // Assert
        IACP99Manager.Validation memory validation = manager.getValidation(VALIDATION_ID);
        assert(validation.status == IACP99Manager.ValidationStatus.Completed);
        assertEq(manager.l1TotalWeight(), 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IACP99Manager.ACP99Manager__NodeIDNotActiveValidator.selector, VALIDATOR_NODE_ID_01
            )
        );
        manager.getValidatorActiveValidation(VALIDATOR_NODE_ID_01);
    }

    function testCompleteValidatorRemovalEmitsEvent()
        external
        validatorRegistrationCompleted(VALIDATOR_NODE_ID_01, VALIDATOR_WEIGHT)
    {
        // Arrange
        uint64 newWeight = 0;
        // Warp to 2024-02-01 00:00:00
        vm.warp(1_706_745_600);
        vm.startPrank(address(poaModule));
        manager.initiateValidatorWeightUpdate(
            VALIDATOR_NODE_ID_01, newWeight, true, VALIDATOR_UPTIME_MESSAGE_INDEX
        );

        // Act
        skip(3600);
        vm.expectEmit(true, true, false, true, address(manager));
        emit CompleteValidatorWeightUpdate(
            bytes32(VALIDATOR_NODE_ID_01), VALIDATION_ID, 1, newWeight
        );
        manager.completeValidatorWeightUpdate(COMPLETE_VALIDATION_MESSAGE_INDEX);
    }
}

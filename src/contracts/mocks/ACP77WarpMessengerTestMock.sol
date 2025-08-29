// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {
    TeleporterMessage,
    TeleporterMessageReceipt
} from "@avalabs/icm-contracts/teleporter/ITeleporterMessenger.sol";
import {
    ConversionData,
    ValidatorMessages
} from "@avalabs/icm-contracts/validator-manager/ValidatorMessages.sol";
import {InitialValidator} from
    "@avalabs/icm-contracts/validator-manager/interfaces/IACP99Manager.sol";
import {WarpMessage} from
    "@avalabs/subnet-evm-contracts@1.2.2/contracts/interfaces/IWarpMessenger.sol";

contract ACP77WarpMessengerTestMock {
    address private constant TELEPORTER_MESSENGER_ADDRESS =
        0xF2E246BB76DF876Cef8b38ae84130F4F55De395b;
    bytes32 private constant P_CHAIN_ID_HEX = bytes32(0);
    bytes32 private constant ANVIL_CHAIN_ID_HEX =
        0x7a69000000000000000000000000000000000000000000000000000000000000;
    bytes32 private constant DEFAULT_DEST_CHAIN_ID_HEX =
        0x1000000000000000000000000000000000000000000000000000000000000000;
    bytes32 public constant DEFAULT_L1_ID =
        0x5f4c8570d996184af03052f1b3acc1c7b432b0a41e7480de1b72d4c6f5983eb9;
    // Node IDs must be exactly 20 bytes to match NODE_ID_LENGTH
    bytes public constant DEFAULT_NODE_ID_02 = bytes(hex"2345678123456781234567812345678123456781");
    bytes public constant DEFAULT_NODE_ID_03 = bytes(hex"3456781234567812345678123456781234567812");
    bytes32 private constant DEFAULT_MESSAGE_ID =
        0x39fa07214dc7ff1d2f8b6dfe6cd26f6b138ee9d40d013724382a5c539c8641e2;
    // Validation ID calculated from 20-byte node ID
    bytes32 private constant DEFAULT_VALIDATION_ID =
        0xeff50f7a8eeb7cc7e7799bdff2003c5a19de374d75da4a8cbcff6abea22b4e56;
    uint64 private constant DEFAULT_VALIDATION_UPTIME_SECONDS = uint64(2_544_480);

    address private immutable validatorManagerAddress;
    // Store validation IDs for dynamically registered validators
    mapping(bytes => bytes32) private nodeIDToValidationID;

    constructor(
        address _validatorManagerAddress
    ) {
        validatorManagerAddress = _validatorManagerAddress;
    }

    function getBlockchainID() external pure returns (bytes32) {
        return ANVIL_CHAIN_ID_HEX;
    }

    function sendWarpMessage(
        bytes calldata payload
    ) external returns (bytes32) {
        // If this is a validator registration message, store the validation ID
        if (payload.length > 6) {
            uint16 codecID = uint16(uint8(payload[0])) << 8 | uint16(uint8(payload[1]));
            uint32 typeID = uint32(uint8(payload[2])) << 24 | uint32(uint8(payload[3])) << 16
                | uint32(uint8(payload[4])) << 8 | uint32(uint8(payload[5]));

            if (
                codecID == ValidatorMessages.CODEC_ID
                    && typeID == ValidatorMessages.REGISTER_L1_VALIDATOR_MESSAGE_TYPE_ID
            ) {
                // Calculate validation ID from the payload
                bytes32 validationID = sha256(payload);

                // Extract node ID from the payload
                ValidatorMessages.ValidationPeriod memory period =
                    ValidatorMessages.unpackRegisterL1ValidatorMessage(payload);

                // Store the mapping
                nodeIDToValidationID[period.nodeID] = validationID;
            }
        }

        return DEFAULT_MESSAGE_ID;
    }

    // Mocks valid warp messages for testing
    // messageIndex = 2: InitializeValidatorSetMessage used for ACP99Manager tests
    // messageIndex = 3: ValidatorRegistrationMessage used for ACP99Manager tests
    // messageIndex = 4: ValidatorUptimeMessage used for ACP99Manager tests
    // messageIndex = 5: ValidatorWeightUpdateMessage used for ACP99Manager tests (weight = 200)
    // messageIndex = 6: ValidatorWeightUpdateMessage used for ACP99Manager tests (weight = 0)
    // messageIndex = 7: ValidatorRegistrationMessage used for ACP99Manager tests (expired)
    function getVerifiedWarpMessage(
        uint32 messageIndex
    ) external view returns (WarpMessage memory message, bool valid) {
        if (messageIndex == 2) {
            return _initializeValidatorSetWarpMessage();
        } else if (messageIndex == 3) {
            return _validatorRegistrationWarpMessage();
        } else if (messageIndex == 4) {
            return _validatorUptimeWarpMessage();
        } else if (messageIndex == 5) {
            return _validatorWeightUpdateWarpMessage();
        } else if (messageIndex == 6) {
            return _validatorWeightZeroWarpMessage();
        } else if (messageIndex == 7) {
            return _validatorRegistrationExpiredWarpMessage();
        }
    }

    function _initializeValidatorSetWarpMessage() private view returns (WarpMessage memory, bool) {
        InitialValidator[] memory initialValidators = new InitialValidator[](2);
        initialValidators[0] = InitialValidator({
            nodeID: DEFAULT_NODE_ID_02,
            weight: 500_000,
            blsPublicKey: new bytes(48)
        });
        initialValidators[1] = InitialValidator({
            nodeID: DEFAULT_NODE_ID_03,
            weight: 500_000,
            blsPublicKey: new bytes(48)
        });
        ConversionData memory conversionData = ConversionData({
            subnetID: DEFAULT_L1_ID,
            validatorManagerBlockchainID: ANVIL_CHAIN_ID_HEX,
            validatorManagerAddress: validatorManagerAddress,
            initialValidators: initialValidators
        });
        bytes memory encodedConversion = ValidatorMessages.packConversionData(conversionData);
        bytes32 encodedConversionID = sha256(encodedConversion);

        WarpMessage memory warpMessage = WarpMessage({
            sourceChainID: P_CHAIN_ID_HEX,
            originSenderAddress: address(0),
            payload: abi.encodePacked(
                ValidatorMessages.CODEC_ID,
                ValidatorMessages.SUBNET_TO_L1_CONVERSION_MESSAGE_TYPE_ID,
                encodedConversionID
            )
        });

        return (warpMessage, true);
    }

    function _validatorRegistrationWarpMessage() private view returns (WarpMessage memory, bool) {
        // Use the stored validation ID if available, otherwise use default
        bytes32 validationID = nodeIDToValidationID[hex"1234567812345678123456781234567812345678"];
        if (validationID == bytes32(0)) {
            validationID = DEFAULT_VALIDATION_ID;
        }

        WarpMessage memory warpMessage = WarpMessage({
            sourceChainID: P_CHAIN_ID_HEX,
            originSenderAddress: address(0),
            payload: abi.encodePacked(
                ValidatorMessages.CODEC_ID,
                ValidatorMessages.L1_VALIDATOR_REGISTRATION_MESSAGE_TYPE_ID,
                validationID,
                true
            )
        });

        return (warpMessage, true);
    }

    function _validatorUptimeWarpMessage() private view returns (WarpMessage memory, bool) {
        // Use the stored validation ID if available, otherwise use default
        bytes32 validationID = nodeIDToValidationID[hex"1234567812345678123456781234567812345678"];
        if (validationID == bytes32(0)) {
            validationID = DEFAULT_VALIDATION_ID;
        }

        WarpMessage memory warpMessage = WarpMessage({
            sourceChainID: ANVIL_CHAIN_ID_HEX,
            originSenderAddress: address(0),
            payload: abi.encodePacked(
                ValidatorMessages.CODEC_ID,
                ValidatorMessages.VALIDATION_UPTIME_MESSAGE_TYPE_ID,
                validationID,
                DEFAULT_VALIDATION_UPTIME_SECONDS
            )
        });

        return (warpMessage, true);
    }

    function _validatorWeightUpdateWarpMessage() private view returns (WarpMessage memory, bool) {
        // Use the stored validation ID if available, otherwise use default
        bytes32 validationID = nodeIDToValidationID[hex"1234567812345678123456781234567812345678"];
        if (validationID == bytes32(0)) {
            validationID = DEFAULT_VALIDATION_ID;
        }

        WarpMessage memory warpMessage = WarpMessage({
            sourceChainID: P_CHAIN_ID_HEX,
            originSenderAddress: address(0),
            payload: abi.encodePacked(
                ValidatorMessages.CODEC_ID,
                ValidatorMessages.L1_VALIDATOR_WEIGHT_MESSAGE_TYPE_ID,
                validationID,
                uint64(1),
                uint64(200_000) // 2 * 100K validator weight
            )
        });

        return (warpMessage, true);
    }

    function _validatorWeightZeroWarpMessage() private view returns (WarpMessage memory, bool) {
        // Use the stored validation ID if available, otherwise use default
        bytes32 validationID = nodeIDToValidationID[hex"1234567812345678123456781234567812345678"];
        if (validationID == bytes32(0)) {
            validationID = DEFAULT_VALIDATION_ID;
        }

        WarpMessage memory warpMessage = WarpMessage({
            sourceChainID: P_CHAIN_ID_HEX,
            originSenderAddress: address(0),
            payload: abi.encodePacked(
                ValidatorMessages.CODEC_ID,
                ValidatorMessages.L1_VALIDATOR_WEIGHT_MESSAGE_TYPE_ID,
                validationID,
                uint64(1),
                uint64(0)
            )
        });

        return (warpMessage, true);
    }

    function _validatorRegistrationExpiredWarpMessage()
        private
        view
        returns (WarpMessage memory, bool)
    {
        // Use the stored validation ID if available, otherwise use default
        bytes32 validationID = nodeIDToValidationID[hex"1234567812345678123456781234567812345678"];
        if (validationID == bytes32(0)) {
            validationID = DEFAULT_VALIDATION_ID;
        }

        WarpMessage memory warpMessage = WarpMessage({
            sourceChainID: P_CHAIN_ID_HEX,
            originSenderAddress: address(0),
            payload: abi.encodePacked(
                ValidatorMessages.CODEC_ID,
                ValidatorMessages.L1_VALIDATOR_REGISTRATION_MESSAGE_TYPE_ID,
                validationID,
                false
            )
        });

        return (warpMessage, true);
    }
}

// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {WarpMessage} from
    "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {
    TeleporterMessage,
    TeleporterMessageReceipt
} from "@avalabs/teleporter/teleporter/ITeleporterMessenger.sol";
import {
    ConversionData,
    ValidatorMessages
} from "@avalabs/teleporter/validator-manager/ValidatorMessages.sol";
import {InitialValidator} from
    "@avalabs/teleporter/validator-manager/interfaces/IValidatorManager.sol";

contract ACP77WarpMessengerTestMock {
    address private constant TELEPORTER_MESSENGER_ADDRESS =
        0xF2E246BB76DF876Cef8b38ae84130F4F55De395b;
    bytes32 private constant P_CHAIN_ID_HEX = bytes32(0);
    bytes32 private constant ANVIL_CHAIN_ID_HEX =
        0x7a69000000000000000000000000000000000000000000000000000000000000;
    bytes32 private constant DEFAULT_DEST_CHAIN_ID_HEX =
        0x1000000000000000000000000000000000000000000000000000000000000000;
    bytes32 public constant DEFAULT_SUBNET_ID =
        0x5f4c8570d996184af03052f1b3acc1c7b432b0a41e7480de1b72d4c6f5983eb9;
    bytes public constant DEFAULT_NODE_ID_02 =
        bytes(hex"2345678123456781234567812345678123456781234567812345678123456781");
    bytes public constant DEFAULT_NODE_ID_03 =
        bytes(hex"3456781234567812345678123456781234567812345678123456781234567812");
    bytes32 private constant DEFAULT_MESSAGE_ID =
        0x39fa07214dc7ff1d2f8b6dfe6cd26f6b138ee9d40d013724382a5c539c8641e2;
    address private constant DEFAULT_VALIDATOR_MANAGER_ADDRESS =
        0xf06FD5A15c8333CcC2b336D72ECE381c88cB657f;
    bytes32 private constant DEFAULT_VALIDATION_ID =
        0x6bc851f1cf9fe68ddb8c6fe4b72f467aeeff662677d4d65e1a387085bfdda283;

    uint64 private constant DEFAULT_VALIDATION_UPTIME_SECONDS = uint64(2_544_480);

    address private immutable tokenHomeAddress;
    address private immutable tokenRemoteAddress;

    constructor(address tokenHomeAddress_, address tokenRemoteAddress_) {
        tokenHomeAddress = tokenHomeAddress_;
        tokenRemoteAddress = tokenRemoteAddress_;
    }

    function getBlockchainID() external pure returns (bytes32) {
        return ANVIL_CHAIN_ID_HEX;
    }

    function sendWarpMessage(
        bytes calldata
    ) external pure returns (bytes32) {
        return DEFAULT_MESSAGE_ID;
    }

    // Mocks valid warp messages for testing
    // messageIndex = 2: InitializeValidatorSetMessage used for ACP99Manager tests
    // messageIndex = 3: SubnetValidatorRegistrationMessage used for ACP99Manager tests
    // messageIndex = 4: ValidatorUptimeMessage used for ACP99Manager tests
    // messageIndex = 5: ValidatorWeightUpdateMessage used for ACP99Manager tests (weight = 200)
    // messageIndex = 6: ValidatorWeightUpdateMessage used for ACP99Manager tests (weight = 0)
    function getVerifiedWarpMessage(
        uint32 messageIndex
    ) external pure returns (WarpMessage memory message, bool valid) {
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
        }
    }

    function _initializeValidatorSetWarpMessage() private pure returns (WarpMessage memory, bool) {
        InitialValidator[] memory initialValidators = new InitialValidator[](2);
        initialValidators[0] =
            InitialValidator({nodeID: DEFAULT_NODE_ID_02, weight: 100, blsPublicKey: new bytes(48)});
        initialValidators[1] =
            InitialValidator({nodeID: DEFAULT_NODE_ID_03, weight: 100, blsPublicKey: new bytes(48)});
        ConversionData memory conversionData = ConversionData({
            subnetID: DEFAULT_SUBNET_ID,
            validatorManagerBlockchainID: ANVIL_CHAIN_ID_HEX,
            validatorManagerAddress: DEFAULT_VALIDATOR_MANAGER_ADDRESS,
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

    function _validatorRegistrationWarpMessage() private pure returns (WarpMessage memory, bool) {
        WarpMessage memory warpMessage = WarpMessage({
            sourceChainID: P_CHAIN_ID_HEX,
            originSenderAddress: address(0),
            payload: abi.encodePacked(
                ValidatorMessages.CODEC_ID,
                ValidatorMessages.L1_VALIDATOR_REGISTRATION_MESSAGE_TYPE_ID,
                DEFAULT_VALIDATION_ID,
                true
            )
        });

        return (warpMessage, true);
    }

    function _validatorUptimeWarpMessage() private pure returns (WarpMessage memory, bool) {
        WarpMessage memory warpMessage = WarpMessage({
            sourceChainID: ANVIL_CHAIN_ID_HEX,
            originSenderAddress: address(0),
            payload: abi.encodePacked(
                ValidatorMessages.CODEC_ID,
                ValidatorMessages.VALIDATION_UPTIME_MESSAGE_TYPE_ID,
                DEFAULT_VALIDATION_ID,
                DEFAULT_VALIDATION_UPTIME_SECONDS
            )
        });

        return (warpMessage, true);
    }

    function _validatorWeightUpdateWarpMessage() private pure returns (WarpMessage memory, bool) {
        WarpMessage memory warpMessage = WarpMessage({
            sourceChainID: P_CHAIN_ID_HEX,
            originSenderAddress: address(0),
            payload: abi.encodePacked(
                ValidatorMessages.CODEC_ID,
                ValidatorMessages.L1_VALIDATOR_WEIGHT_MESSAGE_TYPE_ID,
                DEFAULT_VALIDATION_ID,
                uint64(1),
                uint64(200)
            )
        });

        return (warpMessage, true);
    }

    function _validatorWeightZeroWarpMessage() private pure returns (WarpMessage memory, bool) {
        WarpMessage memory warpMessage = WarpMessage({
            sourceChainID: P_CHAIN_ID_HEX,
            originSenderAddress: address(0),
            payload: abi.encodePacked(
                ValidatorMessages.CODEC_ID,
                ValidatorMessages.L1_VALIDATOR_WEIGHT_MESSAGE_TYPE_ID,
                DEFAULT_VALIDATION_ID,
                uint64(1),
                uint64(0)
            )
        });

        return (warpMessage, true);
    }
}

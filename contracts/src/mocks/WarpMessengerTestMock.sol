// (c) 2024, ADDPHO All rights reserved.
// See the file LICENSE_MIT for licensing terms.

// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {ValidatorMessages} from "../contracts/ACP99/ValidatorMessages.sol";
import {
    RegisterRemoteMessage,
    TransferrerMessage,
    TransferrerMessageType
} from "@avalabs/avalanche-ictt/interfaces/ITokenTransferrer.sol";
import {WarpMessage} from
    "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {TeleporterMessage, TeleporterMessageReceipt} from "@teleporter/ITeleporterMessenger.sol";

contract WarpMessengerTestMock {
    address private constant TELEPORTER_MESSENGER_ADDRESS =
        0xF2E246BB76DF876Cef8b38ae84130F4F55De395b;
    bytes32 private constant P_CHAIN_ID_HEX = bytes32(0);
    bytes32 private constant ANVIL_CHAIN_ID_HEX =
        0x7a69000000000000000000000000000000000000000000000000000000000000;
    bytes32 private constant DEST_CHAIN_ID_HEX =
        0x1000000000000000000000000000000000000000000000000000000000000000;
    bytes32 private constant MESSAGE_ID =
        0x39fa07214dc7ff1d2f8b6dfe6cd26f6b138ee9d40d013724382a5c539c8641e2;
    bytes32 private constant VALIDATION_ID =
        0x5b95b95601dce19048a51e797c1910a7da3514f77ed33a75ef69bd8aaf29a3d2;
    uint64 private constant VALIDATION_UPTIME_SECONDS = uint64(2_544_480);

    address private immutable tokenHomeAddress;
    address private immutable tokenRemoteAddress;

    constructor(address tokenHomeAddress_, address tokenRemoteAddress_) {
        tokenHomeAddress = tokenHomeAddress_;
        tokenRemoteAddress = tokenRemoteAddress_;
    }

    function getBlockchainID() external pure returns (bytes32) {
        return ANVIL_CHAIN_ID_HEX;
    }

    function sendWarpMessage(bytes calldata) external pure returns (bytes32) {
        return MESSAGE_ID;
    }

    // Mocks valid warp messages for testing
    // messageIndex = 1: RegisterRemoteMessage used for AvalancheICTTRouter tests
    // messageIndex = 2: SubnetValidatorRegistrationMessage used for ACP99Manager tests
    // messageIndex = 3: ValidatorUptimeMessage used for ACP99Manager tests
    // messageIndex = 4: ValidatorWeightUpdateMessage used for ACP99Manager tests (weight = 200)
    // messageIndex = 5: ValidatorWeightUpdateMessage used for ACP99Manager tests (weight = 0)
    function getVerifiedWarpMessage(uint32 messageIndex)
        external
        view
        returns (WarpMessage memory message, bool valid)
    {
        if (messageIndex == 1) {
            return _registerRemoteWarpMessage();
        } else if (messageIndex == 2) {
            return _subnetValidatorRegistrationWarpMessage();
        } else if (messageIndex == 3) {
            return _validatorUptimeWarpMessage();
        } else if (messageIndex == 4) {
            return _validatorWeightUpdateWarpMessage();
        } else if (messageIndex == 5) {
            return _validatorWeightZeroWarpMessage();
        }
    }

    function _registerRemoteWarpMessage() private view returns (WarpMessage memory, bool) {
        RegisterRemoteMessage memory registerMessage = RegisterRemoteMessage({
            initialReserveImbalance: 0,
            homeTokenDecimals: 18,
            remoteTokenDecimals: 18
        });
        TransferrerMessage memory bridgeMessage = TransferrerMessage({
            messageType: TransferrerMessageType.REGISTER_REMOTE,
            payload: abi.encode(registerMessage)
        });
        address[] memory allowedRelayerAddresses;
        TeleporterMessageReceipt[] memory receipts;
        TeleporterMessage memory teleporterMessage = TeleporterMessage({
            messageNonce: 1,
            originSenderAddress: tokenRemoteAddress,
            destinationBlockchainID: ANVIL_CHAIN_ID_HEX,
            destinationAddress: tokenHomeAddress,
            requiredGasLimit: 10_000_000,
            allowedRelayerAddresses: allowedRelayerAddresses,
            receipts: receipts,
            message: abi.encode(bridgeMessage)
        });
        WarpMessage memory warpMessage = WarpMessage({
            sourceChainID: DEST_CHAIN_ID_HEX,
            originSenderAddress: TELEPORTER_MESSENGER_ADDRESS,
            payload: abi.encode(teleporterMessage)
        });

        return (warpMessage, true);
    }

    function _subnetValidatorRegistrationWarpMessage()
        private
        pure
        returns (WarpMessage memory, bool)
    {
        WarpMessage memory warpMessage = WarpMessage({
            sourceChainID: P_CHAIN_ID_HEX,
            originSenderAddress: address(0),
            payload: abi.encodePacked(
                ValidatorMessages.CODEC_ID,
                ValidatorMessages.SUBNET_VALIDATOR_REGISTRATION_MESSAGE_TYPE_ID,
                VALIDATION_ID,
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
                VALIDATION_ID,
                VALIDATION_UPTIME_SECONDS
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
                ValidatorMessages.SET_SUBNET_VALIDATOR_WEIGHT_MESSAGE_TYPE_ID,
                VALIDATION_ID,
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
                ValidatorMessages.SET_SUBNET_VALIDATOR_WEIGHT_MESSAGE_TYPE_ID,
                VALIDATION_ID,
                uint64(1),
                uint64(0)
            )
        });

        return (warpMessage, true);
    }
}

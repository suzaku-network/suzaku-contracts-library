// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

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
    address private constant VALIDATOR_MANAGER_ADDRESS = 0xf06FD5A15c8333CcC2b336D72ECE381c88cB657f;
    bytes32 private constant VALIDATION_ID =
        0xe2d4e0a460dd3674dbc90edafc676f80d5a6b402a5c028cdf6c0796c60b2b372;
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

    function sendWarpMessage(
        bytes calldata
    ) external pure returns (bytes32) {
        return MESSAGE_ID;
    }

    // Mocks valid warp messages for testing
    // messageIndex = 1: RegisterRemoteMessage used for AvalancheICTTRouter tests
    // messageIndex = 2: InitializeValidatorSetMessage used for ACP99Manager tests
    // messageIndex = 3: SubnetValidatorRegistrationMessage used for ACP99Manager tests
    // messageIndex = 4: ValidatorUptimeMessage used for ACP99Manager tests
    // messageIndex = 5: ValidatorWeightUpdateMessage used for ACP99Manager tests (weight = 200)
    // messageIndex = 6: ValidatorWeightUpdateMessage used for ACP99Manager tests (weight = 0)
    function getVerifiedWarpMessage(
        uint32 messageIndex
    ) external view returns (WarpMessage memory message, bool valid) {
        if (messageIndex == 1) {
            return _registerRemoteWarpMessage();
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
}

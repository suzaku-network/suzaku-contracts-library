// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {WarpMessage} from
    "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";

import {
    RegisterRemoteMessage,
    TransferrerMessage,
    TransferrerMessageType
} from "@avalabs/avalanche-ictt/interfaces/ITokenTransferrer.sol";
import {TeleporterMessage, TeleporterMessageReceipt} from "@teleporter/ITeleporterMessenger.sol";

contract WarpMessengerTestMock {
    bytes32 private immutable homeChainID =
        0x7a69000000000000000000000000000000000000000000000000000000000000;
    bytes32 private immutable remoteChainID =
        0x1000000000000000000000000000000000000000000000000000000000000000;
    bytes32 private immutable messageID =
        0x39fa07214dc7ff1d2f8b6dfe6cd26f6b138ee9d40d013724382a5c539c8641e2;
    uint256 private immutable initialReserveImbalance = 0;
    uint8 private immutable homeTokenDecimals = 18;
    uint8 private immutable remoteTokenDecimals = 18;
    address private immutable teleporterMessengerAddress =
        0xF2E246BB76DF876Cef8b38ae84130F4F55De395b;
    address private immutable tokenHomeAddress;
    address private immutable tokenRemoteAddress = 0x9C5d3EBEA175C8F401feAa23a4a01214DDE525b6;
    uint256 private immutable requiredGasLimit = 10_000_000;

    constructor(
        address tokenHomeAddress_
    ) {
        tokenHomeAddress = tokenHomeAddress_;
    }

    function getBlockchainID() external view returns (bytes32) {
        return homeChainID;
    }

    function sendWarpMessage(
        bytes calldata
    ) external view returns (bytes32) {
        return messageID;
    }

    function getVerifiedWarpMessage(
        uint32
    ) external view returns (WarpMessage memory message, bool valid) {
        RegisterRemoteMessage memory registerMessage = RegisterRemoteMessage({
            initialReserveImbalance: initialReserveImbalance,
            homeTokenDecimals: homeTokenDecimals,
            remoteTokenDecimals: remoteTokenDecimals
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
            destinationBlockchainID: homeChainID,
            destinationAddress: tokenHomeAddress,
            requiredGasLimit: requiredGasLimit,
            allowedRelayerAddresses: allowedRelayerAddresses,
            receipts: receipts,
            message: abi.encode(bridgeMessage)
        });
        WarpMessage memory warpMessage = WarpMessage({
            sourceChainID: remoteChainID,
            originSenderAddress: teleporterMessengerAddress,
            payload: abi.encode(teleporterMessage)
        });

        return (warpMessage, true);
    }
}

// SPDX-License-Identifier: UNLICENSED
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
    bytes32 private immutable homeChainID;
    bytes32 private immutable remoteChainID;
    bytes32 private immutable messageID;
    uint256 private immutable initialReserveImbalance;
    uint8 private immutable homeTokenDecimals;
    uint8 private immutable remoteTokenDecimals;
    address private immutable teleporterMessengerAddress;
    address private immutable tokenHomeAddress;
    address private immutable tokenRemoteAddress;
    uint256 private immutable requiredGasLimit;

    constructor(
        bytes32 homeChainID_,
        bytes32 remoteChainID_,
        bytes32 messageID_,
        uint256 initialReserveImbalance_,
        uint8 homeTokenDecimals_,
        uint8 remoteTokenDecimals_,
        address teleporterMessengerAddress_,
        address tokenHomeAddress_,
        address tokenRemoteAddress_,
        uint256 requiredGasLimit_
    ) {
        homeChainID = homeChainID_;
        remoteChainID = remoteChainID_;
        messageID = messageID_;
        initialReserveImbalance = initialReserveImbalance_;
        homeTokenDecimals = homeTokenDecimals_;
        remoteTokenDecimals = remoteTokenDecimals_;
        teleporterMessengerAddress = teleporterMessengerAddress_;
        tokenHomeAddress = tokenHomeAddress_;
        tokenRemoteAddress = tokenRemoteAddress_;
        requiredGasLimit = requiredGasLimit_;
    }

    function getBlockchainID() external view returns (bytes32) {
        return homeChainID;
    }

    function sendWarpMessage(bytes calldata) external view returns (bytes32) {
        return messageID;
    }

    function getVerifiedWarpMessage(uint32)
        external
        view
        returns (WarpMessage memory message, bool valid)
    {
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

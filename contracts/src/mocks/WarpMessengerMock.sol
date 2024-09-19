// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

contract WarpMessengerMock {
    bytes32 private immutable blockchainId;
    bytes32 private immutable messageID;

    constructor(bytes32 blockchainId_, bytes32 messageID_) {
        blockchainId = blockchainId_;
        messageID = messageID_;
    }

    function getBlockchainID() external view returns (bytes32) {
        return blockchainId;
    }

    function sendWarpMessage(bytes calldata) external view returns (bytes32) {
        return messageID;
    }
}

// (c) 2024, ADDPHO All rights reserved.
// See the file LICENSE_MIT for licensing terms.

// SPDX-License-Identifier: MIT

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

    function sendWarpMessage(
        bytes calldata
    ) external view returns (bytes32) {
        return messageID;
    }
}

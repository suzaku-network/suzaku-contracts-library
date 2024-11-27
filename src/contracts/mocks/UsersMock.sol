// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {IERC20SendAndCallReceiver} from
    "@avalabs/avalanche-ictt/interfaces/IERC20SendAndCallReceiver.sol";
import {INativeSendAndCallReceiver} from
    "@avalabs/avalanche-ictt/interfaces/INativeSendAndCallReceiver.sol";

// Mock contract to be deployed on the destination chain
contract ERC20UsersMock is IERC20SendAndCallReceiver {
    uint256[] public users;

    function addUser(
        uint256 id
    ) public {
        users.push(id);
    }

    function getUsers() external view returns (uint256[] memory) {
        return users;
    }

    function receiveTokens(
        bytes32, /* sourceBlockchainID */
        address, /* originTokenTransferrerAddress */
        address, /* originSenderAddress */
        address, /* token */
        uint256, /* amount */
        bytes calldata payload
    ) external override {
        uint256 id = abi.decode(payload, (uint256));
        addUser(id);
    }
}

contract NativeUsersMock is INativeSendAndCallReceiver {
    uint256[] public users;

    function addUser(
        uint256 id
    ) public {
        users.push(id);
    }

    function getUsers() external view returns (uint256[] memory) {
        return users;
    }

    function receiveTokens(
        bytes32, /* sourceBlockchainID */
        address, /* originTokenTransferrerAddress */
        address, /* originSenderAddress */
        bytes calldata payload
    ) external payable override {
        uint256 id = abi.decode(payload, (uint256));
        addUser(id);
    }
}

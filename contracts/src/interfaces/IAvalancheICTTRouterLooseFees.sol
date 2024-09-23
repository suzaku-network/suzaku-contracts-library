// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

// Compatible with OpenZeppelin Contracts ^4.8.0

pragma solidity 0.8.18;

import {DestinationBridge, IAvalancheICTTRouter} from "./IAvalancheICTTRouter.sol";

/// @custom:security-contact security@e36knots.com
interface IAvalancheICTTRouterLooseFees is IAvalancheICTTRouter {
    /**
     * @notice Bridge ERC20 token to a destination chain
     * @param tokenAddress Address of the ERC20 token contract
     * @param destinationChainID ID of the destination chain
     * @param amount Amount of token bridged
     * @param recipient Address of the receiver of the tokens
     * @param multiHopFallback Address that will receive the amount bridged in the case of a multihop disfunction
     * @param primaryRelayerFeeBips Fee for the relayer transmitting the message to the destination chain (in bips)
     * @param secondaryRelayerFeeBips Fee for the second relayer in the case of a multihop bridge (in bips)
     */
    function bridgeERC20(
        address tokenAddress,
        bytes32 destinationChainID,
        uint256 amount,
        address recipient,
        address multiHopFallback,
        uint256 primaryRelayerFeeBips,
        uint256 secondaryRelayerFeeBips
    ) external;

    /**
     * @notice Bridge native token to a destination chain
     * @param destinationChainID ID of the destination chain
     * @param recipient Address of the receiver of the tokens
     * @param feeToken Address of the fee token
     * @param multiHopFallback Address that will receive the amount bridged in the case of a multihop disfunction
     * @param primaryRelayerFeeBips Fee for the relayer transmitting the message to the destination chain (in bips)
     * @param secondaryRelayerFeeBips Fee for the second relayer in the case of a multihop bridge (in bips)
     */
    function bridgeNative(
        bytes32 destinationChainID,
        address recipient,
        address feeToken,
        address multiHopFallback,
        uint256 primaryRelayerFeeBips,
        uint256 secondaryRelayerFeeBips
    ) external payable;
}

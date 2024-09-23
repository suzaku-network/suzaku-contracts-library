// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

// Compatible with OpenZeppelin Contracts ^4.8.0

import {IAvalancheICTTRouter, RemoteBridge} from "./IAvalancheICTTRouter.sol";

pragma solidity 0.8.18;

/// @custom:security-contact security@e36knots.com
interface IAvalancheICTTRouterSetFees is IAvalancheICTTRouter {
    /**
     * @notice Issued when changing the value of the relayer fee
     * @param primaryRelayerFee New value of the primary relayer fee
     * @param secondaryRelayerFee New value of the secondary relayer fee
     */
    event ChangeRelayerFees(uint256 primaryRelayerFee, uint256 secondaryRelayerFee);

    /**
     * @notice Change the relayer fee
     * @param primaryRelayerFeeBips_ The relayer fee in basic points
     * @param secondaryRelayerFeeBips_ The relayer fee in basic points (multihop second bridge)
     */
    function setRelayerFeesBips(
        uint256 primaryRelayerFeeBips_,
        uint256 secondaryRelayerFeeBips_
    ) external;

    /**
     * @notice Get the relayer fee in basic points
     * @return primaryRelayerFeeBips The current primary relayer fee in basic points
     * @return secondaryRelayerFeeBips The current secondary relayer fee in basic points
     */
    function getRelayerFeesBips() external view returns (uint256, uint256);

    /**
     * @notice Bridge ERC20 token to a remote chain
     * @param tokenAddress Address of the ERC20 token contract
     * @param remoteChainID ID of the remote chain
     * @param amount Amount of token bridged
     * @param recipient Address of the receiver of the tokens
     * @param multiHopFallback Address that will receive the amount bridged in the case of a multihop disfunction
     */
    function bridgeERC20(
        address tokenAddress,
        bytes32 remoteChainID,
        uint256 amount,
        address recipient,
        address multiHopFallback
    ) external;

    /**
     * @notice Bridge native token to a remote chain
     * @param remoteChainID ID of the remote chain
     * @param recipient Address of the receiver of the tokens
     * @param feeToken Address of the fee token
     * @param multiHopFallback Address that will receive the amount bridged in the case of a multihop disfunction
     */
    function bridgeNative(
        bytes32 remoteChainID,
        address recipient,
        address feeToken,
        address multiHopFallback
    ) external payable;
}

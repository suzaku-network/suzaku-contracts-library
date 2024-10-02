// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

// Compatible with OpenZeppelin Contracts ^4.8.0

import {DestinationBridge, IAvalancheICTTRouter} from "./IAvalancheICTTRouter.sol";

pragma solidity 0.8.18;

/**
 * @title IAvalancheICTTRouterFixedFees
 * @author ADDPHO
 * @notice The complementary interface of the AvalancheICTTRouterFixedFees contract.
 * This interface introduces a new signature for the bridge functions and some relayer fees relating functions (getter, setter, event, error).
 * @custom:security-contact security@suzaku.network
 */
interface IAvalancheICTTRouterFixedFees is IAvalancheICTTRouter {
    error AvalancheICTTRouterFixedFees__CustomRelayerFeesNotAllowed();

    /**
     * @notice Emitted when the value of the fixes relayer fees are updated
     * @param primaryRelayerFee New value of the primary relayer fee
     * @param secondaryRelayerFee New value of the secondary relayer fee
     */
    event UpdateRelayerFees(uint256 primaryRelayerFee, uint256 secondaryRelayerFee);

    /**
     * @notice Update the fixed relayer fees
     * @param primaryRelayerFeeBips_ The relayer fee in basic points
     * @param secondaryRelayerFeeBips_ The relayer fee in basic points (multihop second bridge)
     */
    function updateRelayerFeesBips(
        uint256 primaryRelayerFeeBips_,
        uint256 secondaryRelayerFeeBips_
    ) external;

    /**
     * @notice Get the fixed relayer fees in basic points
     * @return primaryRelayerFeeBips The current primary relayer fee in basic points
     * @return secondaryRelayerFeeBips The current secondary relayer fee in basic points
     */
    function getRelayerFeesBips() external view returns (uint256, uint256);

    /**
     * @notice Bridge ERC20 token to a destination chain. The relayer fees are set by the contract.
     * @param tokenAddress Address of the ERC20 token contract
     * @param destinationChainID ID of the destination chain
     * @param amount Amount of token bridged
     * @param recipient Address of the receiver of the tokens
     * @param multiHopFallback Address that will receive the amount bridged in the case of a multihop disfunction
     */
    function bridgeERC20(
        address tokenAddress,
        bytes32 destinationChainID,
        uint256 amount,
        address recipient,
        address multiHopFallback
    ) external;

    /**
     * @notice Bridge native token to a destination chain. The relayer fees are set by the contract.
     * @param destinationChainID ID of the destination chain
     * @param recipient Address of the receiver of the tokens
     * @param feeToken Address of the fee token
     * @param multiHopFallback Address that will receive the amount bridged in the case of a multihop disfunction
     */
    function bridgeNative(
        bytes32 destinationChainID,
        address recipient,
        address feeToken,
        address multiHopFallback
    ) external payable;
}

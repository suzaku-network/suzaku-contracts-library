// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

// Compatible with OpenZeppelin Contracts ^4.8.0

pragma solidity 0.8.18;

import {IAvalancheICTTRouter} from "../../interfaces/IAvalancheICTTRouter.sol";
import {
    DestinationBridge,
    IAvalancheICTTRouterFixedFees
} from "../../interfaces/IAvalancheICTTRouterFixedFees.sol";
import {AvalancheICTTRouter} from "./AvalancheICTTRouter.sol";
import {WrappedNativeToken} from "@avalabs/avalanche-ictt/WrappedNativeToken.sol";
import {IERC20TokenTransferrer} from "@avalabs/avalanche-ictt/interfaces/IERC20TokenTransferrer.sol";
import {INativeTokenTransferrer} from
    "@avalabs/avalanche-ictt/interfaces/INativeTokenTransferrer.sol";
import {SendTokensInput} from "@avalabs/avalanche-ictt/interfaces/ITokenTransferrer.sol";
import {IWarpMessenger} from
    "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {Ownable} from "@openzeppelin/contracts@4.8.1/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts@4.8.1/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts@4.8.1/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts@4.8.1/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts@4.8.1/utils/Address.sol";
import {SafeERC20TransferFrom} from "@teleporter/SafeERC20TransferFrom.sol";

/**
 * @title AvalancheICTTRouterFixedFees
 * @author Suzaku
 * @notice The AvalancheICTTRouterFixedFees serves the purpose of a router for all transfers initiated from an Avalanche EVM chain through Avalanche ICTT contracts.
 * The difference with the AvalancheICTTRouter contract is that it gives the owner of the contract the possibility to enfore the relayer fees and manage them.
 */
contract AvalancheICTTRouterFixedFees is
    Ownable,
    ReentrancyGuard,
    IAvalancheICTTRouterFixedFees,
    AvalancheICTTRouter
{
    using Address for address;

    /// @notice Relayer fee enforced by the router (in basis points)
    uint256 public primaryRelayerFeeBips;

    /// @notice Relayer fee enforced by the router (in basis points) in case of multihop bridging during the second bridge
    uint256 public secondaryRelayerFeeBips;

    /// @notice Router chain ID
    bytes32 private immutable routerChainID;

    /**
     * @notice Set the relayer fee and the ID of the source chain
     * @param primaryRelayerFeeBips_ Relayer fee in basic points
     * @param secondaryRelayerFeeBips_ In case of multihop bridge, relayer fee for the second bridge
     */
    constructor(uint256 primaryRelayerFeeBips_, uint256 secondaryRelayerFeeBips_) {
        primaryRelayerFeeBips = primaryRelayerFeeBips_;
        secondaryRelayerFeeBips = secondaryRelayerFeeBips_;
        routerChainID = IWarpMessenger(0x0200000000000000000000000000000000000005).getBlockchainID();
    }

    function setRelayerFeesBips(
        uint256 primaryRelayerFeeBips_,
        uint256 secondaryRelayerFeeBips_
    ) external onlyOwner {
        primaryRelayerFeeBips = primaryRelayerFeeBips_;
        secondaryRelayerFeeBips = secondaryRelayerFeeBips_;
        emit AvalancheICTTRouterFixedFees__ChangeRelayerFees(
            primaryRelayerFeeBips_, secondaryRelayerFeeBips_
        );
    }

    function bridgeERC20(
        address tokenAddress,
        bytes32 destinationChainID,
        uint256 amount,
        address recipient,
        address multiHopFallback
    ) external nonReentrant {
        address bridgeSource = tokenToSourceBridge[tokenAddress];
        DestinationBridge memory destinationBridge =
            tokenDestinationChainToDestinationBridge[destinationChainID][tokenAddress];

        uint256 primaryFeeAmount = (amount * primaryRelayerFeeBips) / 10_000;

        uint256 secondaryFeeAmount = (amount * secondaryRelayerFeeBips) / 10_000;

        uint256 adjustedAmount =
            SafeERC20TransferFrom.safeTransferFrom(IERC20(tokenAddress), amount);

        if (!destinationBridge.isMultihop) {
            secondaryFeeAmount = 0;
        }

        uint256 bridgeAmount = adjustedAmount - (primaryFeeAmount + secondaryFeeAmount);

        SafeERC20.safeIncreaseAllowance(IERC20(tokenAddress), bridgeSource, adjustedAmount);

        SendTokensInput memory input = SendTokensInput(
            destinationChainID,
            destinationBridge.bridgeAddress,
            recipient,
            tokenAddress,
            primaryFeeAmount,
            secondaryFeeAmount,
            destinationBridge.requiredGasLimit,
            multiHopFallback
        );
        IERC20TokenTransferrer(bridgeSource).send(input, bridgeAmount);

        emit AvalancheICTTRouter__BridgeERC20(
            tokenAddress, destinationChainID, bridgeAmount, recipient
        );
    }

    function bridgeNative(
        bytes32 destinationChainID,
        address recipient,
        address feeToken,
        address multiHopFallback
    ) external payable nonReentrant {
        address bridgeSource = tokenToSourceBridge[address(0)];
        DestinationBridge memory destinationBridge =
            tokenDestinationChainToDestinationBridge[destinationChainID][address(0)];

        uint256 primaryFeeAmount = (msg.value * primaryRelayerFeeBips) / 10_000;

        uint256 secondaryFeeAmount = (msg.value * secondaryRelayerFeeBips) / 10_000;

        SafeERC20.safeIncreaseAllowance(IERC20(feeToken), bridgeSource, msg.value);
        WrappedNativeToken(payable(feeToken)).deposit{value: primaryFeeAmount}();

        if (!destinationBridge.isMultihop) {
            secondaryFeeAmount = 0;
        }

        uint256 bridgeAmount = msg.value - (primaryFeeAmount + secondaryFeeAmount);

        SendTokensInput memory input = SendTokensInput(
            destinationChainID,
            destinationBridge.bridgeAddress,
            recipient,
            feeToken,
            primaryFeeAmount,
            secondaryFeeAmount,
            destinationBridge.requiredGasLimit,
            multiHopFallback
        );

        INativeTokenTransferrer(bridgeSource).send{value: bridgeAmount}(input);
        emit AvalancheICTTRouter__BridgeNative(destinationChainID, bridgeAmount, recipient);
    }

    function getRelayerFeesBips() external view returns (uint256, uint256) {
        return (primaryRelayerFeeBips, secondaryRelayerFeeBips);
    }

    // REVERT FUNCTIONS
    function bridgeERC20(
        address tokenAddress,
        bytes32 destinationChainID,
        uint256 amount,
        address recipient,
        address multiHopFallback,
        uint256 primaryRelayerFeeBips,
        uint256 secondaryRelayerFeeBips
    ) external override (AvalancheICTTRouter, IAvalancheICTTRouter) nonReentrant {
        revert("Cannot call this function in this contract");
    }

    function bridgeNative(
        bytes32 destinationChainID,
        address recipient,
        address feeToken,
        address multiHopFallback,
        uint256 primaryRelayerFeeBips,
        uint256 secondaryRelayerFeeBips
    ) external payable override (AvalancheICTTRouter, IAvalancheICTTRouter) nonReentrant {
        revert("Cannot call this function in this contract");
    }
}

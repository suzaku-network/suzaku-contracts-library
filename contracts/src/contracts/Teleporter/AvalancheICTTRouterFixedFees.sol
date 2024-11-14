// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

// Compatible with OpenZeppelin Contracts ^4.8.0

pragma solidity 0.8.18;

import {
    DestinationBridge,
    IAvalancheICTTRouter
} from "../../interfaces/Teleporter/IAvalancheICTTRouter.sol";
import {IAvalancheICTTRouterFixedFees} from
    "../../interfaces/Teleporter/IAvalancheICTTRouterFixedFees.sol";
import {AvalancheICTTRouter} from "./AvalancheICTTRouter.sol";
import {WrappedNativeToken} from "@avalabs/avalanche-ictt/WrappedNativeToken.sol";
import {IERC20TokenTransferrer} from "@avalabs/avalanche-ictt/interfaces/IERC20TokenTransferrer.sol";
import {INativeTokenTransferrer} from
    "@avalabs/avalanche-ictt/interfaces/INativeTokenTransferrer.sol";
import {
    SendAndCallInput,
    SendTokensInput
} from "@avalabs/avalanche-ictt/interfaces/ITokenTransferrer.sol";
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
 * @author ADDPHO
 * @notice Equivalent of AvalancheICTTRouter that gives the owner of the contract the possibility to enforce the relayer fees.
 * @custom:security-contact security@suzaku.network
 */
contract AvalancheICTTRouterFixedFees is
    Ownable,
    ReentrancyGuard,
    AvalancheICTTRouter,
    IAvalancheICTTRouterFixedFees
{
    using Address for address;

    /// @notice Relayer fee enforced by the router (in basis points)
    uint256 public primaryRelayerFeeBips;

    /// @notice Relayer fee enforced by the router (in basis points) in case of multihop bridging during the second bridge
    uint256 public secondaryRelayerFeeBips;

    /// @notice Constant to calculate the value of the relayer fees from the basis points
    uint256 private constant BASIS_POINTS_DIVIDER = 10_000;

    constructor(uint256 primaryRelayerFeeBips_, uint256 secondaryRelayerFeeBips_) {
        primaryRelayerFeeBips = primaryRelayerFeeBips_;
        secondaryRelayerFeeBips = secondaryRelayerFeeBips_;
    }

    /// @inheritdoc IAvalancheICTTRouterFixedFees
    function updateRelayerFeesBips(
        uint256 primaryRelayerFeeBips_,
        uint256 secondaryRelayerFeeBips_
    ) external onlyOwner {
        if ((primaryRelayerFeeBips_ + secondaryRelayerFeeBips_) >= BASIS_POINTS_DIVIDER) {
            revert AvalancheICTTRouterFixedFees__CumulatedFeesExceed100Percent(
                primaryRelayerFeeBips_, secondaryRelayerFeeBips_
            );
        }
        primaryRelayerFeeBips = primaryRelayerFeeBips_;
        secondaryRelayerFeeBips = secondaryRelayerFeeBips_;
        emit UpdateRelayerFees(primaryRelayerFeeBips_, secondaryRelayerFeeBips_);
    }

    /// @inheritdoc IAvalancheICTTRouterFixedFees
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

        uint256 adjustedAmount =
            SafeERC20TransferFrom.safeTransferFrom(IERC20(tokenAddress), amount);

        uint256 primaryFeeAmount = (adjustedAmount * primaryRelayerFeeBips) / BASIS_POINTS_DIVIDER;
        uint256 secondaryFeeAmount = destinationBridge.isMultihop
            ? (amount * secondaryRelayerFeeBips) / BASIS_POINTS_DIVIDER
            : 0;

        uint256 bridgeAmount = adjustedAmount - primaryFeeAmount;

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

        emit BridgeERC20(
            tokenAddress,
            destinationChainID,
            recipient,
            bridgeAmount,
            primaryFeeAmount,
            secondaryFeeAmount
        );
    }

    /// @inheritdoc IAvalancheICTTRouterFixedFees
    function bridgeAndCallERC20(
        address tokenAddress,
        bytes32 destinationChainID,
        uint256 amount,
        address recipient,
        bytes memory recipientPayload,
        address recipientFallback,
        uint256 recipientGasLimit,
        address multiHopFallback
    ) external nonReentrant {
        address bridgeSource = tokenToSourceBridge[tokenAddress];
        DestinationBridge memory destinationBridge =
            tokenDestinationChainToDestinationBridge[destinationChainID][tokenAddress];

        uint256 adjustedAmount =
            SafeERC20TransferFrom.safeTransferFrom(IERC20(tokenAddress), amount);

        uint256 primaryFeeAmount = (adjustedAmount * primaryRelayerFeeBips) / BASIS_POINTS_DIVIDER;
        uint256 secondaryFeeAmount = destinationBridge.isMultihop
            ? (amount * secondaryRelayerFeeBips) / BASIS_POINTS_DIVIDER
            : 0;

        uint256 bridgeAmount = adjustedAmount - primaryFeeAmount;

        SafeERC20.safeIncreaseAllowance(IERC20(tokenAddress), bridgeSource, adjustedAmount);

        SendAndCallInput memory input = SendAndCallInput(
            destinationChainID,
            destinationBridge.bridgeAddress,
            recipient,
            recipientPayload,
            destinationBridge.requiredGasLimit,
            recipientGasLimit,
            multiHopFallback,
            recipientFallback,
            tokenAddress,
            primaryFeeAmount,
            secondaryFeeAmount
        );
        IERC20TokenTransferrer(bridgeSource).sendAndCall(input, bridgeAmount);
        emit BridgeAndCallERC20(
            tokenAddress,
            destinationChainID,
            recipient,
            bridgeAmount,
            primaryFeeAmount,
            secondaryFeeAmount
        );
    }

    /// @inheritdoc IAvalancheICTTRouterFixedFees
    function bridgeNative(
        bytes32 destinationChainID,
        address recipient,
        address feeToken,
        address multiHopFallback
    ) external payable nonReentrant {
        address bridgeSource = tokenToSourceBridge[address(0)];
        DestinationBridge memory destinationBridge =
            tokenDestinationChainToDestinationBridge[destinationChainID][address(0)];

        uint256 primaryFeeAmount = (msg.value * primaryRelayerFeeBips) / BASIS_POINTS_DIVIDER;
        uint256 secondaryFeeAmount = destinationBridge.isMultihop
            ? (msg.value * secondaryRelayerFeeBips) / BASIS_POINTS_DIVIDER
            : 0;

        SafeERC20.safeIncreaseAllowance(IERC20(feeToken), bridgeSource, msg.value);
        WrappedNativeToken(payable(feeToken)).deposit{value: primaryFeeAmount}();

        uint256 bridgeAmount = msg.value - primaryFeeAmount;

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
        emit BridgeNative(
            destinationChainID, recipient, bridgeAmount, primaryFeeAmount, secondaryFeeAmount
        );
    }

    /// @inheritdoc IAvalancheICTTRouterFixedFees
    function bridgeAndCallNative(
        bytes32 destinationChainID,
        address recipient,
        address feeToken,
        bytes memory recipientPayload,
        address recipientFallback,
        uint256 recipientGasLimit,
        address multiHopFallback
    ) external payable nonReentrant {
        address bridgeSource = tokenToSourceBridge[address(0)];
        DestinationBridge memory destinationBridge =
            tokenDestinationChainToDestinationBridge[destinationChainID][address(0)];

        uint256 primaryFeeAmount = (msg.value * primaryRelayerFeeBips) / BASIS_POINTS_DIVIDER;
        uint256 secondaryFeeAmount = destinationBridge.isMultihop
            ? (msg.value * secondaryRelayerFeeBips) / BASIS_POINTS_DIVIDER
            : 0;

        SafeERC20.safeIncreaseAllowance(IERC20(feeToken), bridgeSource, msg.value);
        WrappedNativeToken(payable(feeToken)).deposit{value: primaryFeeAmount}();

        uint256 bridgeAmount = msg.value - primaryFeeAmount;

        SendAndCallInput memory input = SendAndCallInput(
            destinationChainID,
            destinationBridge.bridgeAddress,
            recipient,
            recipientPayload,
            destinationBridge.requiredGasLimit,
            recipientGasLimit,
            multiHopFallback,
            recipientFallback,
            feeToken,
            primaryFeeAmount,
            secondaryFeeAmount
        );

        INativeTokenTransferrer(bridgeSource).sendAndCall{value: bridgeAmount}(input);
        emit BridgeAndCallNative(
            destinationChainID, recipient, bridgeAmount, primaryFeeAmount, secondaryFeeAmount
        );
    }

    /// @inheritdoc IAvalancheICTTRouterFixedFees
    function getRelayerFeesBips() external view returns (uint256, uint256) {
        return (primaryRelayerFeeBips, secondaryRelayerFeeBips);
    }

    /// @notice Always revert as custom relayer fees are not allowed in AvalancheICTTRouterFixedFees
    function bridgeERC20(
        address, /*tokenAddress*/
        bytes32, /*destinationChainID*/
        uint256, /*amount*/
        address, /*recipient*/
        address, /*multiHopFallback*/
        address, /* primaryFeeTokenAddress */
        uint256, /*primaryRelayerFeeBips*/
        uint256 /*secondaryRelayerFeeBips*/
    ) external override (AvalancheICTTRouter, IAvalancheICTTRouter) nonReentrant {
        revert AvalancheICTTRouterFixedFees__CustomRelayerFeesNotAllowed();
    }

    /// @notice Always revert as custom relayer fees are not allowed in AvalancheICTTRouterFixedFees
    function bridgeAndCallERC20(
        address, /* tokenAddress */
        bytes32, /* destinationChainID */
        uint256, /* amount */
        address, /* recipient */
        bytes memory, /* recipientPayload */
        address, /* recipientFallback */
        uint256, /* recipientGasLimit */
        address, /* multiHopFallback */
        address, /* primaryFeeTokenAddress */
        uint256, /* primaryRelayerFeeBips */
        uint256 /* secondaryRelayerFeeBips */
    ) external override (AvalancheICTTRouter, IAvalancheICTTRouter) nonReentrant {
        revert AvalancheICTTRouterFixedFees__CustomRelayerFeesNotAllowed();
    }

    /// @notice Always revert as custom relayer fees are not allowed in AvalancheICTTRouterFixedFees
    function bridgeNative(
        bytes32, /*destinationChainID*/
        address, /*recipient*/
        address, /*feeToken*/
        address, /*multiHopFallback*/
        uint256, /*primaryRelayerFeeBips*/
        uint256 /*secondaryRelayerFeeBips*/
    ) external payable override (AvalancheICTTRouter, IAvalancheICTTRouter) nonReentrant {
        revert AvalancheICTTRouterFixedFees__CustomRelayerFeesNotAllowed();
    }

    /// @notice Always revert as custom relayer fees are not allowed in AvalancheICTTRouterFixedFees
    function bridgeAndCallNative(
        bytes32, /* destinationChainID */
        address, /* recipient */
        address, /* feeToken */
        bytes memory, /* recipientPayload */
        address, /* recipientFallback */
        uint256, /* recipientGasLimit */
        address, /* multiHopFallback */
        uint256, /* primaryRelayerFeeBips */
        uint256 /* secondaryRelayerFeeBips */
    ) external payable override (AvalancheICTTRouter, IAvalancheICTTRouter) nonReentrant {
        revert AvalancheICTTRouterFixedFees__CustomRelayerFeesNotAllowed();
    }
}

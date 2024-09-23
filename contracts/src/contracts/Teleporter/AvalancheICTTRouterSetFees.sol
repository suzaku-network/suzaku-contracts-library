// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

// Compatible with OpenZeppelin Contracts ^4.8.0

pragma solidity 0.8.18;

import {IAvalancheICTTRouter} from "../../interfaces/IAvalancheICTTRouter.sol";
import {
    IAvalancheICTTRouterSetFees,
    RemoteBridge
} from "../../interfaces/IAvalancheICTTRouterSetFees.sol";
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
import {SafeMath} from "@openzeppelin/contracts@4.8.1/utils/math/SafeMath.sol";
import {SafeERC20TransferFrom} from "@teleporter/SafeERC20TransferFrom.sol";

/// @custom:security-contact security@e36knots.com
contract AvalancheICTTRouterSetFees is Ownable, ReentrancyGuard, IAvalancheICTTRouterSetFees {
    using Address for address;

    /**
     * @notice Token address => home bridge address
     * @notice Address `0x0` is used for the native token
     */
    mapping(address => address) public tokenToHomeBridge;

    /**
     * @notice Token address => remote chain ID => RemoteBridge
     * @notice Address `0x0` is used for the native token
     */
    mapping(bytes32 => mapping(address => RemoteBridge)) public tokenRemoteChainToRemoteBridge;

    /// @notice Relayer fee enforced by the router (in basis points)
    uint256 public primaryRelayerFeeBips;

    /// @notice Relayer fee enforced by the router (in basis points) in case of multihop bridging during the second bridge
    uint256 public secondaryRelayerFeeBips;

    /// @notice  Current chain ID
    bytes32 private immutable routerChainID;

    /**
     * @notice Set the relayer fee and the ID of the home chain
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
        emit ChangeRelayerFees(primaryRelayerFeeBips_, secondaryRelayerFeeBips_);
    }

    function registerHomeTokenBridge(
        address tokenAddress,
        address bridgeAddress
    ) external onlyOwner {
        require(
            tokenAddress.isContract() || tokenAddress == address(0),
            "TeleporterBridgeRouter: tokenAddress is not a contract"
        );
        require(
            bridgeAddress.isContract(), "TeleporterBridgeRouter: bridgeAddress is not a contract"
        );
        tokenToHomeBridge[tokenAddress] = bridgeAddress;

        emit RegisterHomeTokenBridge(tokenAddress, bridgeAddress);
    }

    function registerRemoteTokenBridge(
        address tokenAddress,
        bytes32 remoteChainID,
        address bridgeAddress,
        uint256 requiredGasLimit,
        bool isMultihop
    ) external onlyOwner {
        require(
            tokenAddress.isContract() || tokenAddress == address(0),
            "TeleporterBridgeRouter: tokenAddress is not a contract"
        );
        require(
            remoteChainID != routerChainID,
            "TeleporterBridgeRouter: remote chain cannot be the same as home chain"
        );
        RemoteBridge memory remoteBridge = RemoteBridge(bridgeAddress, requiredGasLimit, isMultihop);
        tokenRemoteChainToRemoteBridge[remoteChainID][tokenAddress] = remoteBridge;

        emit RegisterRemoteTokenBridge(tokenAddress, remoteBridge, remoteChainID);
    }

    function removeHomeTokenBridge(address tokenAddress) external onlyOwner {
        delete tokenToHomeBridge[tokenAddress];

        emit RemoveHomeTokenBridge(tokenAddress);
    }

    function removeRemoteTokenBridge(
        address tokenAddress,
        bytes32 remoteChainID
    ) external onlyOwner {
        delete tokenRemoteChainToRemoteBridge[remoteChainID][tokenAddress];

        emit RemoveRemoteTokenBridge(tokenAddress, remoteChainID);
    }

    function bridgeERC20(
        address tokenAddress,
        bytes32 remoteChainID,
        uint256 amount,
        address recipient,
        address multiHopFallback
    ) external nonReentrant {
        address bridgeHome = tokenToHomeBridge[tokenAddress];
        RemoteBridge memory remoteBridge =
            tokenRemoteChainToRemoteBridge[remoteChainID][tokenAddress];
        require(bridgeHome != address(0), "TeleporterBridgeRouter: bridge not set for home + token");
        require(
            remoteBridge.bridgeAddress != address(0),
            "TeleporterBridgeRouter: bridge not set for remote + token"
        );

        uint256 primaryFeeAmount = SafeMath.div(SafeMath.mul(amount, primaryRelayerFeeBips), 10_000);

        uint256 secondaryFeeAmount =
            SafeMath.div(SafeMath.mul(amount, secondaryRelayerFeeBips), 10_000);

        uint256 adjustedAmount =
            SafeERC20TransferFrom.safeTransferFrom(IERC20(tokenAddress), amount);

        if (!remoteBridge.isMultihop) {
            secondaryFeeAmount = 0;
        }

        uint256 bridgeAmount = adjustedAmount - (primaryFeeAmount + secondaryFeeAmount);

        SafeERC20.safeIncreaseAllowance(IERC20(tokenAddress), bridgeHome, adjustedAmount);

        SendTokensInput memory input = SendTokensInput(
            remoteChainID,
            remoteBridge.bridgeAddress,
            recipient,
            tokenAddress,
            primaryFeeAmount,
            secondaryFeeAmount,
            remoteBridge.requiredGasLimit,
            multiHopFallback
        );
        IERC20TokenTransferrer(bridgeHome).send(input, bridgeAmount);

        emit BridgeERC20(tokenAddress, remoteChainID, bridgeAmount, recipient);
    }

    function bridgeNative(
        bytes32 remoteChainID,
        address recipient,
        address feeToken,
        address multiHopFallback
    ) external payable nonReentrant {
        address bridgeHome = tokenToHomeBridge[address(0)];
        RemoteBridge memory remoteBridge = tokenRemoteChainToRemoteBridge[remoteChainID][address(0)];
        require(bridgeHome != address(0), "TeleporterBridgeRouter: bridge not set for home");
        require(
            remoteBridge.bridgeAddress != address(0),
            "TeleporterBridgeRouter: bridge not set for remote"
        );

        uint256 primaryFeeAmount =
            SafeMath.div(SafeMath.mul(msg.value, primaryRelayerFeeBips), 10_000);

        uint256 secondaryFeeAmount =
            SafeMath.div(SafeMath.mul(msg.value, secondaryRelayerFeeBips), 10_000);

        SafeERC20.safeIncreaseAllowance(IERC20(feeToken), bridgeHome, msg.value);
        WrappedNativeToken(payable(feeToken)).deposit{value: primaryFeeAmount}();

        if (!remoteBridge.isMultihop) {
            secondaryFeeAmount = 0;
        }

        uint256 bridgeAmount = msg.value - (primaryFeeAmount + secondaryFeeAmount);

        SendTokensInput memory input = SendTokensInput(
            remoteChainID,
            remoteBridge.bridgeAddress,
            recipient,
            feeToken,
            primaryFeeAmount,
            secondaryFeeAmount,
            remoteBridge.requiredGasLimit,
            multiHopFallback
        );

        INativeTokenTransferrer(bridgeHome).send{value: bridgeAmount}(input);
        emit BridgeNative(remoteChainID, bridgeAmount, recipient);
    }

    function getRelayerFeesBips() external view returns (uint256, uint256) {
        return (primaryRelayerFeeBips, secondaryRelayerFeeBips);
    }

    function getHomeBridge(address token) external view returns (address) {
        return tokenToHomeBridge[token];
    }

    function getRemoteBridge(
        bytes32 chainID,
        address token
    ) external view returns (RemoteBridge memory) {
        return tokenRemoteChainToRemoteBridge[chainID][token];
    }
}

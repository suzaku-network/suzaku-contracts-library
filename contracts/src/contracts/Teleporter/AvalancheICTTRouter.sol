// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

// Compatible with OpenZeppelin Contracts ^4.8.0

pragma solidity 0.8.18;

import {DestinationBridge, IAvalancheICTTRouter} from "../../interfaces/IAvalancheICTTRouter.sol";
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

/// @title AvalancheICTTRouter
/// @author Suzaku
/// @notice The AvalancheICTTRouter serves the purpose of a router for all transfers initiated from an Avalanche EVM chain through Avalanche ICTT contracts.
contract AvalancheICTTRouter is Ownable, ReentrancyGuard, IAvalancheICTTRouter {
    using Address for address;

    /**
     * @notice Token address => source bridge address
     * @notice Address `0x0` is used for the native token
     */
    mapping(address token => address sourceBridge) public tokenToSourceBridge;

    /**
     * @notice Token address => destination chain ID => DestinationBridge
     * @notice Address `0x0` is used for the native token
     */
    mapping(
        bytes32 destinationChainID => mapping(address token => DestinationBridge destinationBridge)
    ) public tokenDestinationChainToDestinationBridge;

    /// @notice Router chain ID
    bytes32 private immutable routerChainID;

    /// @notice Set the relayer fee and the ID of the source chain
    constructor() {
        routerChainID = IWarpMessenger(0x0200000000000000000000000000000000000005).getBlockchainID();
    }

    function registerSourceTokenBridge(
        address tokenAddress,
        address bridgeAddress
    ) external onlyOwner {
        if (tokenAddress != address(0) && !tokenAddress.isContract()) {
            revert AvalancheICTTRouter__TokenAddrNotAContract(tokenAddress);
        }
        if (!bridgeAddress.isContract()) {
            revert AvalancheICTTRouter__BridgeAddrNotAContract(bridgeAddress);
        }
        tokenToSourceBridge[tokenAddress] = bridgeAddress;

        emit AvalancheICTTRouter__RegisterSourceTokenBridge(tokenAddress, bridgeAddress);
    }

    function registerDestinationTokenBridge(
        address tokenAddress,
        bytes32 destinationChainID,
        address bridgeAddress,
        uint256 requiredGasLimit,
        bool isMultihop
    ) external onlyOwner {
        if (tokenAddress != address(0) && !tokenAddress.isContract()) {
            revert AvalancheICTTRouter__TokenAddrNotAContract(tokenAddress);
        }
        if (bridgeAddress == address(0)) {
            revert AvalancheICTTRouter__BridgeAddrNotAContract(bridgeAddress);
        }
        if (destinationChainID == routerChainID) {
            revert AvalancheICTTRouter__SourceChainEqualToDestinationChain(
                routerChainID, destinationChainID
            );
        }
        DestinationBridge memory destinationBridge =
            DestinationBridge(bridgeAddress, requiredGasLimit, isMultihop);
        tokenDestinationChainToDestinationBridge[destinationChainID][tokenAddress] =
            destinationBridge;

        emit AvalancheICTTRouter__RegisterDestinationTokenBridge(
            tokenAddress, destinationBridge, destinationChainID
        );
    }

    function removeSourceTokenBridge(address tokenAddress) external onlyOwner {
        delete tokenToSourceBridge[tokenAddress];

        emit AvalancheICTTRouter__RemoveSourceTokenBridge(tokenAddress);
    }

    function removeDestinationTokenBridge(
        address tokenAddress,
        bytes32 destinationChainID
    ) external onlyOwner {
        delete tokenDestinationChainToDestinationBridge[destinationChainID][tokenAddress];

        emit AvalancheICTTRouter__RemoveDestinationTokenBridge(tokenAddress, destinationChainID);
    }

    function bridgeERC20(
        address tokenAddress,
        bytes32 destinationChainID,
        uint256 amount,
        address recipient,
        address multiHopFallback,
        uint256 primaryRelayerFeeBips,
        uint256 secondaryRelayerFeeBips
    ) external virtual nonReentrant {
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
        address multiHopFallback,
        uint256 primaryRelayerFeeBips,
        uint256 secondaryRelayerFeeBips
    ) external payable virtual nonReentrant {
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

    function getSourceBridge(address token) external view returns (address) {
        return tokenToSourceBridge[token];
    }

    function getDestinationBridge(
        bytes32 chainID,
        address token
    ) external view returns (DestinationBridge memory) {
        return tokenDestinationChainToDestinationBridge[chainID][token];
    }
}
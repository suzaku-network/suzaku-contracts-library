// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

// Compatible with OpenZeppelin Contracts ^4.8.0

pragma solidity 0.8.18;

import {DestinationBridge, IAvalancheICTTRouter} from "../../interfaces/IAvalancheICTTRouter.sol";
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
 * @title AvalancheICTTRouter
 * @author ADDPHO
 * @notice The AvalancheICTTRouter allows users to bridge assets between Avalanche EVM L1s through canonical ICTT contracts.
 * @custom:security-contact security@suzaku.network
 */
contract AvalancheICTTRouter is Ownable, ReentrancyGuard, IAvalancheICTTRouter {
    using Address for address;

    /// @notice List of tokens supported by this router on the source chain
    address[] public tokensList;

    /**
     * @notice Token address => source bridge address
     * @notice Address `0x0` is used for the native token
     */
    mapping(address token => address sourceBridge) public tokenToSourceBridge;

    /**
     * @notice Destination chain ID => token address => DestinationBridge
     * @notice Address `0x0` is used for the native token
     */
    mapping(
        bytes32 destinationChainID => mapping(address token => DestinationBridge destinationBridge)
    ) public tokenDestinationChainToDestinationBridge;

    /**
     * @notice Token Address => list of supported destination chains
     * @notice Address `0x0` is used for the native token
     */
    mapping(address token => bytes32[] destinationChainIDsList) public
        tokenToDestinationChainsIDList;

    /// @notice Router chain ID
    bytes32 private immutable routerChainID;

    constructor() {
        routerChainID = IWarpMessenger(0x0200000000000000000000000000000000000005).getBlockchainID();
    }

    /// @inheritdoc IAvalancheICTTRouter
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
        tokensList.push(tokenAddress);

        emit RegisterSourceTokenBridge(tokenAddress, bridgeAddress);
    }

    /// @inheritdoc IAvalancheICTTRouter
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
            revert AvalancheICTTRouter__SourceChainEqualsDestinationChain(
                routerChainID, destinationChainID
            );
        }
        DestinationBridge memory destinationBridge =
            DestinationBridge(bridgeAddress, requiredGasLimit, isMultihop);
        tokenDestinationChainToDestinationBridge[destinationChainID][tokenAddress] =
            destinationBridge;
        tokenToDestinationChainsIDList[tokenAddress].push(destinationChainID);

        emit RegisterDestinationTokenBridge(tokenAddress, destinationChainID, destinationBridge);
    }

    /// @inheritdoc IAvalancheICTTRouter
    function removeSourceTokenBridge(
        address tokenAddress
    ) external onlyOwner {
        delete tokenToSourceBridge[tokenAddress];
        _removeToken(tokenAddress);

        emit RemoveSourceTokenBridge(tokenAddress);
    }

    /// @inheritdoc IAvalancheICTTRouter
    function removeDestinationTokenBridge(
        address tokenAddress,
        bytes32 destinationChainID
    ) external onlyOwner {
        delete tokenDestinationChainToDestinationBridge[destinationChainID][
            tokenAddress
        ];
        _removeDestinationChainID(tokenAddress, destinationChainID);

        emit RemoveDestinationTokenBridge(tokenAddress, destinationChainID);
    }

    /// @inheritdoc IAvalancheICTTRouter
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

        emit BridgeERC20(tokenAddress, destinationChainID, bridgeAmount, recipient);
    }

    /// @inheritdoc IAvalancheICTTRouter
    function bridgeAndCallERC20(
        address tokenAddress,
        bytes32 destinationChainID,
        uint256 amount,
        address recipient,
        bytes memory recipientPayload,
        address recipientFallback,
        uint256 recipientGasLimit,
        uint256 requiredGasLimit,
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

        SendAndCallInput memory input = SendAndCallInput(
            destinationChainID,
            destinationBridge.bridgeAddress,
            recipient,
            recipientPayload,
            requiredGasLimit,
            recipientGasLimit,
            multiHopFallback,
            recipientFallback,
            tokenAddress,
            primaryFeeAmount,
            secondaryFeeAmount
        );
        IERC20TokenTransferrer(bridgeSource).sendAndCall(input, bridgeAmount);
        emit BridgeAndCallERC20(tokenAddress, destinationChainID, bridgeAmount, recipient);
    }

    /// @inheritdoc IAvalancheICTTRouter
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
        emit BridgeNative(destinationChainID, bridgeAmount, recipient);
    }

    /// @inheritdoc IAvalancheICTTRouter
    function bridgeAndCallNative(
        bytes32 destinationChainID,
        address recipient,
        address feeToken,
        bytes memory recipientPayload,
        address recipientFallback,
        uint256 recipientGasLimit,
        uint256 requiredGasLimit,
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

        SendAndCallInput memory input = SendAndCallInput(
            destinationChainID,
            destinationBridge.bridgeAddress,
            recipient,
            recipientPayload,
            requiredGasLimit,
            recipientGasLimit,
            multiHopFallback,
            recipientFallback,
            feeToken,
            primaryFeeAmount,
            secondaryFeeAmount
        );

        INativeTokenTransferrer(bridgeSource).sendAndCall{value: bridgeAmount}(input);
        emit BridgeAndCallNative(destinationChainID, bridgeAmount, recipient);
    }

    /// @inheritdoc IAvalancheICTTRouter
    function getSourceBridge(
        address token
    ) external view returns (address) {
        return tokenToSourceBridge[token];
    }

    /// @inheritdoc IAvalancheICTTRouter
    function getDestinationBridge(
        bytes32 chainID,
        address token
    ) external view returns (DestinationBridge memory) {
        return tokenDestinationChainToDestinationBridge[chainID][token];
    }

    /// @inheritdoc IAvalancheICTTRouter
    function getTokensList() external view returns (address[] memory) {
        return (tokensList);
    }

    /// @inheritdoc IAvalancheICTTRouter
    function getDestinationChainsForToken(
        address token
    ) external view returns (bytes32[] memory) {
        return (tokenToDestinationChainsIDList[token]);
    }

    /**
     * @notice Remove a token from the tokensList array (internal function)
     * @param token The address of the token
     */
    function _removeToken(
        address token
    ) internal {
        uint256 tokensNumber = tokensList.length;
        for (uint256 i; i < tokensNumber; ++i) {
            if (tokensList[i] == token) {
                tokensList[i] = tokensList[tokensList.length - 1];
                tokensList.pop();
                break;
            }
        }
    }

    /**
     * @notice Remove a destination chain from the list of destination chain associated with a token (internal function)
     * @param token The address of the token
     * @param chainID The ID of the destination chain
     */
    function _removeDestinationChainID(address token, bytes32 chainID) internal {
        uint256 chainsNumber = tokenToDestinationChainsIDList[token].length;
        for (uint256 i; i < chainsNumber; ++i) {
            if (tokenToDestinationChainsIDList[token][i] == chainID) {
                tokenToDestinationChainsIDList[token][i] =
                    tokenToDestinationChainsIDList[token][tokensList.length - 1];
                tokenToDestinationChainsIDList[token].pop();
                break;
            }
        }
    }
}

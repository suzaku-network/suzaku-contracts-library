// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

// Compatible with OpenZeppelin Contracts 5.0.2

pragma solidity 0.8.25;

import {
    DestinationBridge, IAvalancheICTTRouter
} from "../../interfaces/ICM/IAvalancheICTTRouter.sol";
import {WrappedNativeToken} from "@avalabs/icm-contracts/ictt/WrappedNativeToken.sol";
import {IERC20TokenTransferrer} from
    "@avalabs/icm-contracts/ictt/interfaces/IERC20TokenTransferrer.sol";
import {INativeTokenTransferrer} from
    "@avalabs/icm-contracts/ictt/interfaces/INativeTokenTransferrer.sol";
import {
    SendAndCallInput,
    SendTokensInput
} from "@avalabs/icm-contracts/ictt/interfaces/ITokenTransferrer.sol";
import {SafeERC20TransferFrom} from "@avalabs/icm-contracts/utilities/SafeERC20TransferFrom.sol";
import {IWarpMessenger} from
    "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {Ownable} from "@openzeppelin/contracts@5.0.2/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts@5.0.2/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts@5.0.2/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts@5.0.2/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts@5.0.2/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts@5.0.2/utils/structs/EnumerableSet.sol";

/**
 * @title AvalancheICTTRouter
 * @author ADDPHO
 * @notice The AvalancheICTTRouter allows users to bridge assets between Avalanche EVM L1s through canonical ICTT contracts.
 * @custom:security-contact security@suzaku.network
 */
contract AvalancheICTTRouter is Ownable, ReentrancyGuard, IAvalancheICTTRouter {
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @notice List of tokens supported by this router on the source chain
    EnumerableSet.AddressSet internal tokensList;

    /**
     * @notice Token address => source bridge address
     * @notice Address `0x0` is used for the native token
     */
    mapping(address token => address sourceBridge) internal tokenToSourceBridge;

    /**
     * @notice Destination chain ID => token address => DestinationBridge
     * @notice Address `0x0` is used for the native token
     */
    mapping(
        bytes32 destinationChainID => mapping(address token => DestinationBridge destinationBridge)
    ) internal tokenDestinationChainToDestinationBridge;

    /**
     * @notice Token Address => list of supported destination chains
     * @notice Address `0x0` is used for the native token
     */
    mapping(address token => EnumerableSet.Bytes32Set destinationChainIDsList) internal
        tokenToDestinationChainsIDList;

    /// @notice Router chain ID
    bytes32 internal immutable routerChainID;

    constructor(
        address initialOwner
    ) Ownable(initialOwner) {
        routerChainID = IWarpMessenger(0x0200000000000000000000000000000000000005).getBlockchainID();
    }

    /// @inheritdoc IAvalancheICTTRouter
    function registerSourceTokenBridge(
        address tokenAddress,
        address bridgeAddress
    ) external onlyOwner {
        if (tokenAddress != address(0) && tokenAddress.code.length == 0) {
            revert AvalancheICTTRouter__TokenAddrNotAContract(tokenAddress);
        }
        if (bridgeAddress.code.length == 0) {
            revert AvalancheICTTRouter__BridgeAddrNotAContract(bridgeAddress);
        }
        tokenToSourceBridge[tokenAddress] = bridgeAddress;
        tokensList.add(tokenAddress);

        emit RegisterSourceTokenBridge(tokenAddress, bridgeAddress);
    }

    /// @inheritdoc IAvalancheICTTRouter
    function registerDestinationTokenBridge(
        address tokenAddress,
        bytes32 destinationChainID,
        address bridgeAddress,
        uint256 requiredGasLimit,
        bool isMultihop
    ) external virtual onlyOwner {
        _registerDestinationTokenBridge(
            tokenAddress, destinationChainID, bridgeAddress, requiredGasLimit, isMultihop
        );
    }

    /// @inheritdoc IAvalancheICTTRouter
    function removeSourceTokenBridge(
        address tokenAddress
    ) external onlyOwner {
        delete tokenToSourceBridge[tokenAddress];
        tokensList.remove(tokenAddress);

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
        tokenToDestinationChainsIDList[tokenAddress].remove(destinationChainID);

        emit RemoveDestinationTokenBridge(tokenAddress, destinationChainID);
    }

    /// @inheritdoc IAvalancheICTTRouter
    function bridgeERC20(
        address tokenAddress,
        bytes32 destinationChainID,
        uint256 amount,
        address recipient,
        address multiHopFallback,
        address primaryFeeTokenAddress,
        uint256 primaryRelayerFee,
        uint256 secondaryRelayerFee
    ) external virtual nonReentrant {
        address bridgeSource = tokenToSourceBridge[tokenAddress];
        DestinationBridge memory destinationBridge =
            tokenDestinationChainToDestinationBridge[destinationChainID][tokenAddress];

        uint256 adjustedAmount =
            SafeERC20TransferFrom.safeTransferFrom(IERC20(tokenAddress), amount);

        uint256 adjustedPrimaryFee = SafeERC20TransferFrom.safeTransferFrom(
            IERC20(primaryFeeTokenAddress), primaryRelayerFee
        );

        if (!destinationBridge.isMultihop) {
            secondaryRelayerFee = 0;
        }

        SafeERC20.safeIncreaseAllowance(IERC20(tokenAddress), bridgeSource, adjustedAmount);
        SafeERC20.safeIncreaseAllowance(
            IERC20(primaryFeeTokenAddress), bridgeSource, adjustedPrimaryFee
        );

        SendTokensInput memory input = SendTokensInput(
            destinationChainID,
            destinationBridge.bridgeAddress,
            recipient,
            primaryFeeTokenAddress,
            adjustedPrimaryFee,
            secondaryRelayerFee,
            destinationBridge.requiredGasLimit,
            multiHopFallback
        );
        IERC20TokenTransferrer(bridgeSource).send(input, adjustedAmount);

        emit BridgeERC20(
            tokenAddress,
            destinationChainID,
            recipient,
            adjustedAmount,
            adjustedPrimaryFee,
            secondaryRelayerFee
        );
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
        address multiHopFallback,
        address primaryFeeTokenAddress,
        uint256 primaryRelayerFee,
        uint256 secondaryRelayerFee
    ) external virtual nonReentrant {
        address bridgeSource = tokenToSourceBridge[tokenAddress];
        DestinationBridge memory destinationBridge =
            tokenDestinationChainToDestinationBridge[destinationChainID][tokenAddress];

        uint256 adjustedAmount =
            SafeERC20TransferFrom.safeTransferFrom(IERC20(tokenAddress), amount);

        uint256 adjustedPrimaryFee = SafeERC20TransferFrom.safeTransferFrom(
            IERC20(primaryFeeTokenAddress), primaryRelayerFee
        );

        if (!destinationBridge.isMultihop) {
            secondaryRelayerFee = 0;
        }

        SafeERC20.safeIncreaseAllowance(IERC20(tokenAddress), bridgeSource, adjustedAmount);
        SafeERC20.safeIncreaseAllowance(
            IERC20(primaryFeeTokenAddress), bridgeSource, adjustedPrimaryFee
        );

        SendAndCallInput memory input = SendAndCallInput(
            destinationChainID,
            destinationBridge.bridgeAddress,
            recipient,
            recipientPayload,
            destinationBridge.requiredGasLimit,
            recipientGasLimit,
            multiHopFallback,
            recipientFallback,
            primaryFeeTokenAddress,
            adjustedPrimaryFee,
            secondaryRelayerFee
        );
        IERC20TokenTransferrer(bridgeSource).sendAndCall(input, adjustedAmount);
        emit BridgeAndCallERC20(
            tokenAddress,
            destinationChainID,
            recipient,
            adjustedAmount,
            adjustedPrimaryFee,
            secondaryRelayerFee
        );
    }

    /// @inheritdoc IAvalancheICTTRouter
    function bridgeNative(
        bytes32 destinationChainID,
        address recipient,
        address primaryFeeTokenAddress,
        address multiHopFallback,
        uint256 primaryRelayerFee,
        uint256 secondaryRelayerFee
    ) external payable virtual nonReentrant {
        address bridgeSource = tokenToSourceBridge[address(0)];
        DestinationBridge memory destinationBridge =
            tokenDestinationChainToDestinationBridge[destinationChainID][address(0)];

        uint256 adjustedPrimaryFee = SafeERC20TransferFrom.safeTransferFrom(
            IERC20(primaryFeeTokenAddress), primaryRelayerFee
        );

        SafeERC20.safeIncreaseAllowance(
            IERC20(primaryFeeTokenAddress), bridgeSource, adjustedPrimaryFee
        );

        if (!destinationBridge.isMultihop) {
            secondaryRelayerFee = 0;
        }

        SendTokensInput memory input = SendTokensInput(
            destinationChainID,
            destinationBridge.bridgeAddress,
            recipient,
            primaryFeeTokenAddress,
            adjustedPrimaryFee,
            secondaryRelayerFee,
            destinationBridge.requiredGasLimit,
            multiHopFallback
        );

        INativeTokenTransferrer(bridgeSource).send{value: msg.value}(input);
        emit BridgeNative(
            destinationChainID, recipient, msg.value, adjustedPrimaryFee, secondaryRelayerFee
        );
    }

    /// @inheritdoc IAvalancheICTTRouter
    function bridgeAndCallNative(
        bytes32 destinationChainID,
        address recipient,
        address primaryFeeTokenAddress,
        bytes memory recipientPayload,
        address recipientFallback,
        uint256 recipientGasLimit,
        address multiHopFallback,
        uint256 primaryRelayerFee,
        uint256 secondaryRelayerFee
    ) external payable virtual nonReentrant {
        address bridgeSource = tokenToSourceBridge[address(0)];
        DestinationBridge memory destinationBridge =
            tokenDestinationChainToDestinationBridge[destinationChainID][address(0)];

        uint256 adjustedPrimaryFee = SafeERC20TransferFrom.safeTransferFrom(
            IERC20(primaryFeeTokenAddress), primaryRelayerFee
        );

        SafeERC20.safeIncreaseAllowance(
            IERC20(primaryFeeTokenAddress), bridgeSource, adjustedPrimaryFee
        );

        if (!destinationBridge.isMultihop) {
            secondaryRelayerFee = 0;
        }

        SendAndCallInput memory input = SendAndCallInput(
            destinationChainID,
            destinationBridge.bridgeAddress,
            recipient,
            recipientPayload,
            destinationBridge.requiredGasLimit,
            recipientGasLimit,
            multiHopFallback,
            recipientFallback,
            primaryFeeTokenAddress,
            adjustedPrimaryFee,
            secondaryRelayerFee
        );

        INativeTokenTransferrer(bridgeSource).sendAndCall{value: msg.value}(input);
        emit BridgeAndCallNative(
            destinationChainID, recipient, msg.value, adjustedPrimaryFee, secondaryRelayerFee
        );
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
        return (tokensList.values());
    }

    /// @inheritdoc IAvalancheICTTRouter
    function getDestinationChainsForToken(
        address token
    ) external view returns (bytes32[] memory) {
        return (tokenToDestinationChainsIDList[token].values());
    }

    function _registerDestinationTokenBridge(
        address tokenAddress,
        bytes32 destinationChainID,
        address bridgeAddress,
        uint256 requiredGasLimit,
        bool isMultihop
    ) internal {
        if (tokenAddress != address(0) && tokenAddress.code.length == 0) {
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
        tokenToDestinationChainsIDList[tokenAddress].add(destinationChainID);

        emit RegisterDestinationTokenBridge(tokenAddress, destinationChainID, destinationBridge);
    }
}

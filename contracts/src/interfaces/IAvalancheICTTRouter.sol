// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

// Compatible with OpenZeppelin Contracts ^4.8.0

pragma solidity 0.8.18;

struct DestinationBridge {
    address bridgeAddress;
    uint256 requiredGasLimit;
    bool isMultihop;
}

/**
 * @title IAvalancheICTTRouter
 * @author ADDPHO
 * @notice The interface of the AvalancheICTTRouter contract
 * @custom:security-contact security@suzaku.network
 */
interface IAvalancheICTTRouter {
    error AvalancheICTTRouter__TokenAddrNotAContract(address contractAddress);
    error AvalancheICTTRouter__BridgeAddrNotAContract(address contractAddress);
    error AvalancheICTTRouter__SourceChainEqualsDestinationChain(
        bytes32 sourceChain, bytes32 destinationChain
    );

    /**
     * @notice Emitted when the source bridge is registered for a token
     * @param tokenAddress Address of the ERC20 token contract
     * @param bridgeAddress Address of the bridge contract
     */
    event RegisterSourceTokenBridge(address indexed tokenAddress, address indexed bridgeAddress);

    /**
     * @notice Emitted when a destination bridge is registered for a token
     * @param tokenAddress Address of the ERC20 token contract
     * @param destinationBridge Bridge address on the destination chain and required gas limit
     * @param destinationChainID ID of the destination chain
     */
    event RegisterDestinationTokenBridge(
        address indexed tokenAddress,
        bytes32 indexed destinationChainID,
        DestinationBridge indexed destinationBridge
    );

    /**
     * @notice Emitted when the source bridge is removed for a token
     * @param tokenAddress Address of the ERC20 token contract
     */
    event RemoveSourceTokenBridge(address indexed tokenAddress);

    /**
     * @notice Emitted when a destination bridge is removed for a token
     * @param tokenAddress Address of the ERC20 token contract
     * @param destinationChainID ID of the destination chain
     */
    event RemoveDestinationTokenBridge(
        address indexed tokenAddress, bytes32 indexed destinationChainID
    );

    /**
     * @notice Emitted when ERC20 tokens are bridged
     * @param tokenAddress Address of the ERC20 token contract
     * @param destinationBlockchainID ID of the destination chain
     * @param amount Amount of token bridged
     * @param recipient Address of the receiver of the tokens
     */
    event BridgeERC20(
        address indexed tokenAddress,
        bytes32 indexed destinationBlockchainID,
        uint256 amount,
        address recipient
    );

    /**
     * @notice Emitted when ERC20 tokens are bridged with calldata for a contract recipient
     * @param tokenAddress Address of the ERC20 token contract
     * @param destinationBlockchainID ID of the destination chain
     * @param amount Amount of token bridged
     * @param recipient Address of the contract receiving the tokens
     */
    event BridgeAndCallERC20(
        address indexed tokenAddress,
        bytes32 indexed destinationBlockchainID,
        uint256 amount,
        address recipient
    );

    /**
     * @notice Emitted when native tokens are bridged
     * @param destinationChainID ID of the destination chain
     * @param amount Amount of token bridged
     * @param recipient Address of the receiver of the tokens
     */
    event BridgeNative(bytes32 indexed destinationChainID, uint256 amount, address recipient);

    /**
     * @notice Emitted when native tokens are bridged with calldata for a contract recipient
     * @param destinationChainID ID of the destination chain
     * @param amount Amount of token bridged
     * @param recipient Address of the receiver of the tokens
     */
    event BridgeAndCallNative(
        bytes32 indexed destinationChainID, uint256 amount, address recipient
    );

    /**
     * @notice Register the source bridge for a token
     * @param tokenAddress Address of the ERC20 token contract
     * @param bridgeAddress Address of the bridge contract
     */
    function registerSourceTokenBridge(address tokenAddress, address bridgeAddress) external;

    /**
     * @notice Register a destination bridge for a token
     * @param tokenAddress Address of the ERC20 token contract
     * @param destinationChainID ID of the destination chain
     * @param bridgeAddress Address of the destination bridge contract
     * @param requiredGasLimit Gas limit requirement for sending to a token bridge
     * @param isMultihop True if this bridge is a multihop one
     */
    function registerDestinationTokenBridge(
        address tokenAddress,
        bytes32 destinationChainID,
        address bridgeAddress,
        uint256 requiredGasLimit,
        bool isMultihop
    ) external;

    /**
     * @notice Remove the source bridge for a token
     * @param tokenAddress Address of the ERC20 token contract
     */
    function removeSourceTokenBridge(address tokenAddress) external;

    /**
     * @notice Remove a destination bridge for a token
     * @param tokenAddress Address of the ERC20 token contract
     * @param destinationChainID ID of the destination chain
     */
    function removeDestinationTokenBridge(
        address tokenAddress,
        bytes32 destinationChainID
    ) external;

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
     * @notice Bridge ERC20 token and call a contract function on the destination chain
     * @param tokenAddress Address of the ERC20 token contract
     * @param destinationChainID ID of the destination chain
     * @param amount Amount of token bridged
     * @param recipient Contract on the destination chain
     * @param recipientPayload Function signature with parameters hashed of the contract
     * @param recipientFallback Address that will receive the amount bridged in the case of a contract call fail
     * @param multiHopFallback Address that will receive the amount bridged in the case of a multihop disfunction
     * @param primaryRelayerFeeBips Fee for the relayer transmitting the message to the destination chain (in bips)
     * @param secondaryRelayerFeeBips Fee for the second relayer in the case of a multihop bridge (in bips)
     */
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

    /**
     * @notice Bridge native token and call a contract function on the destination chain
     * @param destinationChainID ID of the destination chain
     * @param recipient Contract on the destination chain
     * @param feeToken Address of the fee token
     * @param recipientPayload Function signature with parameters hashed of the contract
     * @param recipientFallback Address that will receive the amount bridged in the case of a contract call fail
     * @param multiHopFallback Address that will receive the amount bridged in the case of a multihop disfunction
     * @param primaryRelayerFeeBips Fee for the relayer transmitting the message to the destination chain (in bips)
     * @param secondaryRelayerFeeBips Fee for the second relayer in the case of a multihop bridge (in bips)
     */
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
    ) external payable;

    /**
     * @notice Get the source bridge contract for a token
     * @param token The address of the ERC20 token
     * @return sourceBridge Address of the bridge source instance
     */
    function getSourceBridge(address token) external view returns (address);

    /**
     * @notice Get the destinationBridge for a token and a destination chain
     * @param chainID The ID of the chain
     * @param token The address of the ERC20 token
     * @return destinationBridge The address of the bridge instance on the destination chain and the required gas limit
     */
    function getDestinationBridge(
        bytes32 chainID,
        address token
    ) external view returns (DestinationBridge memory);

    /**
     * @notice Get the list of tokens supported by this router on the source chain
     * @return tokensList The list of tokens
     */
    function getTokensList() external view returns (address[] memory);

    /**
     * @notice Get the list of the destination chains for a supported token
     * @param token The address of the token
     * @return destinationChainIDsList The list of destination chain IDs
     */
    function getDestinationChainsForToken(address token) external view returns (bytes32[] memory);
}

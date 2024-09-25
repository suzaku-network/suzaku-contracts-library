// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

// Compatible with OpenZeppelin Contracts ^4.8.0

pragma solidity 0.8.18;

struct DestinationBridge {
    address bridgeAddress;
    uint256 requiredGasLimit;
    bool isMultihop;
}

/// @custom:security-contact security@e36knots.com
interface IAvalancheICTTRouter {
    /**
     * @notice Issued when an address is not that of a contract
     * @param contractAddress Address of the supposedly contract
     */
    error NotAContract(address contractAddress);

    /**
     * @notice Issued when the source chain and the destination chain are the same
     * @param sourceChain ID of the source chain (chain on which the router is deployed)
     * @param destinationChain ID of the destination chain
     */
    error SourceChainEqualToDestinationChain(bytes32 sourceChain, bytes32 destinationChain);

    /**
     * @notice Issued when registering a new bridge source instance
     * @param tokenAddress Address of the ERC20 token contract
     * @param bridgeAddress Address of the bridge contract
     */
    event RegisterSourceTokenBridge(address indexed tokenAddress, address indexed bridgeAddress);

    /**
     * @notice Issued when registering a new bridge destination
     * @param tokenAddress Address of the ERC20 token contract
     * @param destinationBridge Bridge destination instance and required gas limit
     * @param destinationChainID ID of the destination chain
     */
    event RegisterDestinationTokenBridge(
        address indexed tokenAddress,
        DestinationBridge indexed destinationBridge,
        bytes32 indexed destinationChainID
    );

    /**
     * @notice Issued when deleting a bridge source instance
     * @param tokenAddress Address of the ERC20 token contract
     */
    event RemoveSourceTokenBridge(address indexed tokenAddress);

    /**
     * @notice Issued when deleting a bridge destination
     * @param tokenAddress Address of the ERC20 token contract
     * @param destinationChainID ID of the destination chain
     */
    event RemoveDestinationTokenBridge(
        address indexed tokenAddress, bytes32 indexed destinationChainID
    );

    /**
     * @notice Issued when bridging an ERC20 token
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
     * @notice Issued when bridging a native token
     * @param destinationChainID ID of the destination chain
     * @param amount Amount of token bridged
     * @param recipient Address of the receiver of the tokens
     */
    event BridgeNative(bytes32 indexed destinationChainID, uint256 amount, address recipient);

    /**
     * @notice Register a new source bridge instance
     * @param tokenAddress Address of the ERC20 token contract
     * @param bridgeAddress Address of the bridge contract
     */
    function registerSourceTokenBridge(address tokenAddress, address bridgeAddress) external;

    /**
     * @notice Register a new destination bridge
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
     * @notice Delete a bridge source instance
     * @param tokenAddress Address of the ERC20 token contract
     */
    function removeSourceTokenBridge(address tokenAddress) external;

    /**
     * @notice Delete a bridge destination
     * @param tokenAddress Address of the ERC20 token contract
     * @param destinationChainID ID of the destination chain
     */
    function removeDestinationTokenBridge(
        address tokenAddress,
        bytes32 destinationChainID
    ) external;

    /**
     * @notice Get the source bridge contract via the ERC20 token
     * @param token The address of the ERC20 token
     * @return sourceBridge Address of the bridge source instance
     */
    function getSourceBridge(address token) external view returns (address);

    /**
     * @notice Get the destinationBridge via the ERC20 token and the chain
     * @param chainID The ID of the chain
     * @param token The address of the ERC20 token
     * @return destinationBridge The address of the bridge instance on the destination chain and the required gas limit
     */
    function getDestinationBridge(
        bytes32 chainID,
        address token
    ) external view returns (DestinationBridge memory);
}

// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

// Compatible with OpenZeppelin Contracts ^4.8.0

pragma solidity 0.8.18;

struct RemoteBridge {
    address bridgeAddress;
    uint256 requiredGasLimit;
    bool isMultihop;
}

/// @custom:security-contact security@e36knots.com
interface IAvalancheICTTRouter {
    /**
     * @notice Issued when registering a new bridge home instance
     * @param tokenAddress Address of the ERC20 token contract
     * @param bridgeAddress Address of the bridge contract
     */
    event RegisterHomeTokenBridge(address indexed tokenAddress, address indexed bridgeAddress);

    /**
     * @notice Issued when registering a new bridge remote
     * @param tokenAddress Address of the ERC20 token contract
     * @param remoteBridge Bridge remote instance and required gas limit
     * @param remoteChainID ID of the remote chain
     */
    event RegisterRemoteTokenBridge(
        address indexed tokenAddress,
        RemoteBridge indexed remoteBridge,
        bytes32 indexed remoteChainID
    );

    /**
     * @notice Issued when deleting a bridge home instance
     * @param tokenAddress Address of the ERC20 token contract
     */
    event RemoveHomeTokenBridge(address indexed tokenAddress);

    /**
     * @notice Issued when deleting a bridge remote
     * @param tokenAddress Address of the ERC20 token contract
     * @param remoteChainID ID of the remote chain
     */
    event RemoveRemoteTokenBridge(address indexed tokenAddress, bytes32 indexed remoteChainID);

    /**
     * @notice Issued when bridging an ERC20 token
     * @param tokenAddress Address of the ERC20 token contract
     * @param remoteBlockchainID ID of the remote chain
     * @param amount Amount of token bridged
     * @param recipient Address of the receiver of the tokens
     */
    event BridgeERC20(
        address indexed tokenAddress,
        bytes32 indexed remoteBlockchainID,
        uint256 amount,
        address recipient
    );

    /**
     * @notice Issued when bridging a native token
     * @param remoteChainID ID of the remote chain
     * @param amount Amount of token bridged
     * @param recipient Address of the receiver of the tokens
     */
    event BridgeNative(bytes32 indexed remoteChainID, uint256 amount, address recipient);

    /**
     * @notice Register a new home bridge instance
     * @param tokenAddress Address of the ERC20 token contract
     * @param bridgeAddress Address of the bridge contract
     */
    function registerHomeTokenBridge(address tokenAddress, address bridgeAddress) external;

    /**
     * @notice Register a new remote bridge
     * @param tokenAddress Address of the ERC20 token contract
     * @param remoteChainID ID of the remote chain
     * @param bridgeAddress Address of the remote bridge contract
     * @param requiredGasLimit Gas limit requirement for sending to a token bridge
     * @param isMultihop True if this bridge is a multihop one
     */
    function registerRemoteTokenBridge(
        address tokenAddress,
        bytes32 remoteChainID,
        address bridgeAddress,
        uint256 requiredGasLimit,
        bool isMultihop
    ) external;

    /**
     * @notice Delete a bridge home instance
     * @param tokenAddress Address of the ERC20 token contract
     */
    function removeHomeTokenBridge(address tokenAddress) external;

    /**
     * @notice Delete a bridge remote
     * @param tokenAddress Address of the ERC20 token contract
     * @param remoteChainID ID of the remote chain
     */
    function removeRemoteTokenBridge(address tokenAddress, bytes32 remoteChainID) external;

    /**
     * @notice Get the home bridge contract via the ERC20 token
     * @param token The address of the ERC20 token
     * @return homeBridge Address of the bridge home instance
     */
    function getHomeBridge(address token) external view returns (address);

    /**
     * @notice Get the RemoteBridge via the ERC20 token and the chain
     * @param chainID The ID of the chain
     * @param token The address of the ERC20 token
     * @return remoteBridge The address of the bridge instance on the remote chain and the required gas limit
     */
    function getRemoteBridge(
        bytes32 chainID,
        address token
    ) external view returns (RemoteBridge memory);
}

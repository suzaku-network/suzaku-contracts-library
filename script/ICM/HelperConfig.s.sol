// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {WarpMessengerMock} from "../../src/contracts/mocks/WarpMessengerMock.sol";

import {Script, console} from "forge-std/Script.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        uint256 deployerKey;
        address teleporterManager;
        address tokenAddress;
        address wrappedTokenAddress;
        string tokenName;
        string tokenSymbol;
        string nativeAssetSymbol;
        uint256 initialReserveImbalance;
        uint256 burnedFeesReportingRewardPercentage;
        uint256 primaryRelayerFeeBips;
        uint256 secondaryRelayerFeeBips;
        address tokenHomeTeleporterRegistryAddress;
        bytes32 tokenHomeBlockchainID;
        uint8 tokenHomeTokenDecimals;
        address tokenHomeAddress;
        address tokenRemoteTeleporterRegistryAddress;
        uint8 tokenRemoteTokenDecimals;
    }

    uint256 public _deployerKey = vm.envUint("BRIDGE_DEPLOYER_PRIV_KEY");
    address public _teleporterManager = vm.envAddress("TELEPORTER_MANAGER_ADDR");
    uint256 public _primaryRelayerFeeBips = vm.envUint("PRIMARY_RELAYER_FEE_BIPS");
    uint256 public _secondaryRelayerFeeBips = vm.envUint("SECONDARY_RELAYER_FEE_BIPS");
    bytes32 public _tokenHomeBlockchainID = vm.envBytes32("HOME_CHAIN_HEX");

    NetworkConfig public activeNetworkConfig;

    uint256 public homeChainId = vm.envUint("HOME_CHAIN_ID");
    uint256 public remoteChainId = vm.envUint("REMOTE_CHAIN_ID");

    constructor() {
        if (block.chainid == homeChainId) {
            activeNetworkConfig = getHomeChainConfig();
        } else if (block.chainid == remoteChainId) {
            activeNetworkConfig = getRemoteChainConfig();
        }
    }

    function getHomeChainConfig() public returns (NetworkConfig memory) {
        address _tokenHomeTeleporterRegistryAddress = vm.envAddress("HOME_REGISTRY_CONTRACT_ADDR");
        address _tokenAddress = vm.envAddress("ERC20_TOKEN_CONTRACT_ADDR");
        // address _wrappedTokenAddress = vm.envAddress("WRAPPED_TOKEN_ADDRESS");
        uint8 _tokenDecimals = uint8(vm.envUint("ERC20_TOKEN_DEC"));
        return NetworkConfig({
            deployerKey: _deployerKey,
            teleporterManager: _teleporterManager,
            tokenAddress: _tokenAddress,
            wrappedTokenAddress: address(0),
            tokenName: "",
            tokenSymbol: "",
            nativeAssetSymbol: "",
            initialReserveImbalance: 0,
            burnedFeesReportingRewardPercentage: 0,
            primaryRelayerFeeBips: _primaryRelayerFeeBips,
            secondaryRelayerFeeBips: _secondaryRelayerFeeBips,
            tokenHomeTeleporterRegistryAddress: _tokenHomeTeleporterRegistryAddress,
            tokenHomeBlockchainID: _tokenHomeBlockchainID,
            tokenHomeTokenDecimals: _tokenDecimals,
            tokenHomeAddress: address(0),
            tokenRemoteTeleporterRegistryAddress: address(0),
            tokenRemoteTokenDecimals: 0
        });
    }

    function getRemoteChainConfig() public returns (NetworkConfig memory) {
        address _tokenRemoteTeleporterRegistryAddress =
            vm.envAddress("REMOTE_CHAIN_TELEPORTER_REGISTRY");
        address _tokenHomeAddress = vm.envAddress("HOME_CHAIN_BRIDGE_ADDRESS");
        string memory _tokenName = vm.envString("ERC20_TOKEN_NAME");
        string memory _tokenSymbol = vm.envString("ERC20_TOKEN_SYMBOL");
        uint8 _tokenDecimals = uint8(vm.envUint("ERC20_TOKEN_DECIMALS"));
        string memory _nativeAssetSymbol = vm.envString("NATIVE_ASSET_SYMBOL");
        uint256 _initialReserveImbalance = uint256(vm.envUint("INITIAL_RESERVE_IMBALANCE"));
        uint256 _burnedFeesReportingRewardPercentage =
            uint256(vm.envUint("BURNED_FEES_REPORTING_REWARD_PERCENTAGE"));
        return NetworkConfig({
            deployerKey: _deployerKey,
            teleporterManager: _teleporterManager,
            tokenAddress: address(0),
            wrappedTokenAddress: address(0),
            tokenName: _tokenName,
            tokenSymbol: _tokenSymbol,
            nativeAssetSymbol: _nativeAssetSymbol,
            initialReserveImbalance: _initialReserveImbalance,
            burnedFeesReportingRewardPercentage: _burnedFeesReportingRewardPercentage,
            primaryRelayerFeeBips: _primaryRelayerFeeBips,
            secondaryRelayerFeeBips: _secondaryRelayerFeeBips,
            tokenHomeTeleporterRegistryAddress: address(0),
            tokenHomeBlockchainID: _tokenHomeBlockchainID,
            tokenHomeTokenDecimals: _tokenDecimals,
            tokenHomeAddress: _tokenHomeAddress,
            tokenRemoteTeleporterRegistryAddress: _tokenRemoteTeleporterRegistryAddress,
            tokenRemoteTokenDecimals: _tokenDecimals
        });
    }
}

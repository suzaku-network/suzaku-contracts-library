# Suzaku ICM Contracts Library

## Introduction

The purpose of this repo is to have a router for all transfers initiated from an Avalanche EVM chain through [Avalanche ICTT](https://github.com/ava-labs/icm-contracts/tree/main/contracts/ictt) bridges.

The bridge contracts are canonical and unique to each token, making the use of a router to map these instances logical, as it can be confusing to identify the correct bridge for the token you want to transfer.

For that we created two contracts: `AvalancheICTTRouter` and `AvalancheICTTRouterFixedFees`.

> Note that we use the terms `Source` and `Destination` chains because, when interacting with a router, we cannot distinguish a `Home` and `Remote` chain. The `Source` chain refers to the chain where the router you are interacting with is deployed, while the `Destination` chain refers to the chain you want to connect to. Therefore, the `Source` chain is not necessarily the `Home` chain.

## AvalancheICTTRouter

To register a new bridge, you need first to deploy the `Transferrer` contracts on both the `Home` chain and the `Remote` chain. When this is done, you have to deploy the router contract on both chain. Then you call the functions `registerSourceTokenBridge()` and `registerDestinationTokenBridge()`.

The `registerSourceTokenBridge()` takes as inputs:

- The address of the token on the router chain
- The address fo the bridge associated with the token

The `registerDestinationTokenBridge()` takes as inputs:

- The address of the token on the router chain
- The ID of the destination chain
- The address of the bridge associated with the token
- The amount limit of gas required for a bridging transaction
- A boolean variable attesting of the nature of the bridge (multihop or not)

The boolean variable is used in the case of a bridge between two remote chains: in that case, the token first needs to be bridged back to its home chain before being bridged to the desired remote chain.

The contract store this infos in different mappings to accurately find them back when bridging later on.

> Note that if you want to bridge a native token, you must call those registering functions with the address `0x0` as the token address.

> Additionally, note that these opt-in functions can only be invoked by the owner of the routing contract, who is designated at the time of the contract's deployment.

After registering the bridges, you can execute a bridge transfer from the router. There is 4 types of bridging:

- `bridgeERC20()`: bridge an ERC20 asset
- `bridgeAndCallERC20()`: bridge an ERC20 asset and interact with a smart contract on the `Destination` chain
- `bridgeNative()`: bridge the native asset of the `Source` chain
- `bridgeAndCallNative()`: bridge the native asset of the `Source` chain and interact with a smart contract on the `Destination` chain

| **ERC20**                               | **Native**                                            |
| --------------------------------------- | ----------------------------------------------------- |
| `bridgeERC20()` takes as inputs:        | `bridgeNative()` takes as inputs:                     |
| - The address of the ERC20 token        | - The ID of the destination chain                     |
| - The ID of the destination chain       | - The address of the receiver of the tokens           |
| - The amount of tokens to bridge        | - The address of the fee token                        |
| - The address of the receiver           | - The fallback receiver for multihop                  |
| - The fallback receiver for multihop    | - The amount of tokens to pay as the optional ICM fee |
| - The fee token to pay the relayer      | - The ICM fee for multihop (if any)                   |
| - The optional ICM fee                  |                                                       |
| - The ICM fee for multihop (if any)     |                                                       |
| `bridgeAndCallERC20()` adds:            | `bridgeAndCallNative()` adds:                         |
| - The function signature and params     | - The function signature and params                   |
| - The fallback receiver on failure      | - The fallback receiver on failure                    |
| - The gas amount for recipient contract | - The gas amount for recipient contract               |

> Note that the native function are `payable` meaning you will need to pass a `msg.value` when you call this function to indicate the amount to bridge.

## AvalancheICTTRouterFixedFees

The flow of this router contract is globaly the same as `AvalancheICTTRouter` with the exception that the fees are fixed with this one. Meaning that the relayer fees are taken from the amount bridged and are chosen by the owner of the router when deploying it (it can always be modified later on by the owner by calling the function `updateRelayerFeesBips()`).

To ensure that the amount bridged is enough to pay the relayer, the owner enforces a minimal fee value that will revert the bridge function if the amount is too small.

So 2 new inputs are added to the `registerDestinationTokenBridge()`:

- The minimal amount of tokens to pay as the ICM fee
- The minimal amount of tokens to pay for ICM fee if a multi-hop is needed

And the 2 ICM fees inputs from the bridge functions are removed in this contract.

> Note that there are getter functions in these router contracts to get the the list of tokens registered on the router (`getTokensList()`) or even the source bridge instance associated with a token (`getSourceBridge()`), for example.

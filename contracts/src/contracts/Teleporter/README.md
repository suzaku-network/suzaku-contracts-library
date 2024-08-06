# Suzaku Teleporter Contracts Library

## AvalancheICTTRouter

This contract serves the purpose of a router for all transfers initiated from an Avalanche EVM chain through [Avalanche ICTT](https://github.com/ava-labs/avalanche-interchain-token-transfer) contracts.

After deploying a `Transferrer` between an Home chain and a Remote chain, you can register this bridge on the router. This way, if you have multiple bridges deployed on one chain, instead of searching for the correct bridge contract, you can just call the router with the token address, the chain and the recipient address.

To register a new bridge, you need first to deploy the `Transferrer` contracts on both the Home chain and the Remote chain. When this is done, you have to deploy the router contract on both chain. Then you call the functions `registerHomeTokenBridge()` and `registerRemoteTokenBridge()`.

The `registerHomeTokenBridge()` takes a token address (A) and a bridge address (B) as parameters. With this, when you want to bridge the token (A) from this chain to a remote one, the router will know that it is the bridge (B) that needs to be use.

The `registerRemoteTokenBridge()` takes as parameters a token address (A), the ID of the remote chain (B), a bridge address (C), a required gas limit (D) and a boolean variable that indicates if the bridge needs a multihop (E). With this, when you want to bridge the token (A), the router will know which bridge (C) to use on which remote chain (B). The required gas limit (D) is needed to tell the router the limit of gas when bridging to this bridge instance on this remote chain. The boolean variable is used in the case of a bridge between two remote chains: in that case, the token (A) first needs to be bridged back to its home chain before being bridged to the desired remote chain (B).

Note that if you want to bridge a native token, you must call those registering functions with the address `0x0` as the token address.

After registering the bridge, you can call the bridge functions from the router: `bridgeERC20()` and `bridgeNative()`. The parameters of these functions are fewer and more concrete than those of the original `send()` functions from the bridge contracts.

For `bridgeERC20()`:

- The address of the token you want to bridge
- The ID of the chain you want to bridge to
- The amount of token you want to bridge
- The address of the recipient you want to send your tokens to
- A fallback address in case of a failed multihop bridge

For `bridgeNative()`:

- The ID of the chain you want to bridge to
- The address of the recipient you want to send your tokens to
- The address of the fee token
- A fallback address in case of a failed multihop bridge

Note that this function is `payable` meaning you will need to pass a `msg.value` when you call this function to indicate the amount to bridge.

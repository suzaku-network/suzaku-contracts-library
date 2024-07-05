# Suzaku Contracts Library

An open-source smart contracts library curated by the Suzaku team.

This library provides utility contracts for different blockchain ecosystems, notably Avalanche.

## Avalanche ecosystem

### Teleporter contracts library

#### Contracts

- The [AvalancheICTTRouter](contracts/src/Teleporter/AvalancheICTTRouter.sol) contract is a router contract that can be used as backend for bridge UIs built on top of [Avalanche ICTT](https://github.com/ava-labs/avalanche-interchain-token-transfer).  
  It tracks the Home and Remote `TokenTransferrer` contracts on multiple chains to initiate transfers by only providing the token to transfer, the destination chain ID and the recipient address.

#### Scripts

Foundry deployment scripts for [Avalanche ICTT](https://github.com/ava-labs/avalanche-interchain-token-transfer) Home and Remote contracts at [contracts/script/Teleporter](contracts/script/Teleporter):

- [DeployERC20TokenHome.s.sol](contracts/script/Teleporter/DeployERC20TokenHome.s.sol)
- [DeployNativeTokenHome.s.sol](contracts/script/Teleporter/DeployNativeTokenHome.s.sol)
- [DeployERC20TokenRemote.s.sol](contracts/script/Teleporter/DeployERC20TokenRemote.s.sol)
- [DeployNativeTokenRemote.s.sol](contracts/script/Teleporter/DeployNativeTokenRemote.s.sol)

Those scripts make use of environment variables to deploy the contracts. See [HelperConfig.s.sol](contracts/script/Teleporter/HelperConfig.s.sol) for more details.

## Usage

To use the library in your project, you can install it with `forge`:

```bash
forge install suzaku-network/suzaku-contracts-library
```

## Development

```bash
cd contracts

forge install
forge build
forge test
```

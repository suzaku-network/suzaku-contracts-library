# Suzaku Contracts Library

An open-source smart contracts library curated by the Suzaku team.

This library provides utility contracts for different blockchain ecosystems, notably Avalanche.

## Avalanche ecosystem

### Teleporter contracts library

#### Contracts

- The [AvalancheICTTRouter](contracts/src/contracts/Teleporter/AvalancheICTTRouter.sol) contract is a router contract that can be used as backend for bridge UIs built on top of [Avalanche ICTT](https://github.com/ava-labs/avalanche-interchain-token-transfer).  
  It tracks the Home and Remote `TokenTransferrer` contracts on multiple chains to initiate transfers by only providing the token to transfer, the destination chain ID and the recipient address.  
  [Read more](contracts/src/contracts/Teleporter/README.md)

#### Scripts

Foundry deployment scripts for [Avalanche ICTT](https://github.com/ava-labs/avalanche-interchain-token-transfer) Home and Remote contracts at [contracts/script/Teleporter](contracts/script/Teleporter):

- [DeployERC20TokenHome.s.sol](contracts/script/Teleporter/DeployERC20TokenHome.s.sol)
- [DeployNativeTokenHome.s.sol](contracts/script/Teleporter/DeployNativeTokenHome.s.sol)
- [DeployERC20TokenRemote.s.sol](contracts/script/Teleporter/DeployERC20TokenRemote.s.sol)
- [DeployNativeTokenRemote.s.sol](contracts/script/Teleporter/DeployNativeTokenRemote.s.sol)

Those scripts make use of environment variables to deploy the contracts. See [HelperConfig.s.sol](contracts/script/Teleporter/HelperConfig.s.sol) for more details.

### ACP99Manager library

#### Contracts, libraries and interfaces

- The [SubnetValidatorMessages](contracts/src/contracts/ACP99/SubnetValidatorMessages.sol) library provides utility functions to encode and decode validator set update Warp messages.
- The [ACP99Manager](contracts/src/contracts/ACP99/ACP99Manager.sol) contract can be set as the `SubnetManager` address of a Subnet to manage a its validator set. It follows the [ACP-99](https://github.com/Nuttymoon/ACPs/blob/validatorsetmanager-solidity-contract/ACPs/99-validatorsetmanager-contract/README.md) standard.
- The [IACP99Manager](contracts/src/interfaces/ACP99/IACP99Manager.sol) interface defines the functions that a contract must implement to be a `ACP99Manager`.

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

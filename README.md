# Suzaku Contracts Library

An open-source smart contracts library curated by the Suzaku team.

This library provides utility contracts for different blockchain ecosystems, notably Avalanche.

## Avalanche ecosystem

### ICM contracts library

Check more informations [here](src/contracts/ICM/).

#### Contracts, librairies and interface

- The [IAvalancheICTTRouter](src/interfaces/ICM/IAvalancheICTTRouter.sol) interface specifies the functions a contract must implement to act as a `Router` on an Avalanche EVM chain.
- The [IAvalancheICTTRouterFixedFees](src/interfaces/ICM/IAvalancheICTTRouterFixedFees.sol) interface extends `IAvalancheICTTRouter` by defining additional functions for an "enforced fixed fees" `Router` on an Avalanche EVM chain.
- The [AvalancheICTTRouter](src/contracts/ICM/AvalancheICTTRouter.sol) contract serves as a routing contract that maps tokens to their canonical bridges, simplifying interactions with the Avalanche ICM contracts.
- The [AvalancheICTTRouterFixedFees](src/contracts/ICM/AvalancheICTTRouterFixedFees.sol) contract builds on `AvalancheICTTRouter` by adding fee enforcement for bridging.

### ACP99 contracts library

#### Contracts, libraries and interfaces

- The [ValidatorMessages](contracts/src/contracts/ACP99/ValidatorMessages.sol) library provides utility functions to encode and decode validator set update Warp messages.
- The [ACP99Manager](contracts/src/contracts/ACP99/ACP99Manager.sol) contract can be set as the `SubnetManager` address of a L1 to manage its validator set. It follows the [ACP-99](https://github.com/Nuttymoon/ACPs/blob/validatorsetmanager-solidity-contract/ACPs/99-validatorsetmanager-contract/README.md) standard.
- The [IACP99Manager](contracts/src/interfaces/ACP99/IACP99Manager.sol) interface defines the functions that a contract must implement to be an `ACP99Manager`.
- The [IACP99SecurityModule](contracts/src/interfaces/ACP99/IACP99SecurityModule.sol) interface defines the functions that a security module must implement to work with the `ACP99Manager`.
- The [ACP99PoAModule](contracts/src/contracts/ACP99/SecurityModules/ACP99PoAModule.sol) contract is an example implementation of a Proof-of-Authority security module that works with the `ACP99Manager`.

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

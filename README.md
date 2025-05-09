# Suzaku Contracts Library

An open-source smart contracts library curated by the Suzaku team.

This library provides utility contracts for different blockchain ecosystems, notably Avalanche.

## Avalanche ecosystem

### Validator Manager Contracts

The Validator Manager contracts provide a flexible system for managing validator sets with multiple security modules.

#### Contracts, libraries and interfaces

- The [BalancerValidatorManager](src/contracts/ValidatorManager/BalancerValidatorManager.sol) contract allows multiple security modules to control portions of the validator set with weight limits
- The [PoASecurityModule](src/contracts/ValidatorManager/SecurityModule/PoASecurityModule.sol) implements a Proof of Authority security module
- The [IBalancerValidatorManager](src/interfaces/ValidatorManager/IBalancerValidatorManager.sol) interface defines the functions for balancing validator weights across security modules

Key features:

- Multiple security modules can operate independently
- Each security module has a maximum weight allocation
- Support for validator registration, removal and weight updates
- Built-in weight tracking and enforcement
- Upgradeable from PoA Validator Manager

### ICM contracts library

Check more information [here](src/contracts/ICM/).

#### Contracts, libraries and interfaces

- The [IAvalancheICTTRouter](src/interfaces/ICM/IAvalancheICTTRouter.sol) interface specifies the functions a contract must implement to act as a `Router` on an Avalanche EVM chain.
- The [IAvalancheICTTRouterFixedFees](src/interfaces/ICM/IAvalancheICTTRouterFixedFees.sol) interface extends `IAvalancheICTTRouter` by defining additional functions for an "enforced fixed fees" `Router` on an Avalanche EVM chain.
- The [AvalancheICTTRouter](src/contracts/ICM/AvalancheICTTRouter.sol) contract serves as a routing contract that maps tokens to their canonical bridges, simplifying interactions with the Avalanche ICM contracts.
- The [AvalancheICTTRouterFixedFees](src/contracts/ICM/AvalancheICTTRouterFixedFees.sol) contract builds on `AvalancheICTTRouter` by adding fee enforcement for bridging.

### ACP99 contracts library

Contracts and interfaces in the `ACP99/` directories were PoC for the ACP-99 standard. They are not maintained and should not be used in production.

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

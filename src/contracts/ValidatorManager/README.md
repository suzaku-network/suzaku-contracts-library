# Balancer Validator Manager

The `BalancerValidatorManager` contract inherits from `ValidatorManager` and implements a validator management system that allows multiple security modules to control portions of the validator set. Each security module is allocated a maximum weight they can assign to their validators.

The `BalancerValidatorManager` also adds useful getters for the underlying `ValidatorManager` contract state.

## Key Features

- Multiple security modules can operate independently to manage validators
- Each security module has a maximum weight allocation they cannot exceed
- Tracks and enforces security module weight limits

## Key Functions

### Security Module Management

- `setUpSecurityModule`: register a new security module with a maximum weight allocation
- `getSecurityModules`: get the list of registered security modules
- `getSecurityModuleWeights`: get the current weight and maximum weight allocation for a module

### Validator Management

New functions in `BalancerValidatorManager`:

- `initializeValidatorRegistration`: begin validator registration process with security module weight tracking
- `initializeEndValidation`: begin validator removal process with security module weight updates
- `initializeValidatorWeightUpdate`: begin validator weight update process with security module weight tracking
- `completeEndValidation`: complete validator removal process
- `completeValidatorWeightUpdate`: complete validator weight update process
- `resendValidatorWeightUpdate`: resend validator weight update message

Functions inherited from `ValidatorManager`:

- `completeValidatorRegistration`: complete validator registration process
- `resendRegisterValidatorMessage`: resend validator registration message
- `resendEndValidatorMessage`: resend validator removal message

### Getters

Functions implemented in `BalancerValidatorManager`:

- `getSecurityModules`: get the list of registered security modules
- `getSecurityModuleWeights`: get the current weight and maximum weight allocation for a module
- `isValidatorPendingWeightUpdate`: check if validator has pending weight update
- `getChurnPeriodSeconds`: get the churn period duration
- `getMaximumChurnPercentage`: get the maximum allowed churn percentage
- `getCurrentChurnPeriod`: get the current churn period details

Functions inherited from `ValidatorManager`:

- `getValidator` - get the validator details
- `registeredValidators` - get the validation ID for a node ID

## Usage

Security modules must implement the required interfaces to interact with this contract. The contract owner can register security modules and set their maximum weight allocations.

Each security module can then independently manage their validator set within their weight limits, while the base `ValidatorManager` functionality ensures overall system stability.

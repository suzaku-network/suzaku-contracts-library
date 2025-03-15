// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

struct PoAUpgradeConfig {
    address proxyAddress;
    uint64 initialSecurityModuleMaxWeight;
    bytes[] migratedValidators;
    uint256 proxyAdminOwnerKey;
    uint256 validatorManagerOwnerKey;
    bytes32 l1ID;
    uint64 churnPeriodSeconds;
    uint8 maximumChurnPercentage;
}

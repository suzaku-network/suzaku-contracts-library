// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

struct BalancerMigrationConfig {
    address proxyAddress;
    address validatorManagerProxy;
    address poaManager;
    uint64 initialSecurityModuleMaxWeight;
    bytes[] migratedValidators;
    address proxyAdminOwnerAddress;
    address validatorManagerOwnerAddress;
    bytes32 subnetID;
    uint64 churnPeriodSeconds;
    uint8 maximumChurnPercentage;
}

// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";

/**
 * @notice This test file is temporarily disabled because it tests upgrading from v1 PoAValidatorManager
 * to BalancerValidatorManager, but v2.1 of icm-contracts no longer includes PoAValidatorManager.
 * 
 * The v2.1 architecture uses ValidatorManager + PoAManager separately instead of the monolithic
 * PoAValidatorManager from v1.
 * 
 * To properly test upgrades in v2.1 context, you would need to:
 * 1. Deploy the new ValidatorManager + PoAManager pair
 * 2. Migrate existing validators
 * 3. Deploy BalancerValidatorManager to wrap the ValidatorManager
 * 4. Transfer ownership from PoAManager to BalancerValidatorManager
 */
contract PoAToBalancerValidatorManagerTest is Test {
    function testDisabled() public {
        // This test suite is disabled for v2.1 compatibility
        vm.skip(true);
    }
}
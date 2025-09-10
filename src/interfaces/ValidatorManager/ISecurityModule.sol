// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {IERC165} from "@openzeppelin/contracts@5.0.2/utils/introspection/IERC165.sol";

/**
 * @title ISecurityModule
 * @author ADDPHO
 * @notice Uniform operational interface implemented by Balancer security modules.
 * @dev
 * - Intended for generic on-chain callers (keepers, governance).
 * - Functions are the permissionless “ops” used to progress/repair validator state.
 * - Implementers MUST support ERC‑165 and return true for `type(ISecurityModule).interfaceId`.
 * @custom:security-contact security@suzaku.network
 */
interface ISecurityModule is IERC165 {
    /**
     * @notice Completes a validator registration after P‑Chain acknowledgment.
     * @param messageIndex The index of the Warp message carrying the registration result.
     * @return validationID The ID of the acknowledged validation period.
     */
    function completeValidatorRegistration(
        uint32 messageIndex
    ) external returns (bytes32 validationID);

    /**
     * @notice Completes a validator removal after P‑Chain acknowledgment.
     * @param messageIndex The index of the Warp message carrying the removal result.
     * @return validationID The ID of the acknowledged validation period.
     */
    function completeValidatorRemoval(
        uint32 messageIndex
    ) external returns (bytes32 validationID);

    /**
     * @notice Completes a validator weight update after P‑Chain acknowledgment.
     * @param messageIndex The index of the Warp message carrying the weight update acknowledgment.
     * @return validationID The ID of the validation period.
     * @return nonce The acknowledged validator message nonce.
     */
    function completeValidatorWeightUpdate(
        uint32 messageIndex
    ) external returns (bytes32 validationID, uint64 nonce);
}

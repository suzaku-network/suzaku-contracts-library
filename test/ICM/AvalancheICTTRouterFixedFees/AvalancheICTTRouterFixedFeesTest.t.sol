// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.25;

import {AvalancheICTTRouterFixedFees} from
    "../../../src/contracts/ICM/AvalancheICTTRouterFixedFees.sol";

import {WarpMessengerTestMock} from "../../../src/contracts/mocks/WarpMessengerTestMock.sol";
import {IAvalancheICTTRouterFixedFees} from
    "../../../src/interfaces/ICM/IAvalancheICTTRouterFixedFees.sol";
import {HelperConfig4Test} from "../HelperConfig4Test.t.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract AvalancheICTTRouterFixedFeesTest is Test {
    address private constant WARP_PRECOMPILE = 0x0200000000000000000000000000000000000005;

    address private constant TOKEN_SRC = 0xDe09E74d4888Bc4e65F589e8c13Bce9F71DdF4c7;

    uint256 private constant PRIM_RELAYER_FEE_BIPS = 20;
    uint256 private constant SEC_RELAYER_FEE_BIPS = 20;

    event UpdateRelayerFees(uint256 primaryRelayerFee, uint256 secondaryRelayerFee);

    HelperConfig4Test helperConfig = new HelperConfig4Test();

    uint256 deployerKey;
    address owner;

    AvalancheICTTRouterFixedFees tokenBridgeRouter;

    function setUp() external {
        (deployerKey, owner,) = helperConfig.activeNetworkConfigTest();

        WarpMessengerTestMock warpMessengerTestMock = new WarpMessengerTestMock(TOKEN_SRC);
        vm.etch(WARP_PRECOMPILE, address(warpMessengerTestMock).code);
        vm.startBroadcast(deployerKey);
        tokenBridgeRouter =
            new AvalancheICTTRouterFixedFees(PRIM_RELAYER_FEE_BIPS, SEC_RELAYER_FEE_BIPS, owner);
        vm.stopBroadcast();
    }

    function testSetRelayerFees() public {
        vm.startPrank(owner);
        (uint256 primaryRelayerFeeBipsStart, uint256 secondaryRelayerFeeBipsStart) =
            tokenBridgeRouter.getRelayerFeesBips();

        tokenBridgeRouter.updateRelayerFeesBips(50, 30);

        (uint256 primaryRelayerFeeBipsEnd, uint256 secondaryRelayerFeeBipsEnd) =
            tokenBridgeRouter.getRelayerFeesBips();

        assert(primaryRelayerFeeBipsStart != primaryRelayerFeeBipsEnd);
        assert(secondaryRelayerFeeBipsStart != secondaryRelayerFeeBipsEnd);
        assert(primaryRelayerFeeBipsEnd == 50 && secondaryRelayerFeeBipsEnd == 30);
        vm.stopPrank();
    }

    function testRevertsOnRelayerFeesSetIfFeesBipsTooHigh() public {
        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAvalancheICTTRouterFixedFees
                    .AvalancheICTTRouterFixedFees__CumulatedFeesExceed100Percent
                    .selector,
                5000,
                5000
            )
        );
        tokenBridgeRouter.updateRelayerFeesBips(5000, 5000);
        vm.stopPrank();
    }

    function testEmitsOnRelayerFeesSet() public {
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, false, address(tokenBridgeRouter));
        emit UpdateRelayerFees(50, 20);
        tokenBridgeRouter.updateRelayerFeesBips(50, 20);
        vm.stopPrank();
    }
}

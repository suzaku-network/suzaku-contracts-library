// SPDX-License-Identifier: UNLICENSED
// SPDX-FileCopyrightText: Copyright 2024 ADDPHO

pragma solidity 0.8.18;

import {AvalancheICTTRouterFixedFees} from
    "../../../src/contracts/Teleporter/AvalancheICTTRouterFixedFees.sol";

import {WarpMessengerTestMock} from "../../../src/contracts/mocks/WarpMessengerTestMock.sol";
import {IAvalancheICTTRouterFixedFees} from
    "../../../src/interfaces/Teleporter/IAvalancheICTTRouterFixedFees.sol";
import {HelperConfig4Test} from "../HelperConfig4Test.t.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract AvalancheICTTRouterFixedFeesTest is Test {
    address private constant TOKEN_SOURCE = 0x6D411e0A54382eD43F02410Ce1c7a7c122afA6E1;

    event UpdateRelayerFees(uint256 primaryRelayerFee, uint256 secondaryRelayerFee);

    HelperConfig4Test helperConfig = new HelperConfig4Test(TOKEN_SOURCE, 1);

    uint256 deployerKey;
    address owner;
    bytes32 messageId;
    address warpPrecompileAddress;
    WarpMessengerTestMock warpMessengerTestMock;

    AvalancheICTTRouterFixedFees tokenBridgeRouter;

    function setUp() external {
        (
            deployerKey,
            owner,
            ,
            messageId,
            warpPrecompileAddress,
            warpMessengerTestMock,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            tokenBridgeRouter,
            ,
            ,
            ,
            ,
        ) = helperConfig.activeNetworkConfigTest();

        vm.etch(warpPrecompileAddress, address(warpMessengerTestMock).code);
    }

    function testSetRelayerFees() public {
        vm.startPrank(owner);
        (uint256 primaryRelayerFeeBipsStart, uint256 secondaryRelayerFeeBipsStart) =
            tokenBridgeRouter.getRelayerFeesBips();

        tokenBridgeRouter.updateRelayerFeesBips(50, 20);

        (uint256 primaryRelayerFeeBipsEnd, uint256 secondaryRelayerFeeBipsEnd) =
            tokenBridgeRouter.getRelayerFeesBips();

        assert(primaryRelayerFeeBipsStart != primaryRelayerFeeBipsEnd);
        assert(secondaryRelayerFeeBipsStart != secondaryRelayerFeeBipsEnd);
        assert(primaryRelayerFeeBipsEnd == 50 && secondaryRelayerFeeBipsEnd == 20);
        vm.stopPrank();
    }

    function testRevertsOnRelayerFeesSetIfFeesBipsTooHigh() public {
        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAvalancheICTTRouterFixedFees.AvalancheICTTRouterFixedFees__FeesBipsTooHigh.selector,
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

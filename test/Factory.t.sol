// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test, console2} from "forge-std/Test.sol";
import {Factory} from "../src/Factory.sol";
import {Token0, Token1} from "../src/mock/Tokens.sol";

contract FactoryTest is Test {
    Factory public factory;
    address public owner;
    address public token0;
    address public token1;

    function setUp() public {
        owner = vm.addr(123);
        vm.label(owner, "owner");

        Token0 _token0 = new Token0();
        Token1 _token1 = new Token1();

        (token0, token1) = address(_token0) < address(_token1)
            ? (address(_token0), address(_token1))
            : (address(_token1), address(_token0));

        factory = new Factory(owner);

        assertEq(factory.allPairsLength(), 0);
        assertEq(factory.owner(), owner);
        assertEq(factory.feeTo(), address(0));
    }

    function testCreatePair() public {
        factory.createPair(token0, token1);
        address pair = factory.getPair(token0, token1);

        assertEq(factory.allPairsLength(), 1);
        assertEq(factory.allPairs(0), pair);
    }

    function testCreatePairFail() public {
        vm.expectRevert(Factory.Factory_Identical_Addresses.selector);
        factory.createPair(token0, token0);

        vm.expectRevert(Factory.Factory_Zero_Address.selector);
        factory.createPair(token0, address(0));

        factory.createPair(token0, token1);

        vm.expectRevert(Factory.Factory_Pair_Already_Exists.selector);
        factory.createPair(token0, token1);
    }

    function testSetFeeTo() public {
        vm.prank(owner);
        factory.setFeeTo(owner);

        assertEq(factory.feeTo(), owner);
    }
}

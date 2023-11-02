// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test, console2} from "forge-std/Test.sol";
import {ShareToken} from "../src/ShareToken.sol";

contract TokenTest is Test {
    ShareToken public token;
    address public owner;
    address public user1;

    function setUp() public {
        owner = vm.addr(123);
        vm.label(owner, "owner");

        user1 = vm.addr(456);
        vm.label(owner, "user1");

        vm.prank(owner);
        token = new ShareToken();
    }

    function testMintAndBurn() public {
        vm.startPrank(owner);
        token.mint(user1, 1 ether);

        assertEq(token.balanceOf(user1), 1 ether);

        token.burn(user1, 1 ether);
        assertEq(token.balanceOf(user1), 0);

        vm.stopPrank();
    }
}

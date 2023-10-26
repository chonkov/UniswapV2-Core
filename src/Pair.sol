// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IPair} from "./interfaces/IPair.sol";

contract Pair is IPair {
    function initialize(address token0, address token1) external {}
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Token0 is ERC20 {
    constructor() ERC20("Token0", "TKN0") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract Token1 is ERC20 {
    constructor() ERC20("Token1", "TKN1") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

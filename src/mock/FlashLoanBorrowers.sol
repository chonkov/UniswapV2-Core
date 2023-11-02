// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IERC3156FlashBorrower} from "lib/openzeppelin-contracts/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "lib/openzeppelin-contracts/contracts/interfaces/IERC3156FlashLender.sol";
import {ERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract FlashBorrower is IERC3156FlashBorrower, ERC165 {
    IERC3156FlashLender lender;
    uint256 public counter;

    constructor(IERC3156FlashLender lender_) {
        lender = lender_;
    }

    /// @dev ERC-3156 Flash loan callback
    function onFlashLoan(
        address initiator,
        address, /* token*/
        uint256, /* amount*/
        uint256, /*fee*/
        bytes calldata /*data*/
    ) external override returns (bytes32) {
        require(msg.sender == address(lender));
        require(initiator == address(this));

        counter++;

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    /// @dev Initiate a flash loan
    function flashBorrow(address token, uint256 amount) public {
        uint256 _allowance = IERC20(token).allowance(address(this), address(lender));
        uint256 _fee = lender.flashFee(token, amount); // 0
        uint256 _repayment = amount + _fee; // amount
        IERC20(token).approve(address(lender), _allowance + _repayment);
        lender.flashLoan(IERC3156FlashBorrower(address(this)), token, amount, "");
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165) returns (bool) {
        return interfaceId == type(IERC3156FlashBorrower).interfaceId;
    }
}

contract InvalidFlashBorrower1 is ERC165 {
    function supportsInterface(bytes4 /* interfaceId */ ) public view virtual override(ERC165) returns (bool) {
        return false;
    }
}

contract InvalidFlashBorrower2 is IERC3156FlashBorrower, ERC165 {
    IERC3156FlashLender lender;

    constructor(IERC3156FlashLender lender_) {
        lender = lender_;
    }

    function onFlashLoan(
        address, /* initiator*/
        address, /* token*/
        uint256, /* amount*/
        uint256, /*fee*/
        bytes calldata /*data*/
    ) external override returns (bytes32) {
        return keccak256("ERC3156FlashBorrower.0nFlashLoan");
    }

    function flashBorrow(address token, uint256 amount) public {
        uint256 _allowance = IERC20(token).allowance(address(this), address(lender));
        uint256 _fee = lender.flashFee(token, amount); // 0
        uint256 _repayment = amount + _fee; // amount
        IERC20(token).approve(address(lender), _allowance + _repayment);
        lender.flashLoan(IERC3156FlashBorrower(address(this)), token, amount, "");
    }

    function supportsInterface(bytes4 /* interfaceId */ ) public view virtual override(ERC165) returns (bool) {
        return true;
    }
}

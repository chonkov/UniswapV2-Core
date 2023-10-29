// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Context} from "lib/openzeppelin-contracts/contracts/utils/Context.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {UD60x18, ud, MAX_WHOLE_UD60x18} from "lib/prb-math/src/UD60x18.sol";
import {IPair} from "./interfaces/IPair.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {ICallee} from "./interfaces/ICallee.sol";
import {ShareToken} from "./ShareToken.sol";

error Pair_Locked();
error Pair_Insufficient_Amounts();
error Pair_Insufficient_Liquidity();
error Pair_Insufficient_Liquidity_Minted();
error Pair_Insufficient_Liquidity_Burned();
error Pair_Overflow();
error Pair_Invalid_Receiver();
error Pair_Invalid_K();

contract Pair is IPair, Context, ShareToken {
    using SafeERC20 for IERC20;

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    address public immutable factory;
    address public immutable token0;
    address public immutable token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    bool private unlocked = true;

    modifier lock() {
        if (!unlocked) revert Pair_Locked();
        unlocked = false;
        _;
        unlocked = true;
    }

    constructor(address _token0, address _token1) {
        factory = _msgSender();
        token0 = _token0;
        token1 = _token1;
    }

    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) revert Pair_Overflow();

        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;

        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            UD60x18 udReserve0 = ud(_reserve0);
            UD60x18 udReserve1 = ud(_reserve1);

            price0CumulativeLast += udReserve1.div(udReserve0).unwrap() * timeElapsed;
            price1CumulativeLast += udReserve0.div(udReserve1).unwrap() * timeElapsed;
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;

        emit Sync(reserve0, reserve1);
    }

    function _mintFee(uint256 _reserve0, uint256 _reserve1) private returns (bool feeOn) {
        address feeTo = IFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast;

        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = Math.sqrt(_reserve0 * _reserve1);
                uint256 rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply() * uint256(rootK - rootKLast);
                    uint256 denominator = rootK * 5 + rootKLast;
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    function mint(address to) external lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        bool feeOn = _mintFee(_reserve0, _reserve1);

        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min((amount0 * _totalSupply) / _reserve0, (amount1 * _totalSupply) / _reserve1);
        }
        if (liquidity == 0) revert Pair_Insufficient_Liquidity_Minted();
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * reserve1;

        emit Mint(_msgSender(), amount0, amount1);
    }

    function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        address _token0 = token0;
        address _token1 = token1;
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply();
        amount0 = (liquidity * balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = (liquidity * balance1) / _totalSupply; // using balances ensures pro-rata distribution

        if (amount0 == 0 || amount1 == 0) revert Pair_Insufficient_Liquidity_Burned();

        _burn(address(this), liquidity);
        IERC20(_token0).safeTransfer(to, amount0);
        IERC20(_token1).safeTransfer(to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);

        if (feeOn) kLast = ud(reserve0).mul(ud(reserve1)).unwrap(); // reserve0 and reserve1 are up-to-date

        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external lock {
        // Example:
        // token0 = ETH, token1 = DAI
        // Before swap is made and no tokens are transfered: reserve0 = 10 ETH, reserve1 = 10,000 DAI => K = 100,000
        // Before `swap` is called - user calls 'transfer' and sends 2,5 ETH => reserve0 = 12,5 ETH => amount0Out = 0 && amount1Out = 2,000
        // amount1Out = reserve1 - K / reserve0' (reserve0' = reserve0 + 2,5 ETH = 12,5 ETH)

        if (amount0Out == 0 && amount1Out == 0) revert Pair_Insufficient_Amounts();
        (uint256 _reserve0, uint256 _reserve1,) = getReserves();

        if (amount0Out >= _reserve0 || amount1Out >= _reserve1) revert Pair_Insufficient_Liquidity();

        uint256 balance0;
        uint256 balance1;
        {
            // scope for _token{0,1}, avoids stack too deep errors

            address _token0 = token0;
            address _token1 = token1;
            if (to == _token0 || to == _token1) revert Pair_Invalid_Receiver();

            if (amount0Out > 0) IERC20(_token0).safeTransfer(to, amount0Out);
            if (amount1Out > 0) IERC20(_token1).safeTransfer(to, amount1Out);
            if (data.length > 0) ICallee(to).uniswapV2Call(_msgSender(), amount0Out, amount1Out, data); // 'FlashSwap'
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }

        // 12,5 ETH > 10 ETH - 0 (amount0Out = 0) => amount0In = 2,5 ETH
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        // 8,000 DAI > 10,000 DAI - 2,000 DAI (amount0Out = 2,000) => amount1In = 0
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;

        if (amount0In == 0 && amount1In == 0) revert Pair_Insufficient_Amounts();
        {
            // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            uint256 balance0Adjusted = balance0 * 1000 - amount0In * 3;
            uint256 balance1Adjusted = balance1 * 1000 - amount1In * 3;
            // (12,5 - dx(amount0In * 3))*(8,000) >= 10 * 10,000, but dx has been already paid as a fee
            if (balance0Adjusted * balance1Adjusted < _reserve0 * _reserve1 * 1000 ** 2) revert Pair_Invalid_K();
        }

        _update(balance0, balance1, uint112(_reserve0), uint112(_reserve1));
        emit Swap(_msgSender(), amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function skim(address to) external lock {
        // Cache storage variables
        address _token0 = token0;
        address _token1 = token1;
        IERC20(_token0).safeTransfer(to, IERC20(_token0).balanceOf(address(this)) - reserve0);
        IERC20(_token1).safeTransfer(to, IERC20(_token1).balanceOf(address(this)) - reserve1);
    }

    function sync() external {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }
}

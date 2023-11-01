// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test, console2} from "forge-std/Test.sol";
import {Factory} from "../src/Factory.sol";
import {Pair} from "../src/Pair.sol";
import {ERC20, IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC3156FlashLender} from "lib/openzeppelin-contracts/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "lib/openzeppelin-contracts/contracts/interfaces/IERC3156FlashBorrower.sol";
import {ERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {UD60x18, ud, MAX_WHOLE_UD60x18} from "lib/prb-math/src/UD60x18.sol";

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

contract PairTest is Test {
    using SafeERC20 for ERC20;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(UD60x18 reserve0, UD60x18 reserve1);

    bytes EMPTY_DATA = "";

    address public token0;
    address public token1;
    Factory public factory;
    Pair public pair;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    function setUp() public {
        owner = vm.addr(123);
        vm.label(owner, "owner");

        user1 = vm.addr(111);
        vm.label(user1, "user1");

        user2 = vm.addr(222);
        vm.label(user2, "user2");

        user3 = vm.addr(333);
        vm.label(user3, "user3");

        Token0 _token0 = new Token0();
        Token1 _token1 = new Token1();

        (token0, token1) = address(_token0) < address(_token1)
            ? (address(_token0), address(_token1))
            : (address(_token1), address(_token0));

        factory = new Factory(owner);
        factory.createPair(token0, token1);
        pair = Pair(factory.getPair(token0, token1));

        // Token0 = WETH
        Token0(token0).mint(user1, 10 ether);
        Token0(token0).mint(user2, 10 ether);
        Token0(token0).mint(user3, 20 ether);

        // Token1 = DAI
        Token1(token1).mint(user1, 100_000 ether);
        Token1(token1).mint(user2, 100_000 ether);
        Token1(token1).mint(user3, 200_000 ether);
    }

    function addLiquidity(uint256 token0Amount, uint256 token1Amount, address to) private {
        ERC20(token0).safeTransfer(address(pair), token0Amount);
        ERC20(token1).safeTransfer(address(pair), token1Amount);
        pair.mint(to);
    }

    function inputAmountPlusFee(UD60x18 x, UD60x18 y, UD60x18 dy) private pure returns (UD60x18 dx) {
        dx = (x.mul(dy).mul(ud(1000)) / y.sub(dy).mul(ud(997))).add(ud(1));
    }

    function testSetUp() public {
        assertEq(factory.allPairsLength(), 1);
        assertEq(factory.allPairs(0), address(pair));
        assertEq(factory.owner(), owner);
        assertEq(factory.feeTo(), address(0));
        assertEq(pair.totalSupply(), 0);
        (UD60x18 reserve0, UD60x18 reserve1, uint32 blockTimestampLast) = pair.getReserves();
        assertEq(reserve0.unwrap(), 0);
        assertEq(reserve1.unwrap(), 0);
        assertEq(blockTimestampLast, 0);
        assertEq(ERC20(token0).balanceOf(user1), 10 ether);
        assertEq(ERC20(token1).balanceOf(user1), 100_000 ether);
    }

    function testSetFeeTo() public {
        vm.prank(owner);
        factory.setFeeTo(owner);
        assertEq(factory.feeTo(), owner);
    }

    function testMint() public {
        uint256 blockTimestamp = block.timestamp;

        (UD60x18 reserve0, UD60x18 reserve1,) = pair.getReserves();
        assertEq(reserve0.unwrap(), 0);
        assertEq(reserve1.unwrap(), 0);

        uint256 amount0 = ERC20(token0).balanceOf(user1);
        uint256 amount1 = ERC20(token1).balanceOf(user1);

        vm.startPrank(user1);
        ERC20(token0).safeTransfer(address(pair), amount0);
        ERC20(token1).safeTransfer(address(pair), amount1);
        vm.expectEmit();
        emit Mint(user1, amount0, amount1);
        pair.mint(user1);
        vm.stopPrank();

        (reserve0, reserve1,) = pair.getReserves();

        assertEq(reserve0.unwrap(), amount0);
        assertEq(reserve1.unwrap(), amount1);
        assertEq(pair.balanceOf(user1) + 1_000, pair.totalSupply());
        assertEq(pair.kLast(), 0);
        assertEq(pair.balanceOf(address(pair.vault())), pair.MINIMUM_LIQUIDITY());

        amount0 = ERC20(token0).balanceOf(user2);
        amount1 = ERC20(token1).balanceOf(user2);

        assertEq(ERC20(token0).balanceOf(user2), 10 ether);
        assertEq(ERC20(token1).balanceOf(user2), 100_000 ether);

        vm.warp(blockTimestamp + 12);

        vm.startPrank(user2);
        addLiquidity(amount0, amount1, user2);
        vm.stopPrank();

        (reserve0, reserve1,) = pair.getReserves();

        assertEq(reserve0.unwrap(), amount0 * 2);
        assertEq(reserve1.unwrap(), amount1 * 2);
        assertEq(ERC20(token0).balanceOf(address(pair)), amount0 * 2);
        assertEq(ERC20(token1).balanceOf(address(pair)), amount1 * 2);
        assertEq(pair.balanceOf(user1) + 1_000, pair.totalSupply() / 2);
        assertEq((pair.balanceOf(user2) * 2), pair.totalSupply());
        assertEq(pair.balanceOf(address(pair.vault())), pair.MINIMUM_LIQUIDITY());

        assertEq(pair.price0CumulativeLast(), (reserve1.div(reserve0)).unwrap() * 12);
        assertEq(pair.price1CumulativeLast(), (reserve0.div(reserve1)).unwrap() * 12);
    }

    function testMintInvalidReserves() public {
        uint256 amount0 = ERC20(token0).balanceOf(user1);
        uint256 amount1 = ERC20(token1).balanceOf(user1);

        vm.startPrank(user1);
        addLiquidity(amount0, amount1, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        ERC20(token0).safeTransfer(address(pair), amount0 - 10);
        ERC20(token1).safeTransfer(address(pair), amount1);
        vm.expectRevert();
        pair.mint(user2);
        vm.stopPrank();
    }

    function testMintFailInsufficientLiquidityMinted() public {
        vm.startPrank(user1);
        ERC20(token0).safeTransfer(address(pair), 100);
        ERC20(token1).safeTransfer(address(pair), 10000);
        vm.expectRevert(Pair.Pair_Insufficient_Liquidity_Minted.selector);
        pair.mint(user1);
    }

    function testMintFailOverflow() public {
        // Creating a fresh new user and pair due to the already minted tokens in the 'setUp' function
        address user4 = address(444);
        Token0 t0 = new Token0();
        Token1 t1 = new Token1();

        // MAX_WHOLE_UD60x18 is slightly less than the type(uint256).max, the minting
        // and the calculations in 'mint', '_mintFee' & '_update' can be executed
        t0.mint(user4, MAX_WHOLE_UD60x18.unwrap());
        t1.mint(user4, MAX_WHOLE_UD60x18.unwrap() + 1);

        factory.createPair(address(t0), address(t1));
        Pair _pair = Pair(factory.getPair(address(t0), address(t1)));

        vm.startPrank(user4);
        ERC20(t0).safeTransfer(address(_pair), 1);
        ERC20(t1).safeTransfer(address(_pair), MAX_WHOLE_UD60x18.unwrap() + 1);
        vm.expectRevert(Pair.Pair_Overflow.selector);
        _pair.mint(user4);
    }

    function testBurn() public {
        uint256 amount0 = ERC20(token0).balanceOf(user1);
        uint256 amount1 = ERC20(token1).balanceOf(user1);

        vm.startPrank(user1);
        addLiquidity(amount0, amount1, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        addLiquidity(amount0, amount1, user2);

        uint256 amount = pair.balanceOf(user2);

        ERC20(pair).transfer(address(pair), amount);
        vm.expectEmit();
        emit Burn(user2, amount0, amount1, user1);
        pair.burn(user1);
        vm.stopPrank();

        (UD60x18 reserve0, UD60x18 reserve1,) = pair.getReserves();

        assertEq(reserve0.unwrap(), 10 ether);
        assertEq(reserve1.unwrap(), 100_000 ether);
        assertEq(ERC20(token0).balanceOf(user1), 10 ether);
        assertEq(ERC20(token1).balanceOf(user1), 100_000 ether);
        assertEq(ERC20(token0).balanceOf(user2), 0);
        assertEq(ERC20(token1).balanceOf(user2), 0);
        assertEq(pair.totalSupply(), Math.sqrt(amount0 * amount1));
        assertEq(pair.totalSupply(), Math.sqrt(reserve0.unwrap() * reserve1.unwrap()));

        amount = pair.balanceOf(user1);

        vm.startPrank(user1);
        ERC20(pair).transfer(address(pair), amount);
        vm.expectEmit();
        emit Burn(user1, amount0 - 10, amount1 - 100_000, user1);
        pair.burn(user1);
        vm.stopPrank();

        (reserve0, reserve1,) = pair.getReserves();
        assertEq(pair.totalSupply(), Math.sqrt(reserve0.unwrap() * reserve1.unwrap()));
        assertEq(ERC20(token0).balanceOf(user1) + 10, 20 ether);
        assertEq(ERC20(token1).balanceOf(user1) + 100_000, 200_000 ether);
    }

    function testBurnFailInsufficientLiquidityBurned() public {
        uint256 amount0 = ERC20(token0).balanceOf(user1);
        uint256 amount1 = ERC20(token1).balanceOf(user1);

        vm.startPrank(user1);
        addLiquidity(amount0, amount1, user1);

        vm.expectRevert(Pair.Pair_Insufficient_Liquidity_Burned.selector);
        pair.burn(user1);
        vm.stopPrank();
    }

    function testSwapFailInvalidAmounts() public {
        uint256 amount0 = ERC20(token0).balanceOf(user1);
        uint256 amount1 = ERC20(token1).balanceOf(user1);

        vm.startPrank(user1);
        addLiquidity(amount0, amount1, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert(Pair.Pair_Invalid_Out_Amounts.selector);
        pair.swap(0, 0, user2, EMPTY_DATA);

        vm.expectRevert(Pair.Pair_Invalid_In_Amounts.selector);
        pair.swap(amount0 / 2, amount1 / 2, user2, EMPTY_DATA);
        vm.stopPrank();
    }

    function testSwapFailInsufficientLiquidity() public {
        uint256 amount0 = ERC20(token0).balanceOf(user1);
        uint256 amount1 = ERC20(token1).balanceOf(user1);

        vm.startPrank(user1);
        addLiquidity(amount0, amount1, user1);
        vm.stopPrank();

        amount0 = ERC20(token0).balanceOf(user3);
        amount1 = ERC20(token1).balanceOf(user3);

        vm.startPrank(user3);
        vm.expectRevert(Pair.Pair_Insufficient_Liquidity.selector);
        pair.swap(amount0, 0, user3, EMPTY_DATA);

        vm.expectRevert(Pair.Pair_Insufficient_Liquidity.selector);
        pair.swap(0, amount1, user3, EMPTY_DATA);

        vm.stopPrank();
    }

    function testSwapFailInvalidReceiver() public {
        uint256 amount0 = ERC20(token0).balanceOf(user1);
        uint256 amount1 = ERC20(token1).balanceOf(user1);

        vm.startPrank(user1);
        addLiquidity(amount0, amount1, user1);
        vm.stopPrank();

        amount0 = 0;
        amount1 = 20_000;

        vm.startPrank(user3);
        vm.expectRevert(Pair.Pair_Invalid_Receiver.selector);
        pair.swap(amount0, amount1, token0, EMPTY_DATA);

        vm.expectRevert(Pair.Pair_Invalid_Receiver.selector);
        pair.swap(amount0, amount1, token1, EMPTY_DATA);
        vm.stopPrank();
    }

    function testSwapFailInvalidK() public {
        uint256 amount0 = ERC20(token0).balanceOf(user1);
        uint256 amount1 = ERC20(token1).balanceOf(user1);

        vm.startPrank(user1);
        addLiquidity(amount0, amount1, user1);
        vm.stopPrank();

        // `user2` transfers 2.5 ether before calling swap
        uint256 amount0In = 5 ether / 2;
        uint256 amount0Out = 0;
        uint256 amount1Out = 20_000 ether;

        vm.startPrank(user2);
        ERC20(token0).transfer(address(pair), amount0In);
        vm.expectRevert(Pair.Pair_Invalid_K.selector);
        pair.swap(amount0Out, amount1Out, user2, EMPTY_DATA);
        vm.stopPrank();
    }

    function testSwap() public {
        uint256 amount0 = ERC20(token0).balanceOf(user1);
        uint256 amount1 = ERC20(token1).balanceOf(user1);

        vm.startPrank(user1);
        addLiquidity(amount0, amount1, user1);
        vm.stopPrank();

        //   `user2` transfers 2.5 + fee ether before calling swap
        uint256 amount0In;
        uint256 amount1In = 0;
        uint256 amount0Out = 0;
        uint256 amount1Out = 20_000 ether;

        (UD60x18 reserve0, UD60x18 reserve1,) = pair.getReserves();

        amount0In = (inputAmountPlusFee(reserve0, reserve1, ud(amount1Out))).unwrap(); // 2507522567703109328 ~ 2.5075 ether

        vm.startPrank(user2);
        ERC20(token0).transfer(address(pair), amount0In);
        vm.expectEmit();
        emit Swap(user2, amount0In, amount1In, amount0Out, amount1Out, user2);
        pair.swap(amount0Out, amount1Out, user2, EMPTY_DATA);
        vm.stopPrank();

        (reserve0, reserve1,) = pair.getReserves();

        assertEq(ERC20(token0).balanceOf(user2), amount0 - amount0In);
        assertEq(ERC20(token1).balanceOf(user2), amount1 + amount1Out);
        assertEq(ERC20(token0).balanceOf(address(pair)), reserve0.unwrap());
        assertEq(ERC20(token1).balanceOf(address(pair)), reserve1.unwrap());
        assertEq(ERC20(token0).balanceOf(user2), amount0 - amount0In);
        assertEq(ERC20(token1).balanceOf(user2), 120_000 ether);
        assertEq(reserve0.unwrap(), amount0 + amount0In);
        assertEq(reserve1.unwrap(), 80_000 ether);
    }

    function testSkim() public {
        uint256 amount0 = ERC20(token0).balanceOf(user1);
        uint256 amount1 = ERC20(token1).balanceOf(user1);

        vm.startPrank(user1);
        ERC20(token0).safeTransfer(address(pair), amount0);
        ERC20(token1).safeTransfer(address(pair), amount1);
        vm.stopPrank();

        vm.startPrank(user2);
        pair.skim(user2);
        vm.stopPrank();

        assertEq(ERC20(token0).balanceOf(address(pair)), 0);
        assertEq(ERC20(token1).balanceOf(address(pair)), 0);
        assertEq(ERC20(token0).balanceOf(user2), amount0 * 2);
        assertEq(ERC20(token1).balanceOf(user2), amount1 * 2);
    }

    function testSync() public {
        uint256 amount0 = ERC20(token0).balanceOf(user1);
        uint256 amount1 = ERC20(token1).balanceOf(user1);

        vm.startPrank(user1);
        addLiquidity(amount0 / 2, amount1, user1);

        (UD60x18 reserve0,,) = pair.getReserves();
        assertEq(reserve0.unwrap(), 5 ether);

        ERC20(token0).safeTransfer(address(pair), amount0 / 2);

        (reserve0,,) = pair.getReserves();
        assertEq(reserve0.unwrap(), 5 ether);

        pair.sync();
        (reserve0,,) = pair.getReserves();
        assertEq(reserve0.unwrap(), 10 ether);

        vm.stopPrank();
    }
}

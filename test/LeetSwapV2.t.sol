// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import "../src/LeetSwapV2Router01.sol";
import "../src/LeetSwapV2Factory.sol";
import "../src/LeetSwapV2Pair.sol";
import "../src/interfaces/IWCANTO.sol";
import "../src/interfaces/IBaseV1Factory.sol";
import "../src/interfaces/IBaseV1Router01.sol";
import "../script/DeployDEXV2.s.sol";

import {MockERC20Tax} from "./doubles/MockERC20Tax.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract TestLeetSwapV2 is Test {
    uint256 mainnetFork;

    DeployDEXV2 public deployer;
    LeetSwapV2Factory public factory;
    LeetSwapV2Router01 public router;

    IBaseV1Factory public cantoDEXFactory;
    IBaseV1Router01 public cantoDEXRouter;

    IWCANTO public weth;
    MockERC20 public token0;
    MockERC20 public token1;
    MockERC20Tax public token0Tax;
    MockERC20Tax public token1Tax;

    uint256 public taxRate;
    uint256 public taxDivisor;
    address public taxRecipient;

    function setUp() public {
        mainnetFork = vm.createSelectFork(
            "https://canto.slingshot.finance",
            2923489
        );

        deployer = new DeployDEXV2();
        (factory, router) = deployer.run();
        weth = IWCANTO(router.WETH());

        cantoDEXFactory = IBaseV1Factory(deployer.cantoDEXFactory());

        token0 = new MockERC20("Token0", "T0", 18);
        token1 = new MockERC20("Token1", "T1", 18);
        token0.mint(address(this), 10 ether);
        token1.mint(address(this), 10 ether);

        taxRate = 1000;
        taxDivisor = 1e4;
        taxRecipient = address(0xDEADBEEF);
        token0Tax = new MockERC20Tax(
            "Token0Tax",
            "T0T",
            18,
            taxRate,
            taxDivisor,
            taxRecipient
        );
        token1Tax = new MockERC20Tax(
            "Token1Tax",
            "T1T",
            18,
            taxRate,
            taxDivisor,
            taxRecipient
        );
        token0Tax.mint(address(this), 10 ether);
        token1Tax.mint(address(this), 10 ether);

        token0Tax.setPair(
            address(router.pairFor(address(token0Tax), address(weth))),
            true
        );
        token0Tax.setPair(
            address(router.pairFor(address(token0Tax), address(token1Tax))),
            true
        );
        token0Tax.setPair(
            address(router.pairFor(address(token0Tax), address(token0))),
            true
        );
        token0Tax.setPair(
            address(router.pairFor(address(token0Tax), address(token1))),
            true
        );

        token1Tax.setPair(
            address(router.pairFor(address(token1Tax), address(weth))),
            true
        );
        token1Tax.setPair(
            address(router.pairFor(address(token1Tax), address(token0Tax))),
            true
        );
        token1Tax.setPair(
            address(router.pairFor(address(token1Tax), address(token0))),
            true
        );
        token1Tax.setPair(
            address(router.pairFor(address(token1Tax), address(token1))),
            true
        );

        vm.label(address(deployer), "deployer");
        vm.label(address(factory), "factory");
        vm.label(address(router), "router");
        vm.label(address(weth), "wcanto");
        vm.label(address(token0), "token0");
        vm.label(address(token1), "token1");
        vm.label(address(token0Tax), "token0Tax");
        vm.label(address(token1Tax), "token1Tax");
        vm.label(address(cantoDEXFactory), "cantoDEXFactory");

        vm.deal(address(this), 100 ether);
        weth.deposit{value: 10 ether}();
    }

    function testAddLiquidityPairFor() public {
        token0.approve(address(router), 1 ether);
        token1.approve(address(router), 1 ether);

        (address _token0, address _token1) = router.sortTokens(
            address(token0),
            address(token1)
        );
        address pair = router.pairFor(_token0, _token1);

        (, , uint256 liquidity) = router.addLiquidity(
            address(token0),
            address(token1),
            1 ether,
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        assertEq(liquidity, 1 ether - LeetSwapV2Pair(pair).MINIMUM_LIQUIDITY());
        assertEq(factory.getPair(address(token0), address(token1)), pair);
    }

    function testAddLiquidityNoPair() public {
        token0.approve(address(router), 1 ether);
        token1.approve(address(router), 1 ether);

        (address _token0, address _token1) = router.sortTokens(
            address(token0),
            address(token1)
        );

        address pair = router.pairFor(_token0, _token1);

        (uint256 amount0, uint256 amount1, uint256 liquidity) = router
            .addLiquidity(
                address(token0),
                address(token1),
                1 ether,
                1 ether,
                1 ether,
                1 ether,
                address(this),
                block.timestamp + 1
            );

        assertEq(amount0, 1 ether);
        assertEq(amount1, 1 ether);
        assertEq(liquidity, 1 ether - LeetSwapV2Pair(pair).MINIMUM_LIQUIDITY());

        assertEq(
            factory.getPair(address(token0), address(token1), false),
            pair
        );
        assertEq(LeetSwapV2Pair(pair).token0(), address(token0));
        assertEq(LeetSwapV2Pair(pair).token1(), address(token1));

        (uint256 reserve0, uint256 reserve1, ) = LeetSwapV2Pair(pair)
            .getReserves();
        assertEq(reserve0, 1 ether);
        assertEq(reserve1, 1 ether);
        assertEq(token0.balanceOf(address(pair)), 1 ether);
        assertEq(token1.balanceOf(address(pair)), 1 ether);
        assertEq(token0.balanceOf(address(this)), 9 ether);
        assertEq(token1.balanceOf(address(this)), 9 ether);
    }

    function testAddLiquidityInsufficientAmountB() public {
        token0.approve(address(router), 4 ether);
        token1.approve(address(router), 8 ether);

        router.addLiquidity(
            address(token0),
            address(token1),
            4 ether,
            8 ether,
            4 ether,
            8 ether,
            address(this),
            block.timestamp + 1
        );

        token0.approve(address(router), 1 ether);
        token1.approve(address(router), 2 ether);

        //vm.expectRevert(bytes('LeetSwapV2Router: INSUFFICIENT_A_AMOUNT'));
        vm.expectRevert();
        router.addLiquidity(
            address(token0),
            address(token1),
            1 ether,
            2 ether,
            1 ether,
            2.3 ether,
            address(this),
            block.timestamp + 1
        );
    }

    function testAddLiquidityAmountBDesiredHigh() public {
        token0.approve(address(router), 4 ether);
        token1.approve(address(router), 8 ether);

        router.addLiquidity(
            address(token0),
            address(token1),
            4 ether,
            8 ether,
            4 ether,
            8 ether,
            address(this),
            block.timestamp + 1
        );

        token0.approve(address(router), 1 ether);
        token1.approve(address(router), 2 ether);

        (uint256 amount0, uint256 amount1, ) = router.addLiquidity(
            address(token0),
            address(token1),
            1 ether,
            2.3 ether,
            1 ether,
            2 ether,
            address(this),
            block.timestamp + 1
        );

        assertEq(amount0, 1 ether);
        assertEq(amount1, 2 ether);
    }

    function testAddLiquidityAmountBDesiredLow() public {
        token0.approve(address(router), 4 ether);
        token1.approve(address(router), 8 ether);

        router.addLiquidity(
            address(token0),
            address(token1),
            4 ether,
            8 ether,
            4 ether,
            8 ether,
            address(this),
            block.timestamp + 1
        );

        token0.approve(address(router), 1 ether);
        token1.approve(address(router), 2 ether);

        vm.expectRevert();
        (uint256 amount0, uint256 amount1, ) = router.addLiquidity(
            address(token0),
            address(token1),
            1 ether,
            1.5 ether,
            0.75 ether,
            2 ether,
            address(this),
            block.timestamp + 1
        );

        assertEq(amount0, 0);
        assertEq(amount1, 0);
    }

    function testAddLiquidityInsufficientAmountA() public {
        token0.approve(address(router), 4 ether);
        token1.approve(address(router), 8 ether);

        router.addLiquidity(
            address(token0),
            address(token1),
            4 ether,
            8 ether,
            4 ether,
            8 ether,
            address(this),
            block.timestamp + 1
        );

        token0.approve(address(router), 1 ether);
        token1.approve(address(router), 2 ether);

        vm.expectRevert();
        //vm.expectRevert(bytes('LeetSwapV2Router: INSUFFICIENT_A_AMOUNT'));
        router.addLiquidity(
            address(token0),
            address(token1),
            1 ether,
            1.5 ether,
            1 ether,
            2 ether,
            address(this),
            block.timestamp + 1
        );
    }

    function testAddLiquidityExpired() public {
        token0.approve(address(router), 1 ether);
        token1.approve(address(router), 1 ether);

        vm.warp(2);
        vm.expectRevert(LeetSwapV2Router01.DeadlineExpired.selector);
        router.addLiquidity(
            address(token0),
            address(token1),
            1 ether,
            1 ether,
            1 ether,
            1 ether,
            address(this),
            1
        );
    }

    function testRemoveLiquidity() public {
        token0.approve(address(router), 1 ether);
        token1.approve(address(router), 1 ether);

        (uint256 amount0, uint256 amount1, uint256 liquidity) = router
            .addLiquidity(
                address(token0),
                address(token1),
                1 ether,
                1 ether,
                1 ether,
                1 ether,
                address(this),
                block.timestamp + 1
            );

        address pair = factory.getPair(address(token0), address(token1), false);
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        uint256 pairMinimumLiquidity = LeetSwapV2Pair(pair).MINIMUM_LIQUIDITY();
        router.removeLiquidity(
            address(token0),
            address(token1),
            liquidity,
            amount0 - pairMinimumLiquidity,
            amount1 - pairMinimumLiquidity,
            address(this),
            block.timestamp + 1
        );

        assertEq(
            token0.balanceOf(address(this)),
            10 ether - pairMinimumLiquidity
        );
        assertEq(
            token1.balanceOf(address(this)),
            10 ether - pairMinimumLiquidity
        );
    }

    function testRemoveLiquidityInsufficientAmountA() public {
        token0.approve(address(router), 1 ether);
        token1.approve(address(router), 1 ether);

        (uint256 amount0, uint256 amount1, uint256 liquidity) = router
            .addLiquidity(
                address(token0),
                address(token1),
                1 ether,
                1 ether,
                1 ether,
                1 ether,
                address(this),
                block.timestamp + 1
            );

        address pair = factory.getPair(address(token0), address(token1), false);
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        uint256 pairMinimumLiquidity = LeetSwapV2Pair(pair).MINIMUM_LIQUIDITY();
        vm.expectRevert(LeetSwapV2Router01.InsufficientAAmount.selector);
        router.removeLiquidity(
            address(token0),
            address(token1),
            liquidity,
            amount0 - pairMinimumLiquidity + 1,
            amount1 - pairMinimumLiquidity,
            address(this),
            block.timestamp + 1
        );
    }

    function testRemoveLiquidityInsufficientAmountB() public {
        token0.approve(address(router), 1 ether);
        token1.approve(address(router), 1 ether);

        (uint256 amount0, uint256 amount1, uint256 liquidity) = router
            .addLiquidity(
                address(token0),
                address(token1),
                1 ether,
                1 ether,
                1 ether,
                1 ether,
                address(this),
                block.timestamp + 1
            );

        address pair = factory.getPair(address(token0), address(token1), false);
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        uint256 pairMinimumLiquidity = LeetSwapV2Pair(pair).MINIMUM_LIQUIDITY();
        vm.expectRevert(LeetSwapV2Router01.InsufficientBAmount.selector);
        router.removeLiquidity(
            address(token0),
            address(token1),
            liquidity,
            amount0 - pairMinimumLiquidity,
            amount1 - pairMinimumLiquidity + 1,
            address(this),
            block.timestamp + 1
        );
    }

    function testRemoveLiquidityExpired() public {
        token0.approve(address(router), 1 ether);
        token1.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidity(
            address(token0),
            address(token1),
            1 ether,
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(address(token0), address(token1), false);
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        vm.warp(2);
        vm.expectRevert(LeetSwapV2Router01.DeadlineExpired.selector);
        router.removeLiquidity(
            address(token0),
            address(token1),
            liquidity,
            0,
            0,
            address(this),
            1
        );
    }

    function testAddLiquidityTaxToken() public {
        token0Tax.approve(address(router), 1 ether);
        token1.approve(address(router), 1 ether);

        (address _token0Tax, address _token1) = router.sortTokens(
            address(token0Tax),
            address(token1)
        );

        address pair = router.pairFor(_token0Tax, _token1);

        (uint256 amount0, uint256 amount1, uint256 liquidity) = router
            .addLiquidity(
                address(token0Tax),
                address(token1),
                1 ether,
                1 ether,
                1 ether,
                1 ether,
                address(this),
                block.timestamp + 1
            );
        uint256 taxAmount = (1 ether * taxRate) / taxDivisor;

        assertEq(amount0, 1 ether); // don't subtract tax cuz it gets calculated before subtracting the fee
        assertEq(amount1, 1 ether);
        assertTrue(
            liquidity < 1 ether - LeetSwapV2Pair(pair).MINIMUM_LIQUIDITY()
        );

        assertEq(
            factory.getPair(address(token0Tax), address(token1), false),
            pair
        );
        assertEq(LeetSwapV2Pair(pair).token0(), address(token0Tax));
        assertEq(LeetSwapV2Pair(pair).token1(), address(token1));

        (uint256 reserve0, uint256 reserve1, ) = LeetSwapV2Pair(pair)
            .getReserves();
        assertEq(token0Tax.balanceOf(taxRecipient), taxAmount);
        assertEq(reserve0, 1 ether - taxAmount);
        assertEq(reserve1, 1 ether);
        assertEq(token0Tax.balanceOf(address(pair)), 1 ether - taxAmount);
        assertEq(token1.balanceOf(address(pair)), 1 ether);
        assertEq(token0Tax.balanceOf(address(this)), 9 ether);
        assertEq(token1.balanceOf(address(this)), 9 ether);
    }

    function testRemoveLiquidityTaxToken() public {
        token0Tax.approve(address(router), 1 ether);
        token1.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidity(
            address(token0Tax),
            address(token1),
            1 ether,
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(
            address(token0Tax),
            address(token1),
            false
        );
        uint256 reserve0 = token0Tax.balanceOf(pair);
        uint256 reserve1 = token1.balanceOf(pair);

        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        uint256 pairMinimumLiquidity = LeetSwapV2Pair(pair).MINIMUM_LIQUIDITY();
        uint256 taxAmount = ((reserve0 - pairMinimumLiquidity) * taxRate) /
            taxDivisor;
        router.removeLiquidity(
            address(token0Tax),
            address(token1),
            liquidity,
            reserve0 - pairMinimumLiquidity,
            reserve1 - pairMinimumLiquidity - taxAmount,
            address(this),
            block.timestamp + 1
        );
    }

    function testAddLiquidityETHTaxToken() public {
        token0Tax.approve(address(router), 1 ether);

        address pair = router.pairFor(address(token0Tax), address(weth));

        (uint256 amount0, uint256 amount1, ) = router.addLiquidityETH{
            value: 1 ether
        }(
            address(token0Tax),
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        assertEq(amount0, 1 ether); // don't subtract tax cuz it gets calculated before subtracting the fee
        assertEq(amount1, 1 ether);

        assertEq(
            factory.getPair(address(token0Tax), address(weth), false),
            pair
        );
        assertEq(LeetSwapV2Pair(pair).token0(), address(token0Tax));
        assertEq(LeetSwapV2Pair(pair).token1(), address(weth));
    }

    function testSwapExactTokensForTokens() public {
        token0.approve(address(router), 1 ether);
        token1.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidity(
            address(token0),
            address(token1),
            1 ether,
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(address(token0), address(token1), false);
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        token0.approve(address(router), 1 ether);

        uint256 initialBalanceToken0 = token0.balanceOf(address(this));
        uint256 initialBalanceToken1 = token1.balanceOf(address(this));
        uint256 amountOut = router.getAmountsOut(1 ether, path)[1];
        router.swapExactTokensForTokens(
            1 ether,
            amountOut,
            path,
            address(this),
            block.timestamp + 1
        );

        assertEq(
            token0.balanceOf(address(this)),
            initialBalanceToken0 - 1 ether
        );
        assertEq(
            token1.balanceOf(address(this)),
            initialBalanceToken1 + amountOut
        );
    }

    function testSwapExactTokensForTokensInsufficientAmountOut() public {
        token0.approve(address(router), 1 ether);
        token1.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidity(
            address(token0),
            address(token1),
            1 ether,
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(address(token0), address(token1), false);
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        token0.approve(address(router), 1 ether);

        uint256 initialBalanceToken0 = token0.balanceOf(address(this));
        uint256 initialBalanceToken1 = token1.balanceOf(address(this));
        uint256 amountOut = router.getAmountsOut(1 ether, path)[1];
        vm.expectRevert(LeetSwapV2Router01.InsufficientOutputAmount.selector);
        router.swapExactTokensForTokens(
            1 ether,
            amountOut + 1,
            path,
            address(this),
            block.timestamp + 1
        );

        assertEq(token0.balanceOf(address(this)), initialBalanceToken0);
        assertEq(token1.balanceOf(address(this)), initialBalanceToken1);
    }

    function testSwapExactTokensForTokensDeadlineExpired() public {
        token0.approve(address(router), 1 ether);
        token1.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidity(
            address(token0),
            address(token1),
            1 ether,
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(address(token0), address(token1), false);
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        token0.approve(address(router), 1 ether);

        uint256 initialBalanceToken0 = token0.balanceOf(address(this));
        uint256 initialBalanceToken1 = token1.balanceOf(address(this));
        uint256 amountOut = router.getAmountsOut(1 ether, path)[1];
        vm.warp(2);
        vm.expectRevert(LeetSwapV2Router01.DeadlineExpired.selector);
        router.swapExactTokensForTokens(
            1 ether,
            amountOut,
            path,
            address(this),
            1
        );

        assertEq(token0.balanceOf(address(this)), initialBalanceToken0);
        assertEq(token1.balanceOf(address(this)), initialBalanceToken1);
    }

    function testSwapExactETHForTokens() public {
        token0.approve(address(router), 1 ether);
        token1.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidityETH{value: 1 ether}(
            address(token0),
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(address(token0), address(weth), false);
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token0);

        uint256 initialBalanceToken0 = token0.balanceOf(address(this));
        uint256 initialBalanceToken1 = token1.balanceOf(address(this));
        uint256 amountOut = router.getAmountsOut(1 ether, path)[1];
        router.swapExactETHForTokens{value: 1 ether}(
            amountOut,
            path,
            address(this),
            block.timestamp + 1
        );

        assertEq(
            token0.balanceOf(address(this)),
            initialBalanceToken0 + amountOut
        );
        assertEq(token1.balanceOf(address(this)), initialBalanceToken1);
    }

    function testSwapExactETHForTokensInsufficientAmountOut() public {
        token0.approve(address(router), 1 ether);
        token1.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidityETH{value: 1 ether}(
            address(token0),
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(address(token0), address(weth), false);
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token0);

        uint256 initialBalanceToken0 = token0.balanceOf(address(this));
        uint256 initialBalanceToken1 = token1.balanceOf(address(this));
        uint256 amountOut = router.getAmountsOut(1 ether, path)[1];
        vm.expectRevert(LeetSwapV2Router01.InsufficientOutputAmount.selector);
        router.swapExactETHForTokens{value: 1 ether}(
            amountOut + 1,
            path,
            address(this),
            block.timestamp + 1
        );

        assertEq(token0.balanceOf(address(this)), initialBalanceToken0);
        assertEq(token1.balanceOf(address(this)), initialBalanceToken1);
    }

    function testSwapExactETHForTokensDeadlineExpired() public {
        token0.approve(address(router), 1 ether);
        token1.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidityETH{value: 1 ether}(
            address(token0),
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(address(token0), address(weth), false);
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token0);

        uint256 initialBalanceToken0 = token0.balanceOf(address(this));
        uint256 initialBalanceToken1 = token1.balanceOf(address(this));
        uint256 amountOut = router.getAmountsOut(1 ether, path)[1];
        vm.warp(2);
        vm.expectRevert(LeetSwapV2Router01.DeadlineExpired.selector);
        router.swapExactETHForTokens{value: 1 ether}(
            amountOut,
            path,
            address(this),
            1
        );

        assertEq(token0.balanceOf(address(this)), initialBalanceToken0);
        assertEq(token1.balanceOf(address(this)), initialBalanceToken1);
    }

    function testSwapExactTokensForETH() public {
        token0.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidityETH{value: 1 ether}(
            address(token0),
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(address(token0), address(weth), false);
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(weth);

        uint256 initialBalanceToken0 = token0.balanceOf(address(this));
        uint256 initialBalanceETH = address(this).balance;
        uint256 amountOut = router.getAmountsOut(1 ether, path)[1];
        token0.approve(address(router), 1 ether);
        router.swapExactTokensForETH(
            1 ether,
            amountOut,
            path,
            address(this),
            block.timestamp + 1
        );

        assertEq(
            token0.balanceOf(address(this)),
            initialBalanceToken0 - 1 ether
        );
        assertEq(address(this).balance, initialBalanceETH + amountOut);
    }

    function testSwapExactTokensForETHInsufficientAmountOut() public {
        token0.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidityETH{value: 1 ether}(
            address(token0),
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(address(token0), address(weth), false);
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(weth);

        uint256 initialBalanceToken0 = token0.balanceOf(address(this));
        uint256 initialBalanceETH = address(this).balance;
        uint256 amountOut = router.getAmountsOut(1 ether, path)[1];
        token0.approve(address(router), 1 ether);
        vm.expectRevert(LeetSwapV2Router01.InsufficientOutputAmount.selector);
        router.swapExactTokensForETH(
            1 ether,
            amountOut + 1,
            path,
            address(this),
            block.timestamp + 1
        );

        assertEq(token0.balanceOf(address(this)), initialBalanceToken0);
        assertEq(address(this).balance, initialBalanceETH);
    }

    function testSwapExactTokensForETHDeadlineExpired() public {
        token0.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidityETH{value: 1 ether}(
            address(token0),
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(address(token0), address(weth), false);
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(weth);

        uint256 initialBalanceToken0 = token0.balanceOf(address(this));
        uint256 initialBalanceETH = address(this).balance;
        uint256 amountOut = router.getAmountsOut(1 ether, path)[1];
        token0.approve(address(router), 1 ether);
        vm.warp(2);
        vm.expectRevert(LeetSwapV2Router01.DeadlineExpired.selector);
        router.swapExactTokensForETH(
            1 ether,
            amountOut,
            path,
            address(this),
            1
        );

        assertEq(token0.balanceOf(address(this)), initialBalanceToken0);
        assertEq(address(this).balance, initialBalanceETH);
    }

    function testSwapExactETHForTokensSupportingFeeOnTransferTokens() public {
        token0Tax.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidityETH{value: 1 ether}(
            address(token0Tax),
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(
            address(token0Tax),
            address(weth),
            false
        );
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token0Tax);

        uint256 initialBalanceToken0 = token0Tax.balanceOf(address(this));
        uint256 initialBalanceETH = address(this).balance;
        uint256 amountIn = 1 ether;
        uint256 amountInAfterTax = (amountIn * taxRate) / taxDivisor;
        uint256 amountOutAfterTax = router.getAmountOut(
            amountInAfterTax,
            path[0],
            path[1]
        );
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: 1 ether
        }(amountOutAfterTax, path, address(this), block.timestamp + 1);

        assertTrue(
            token0Tax.balanceOf(address(this)) >=
                initialBalanceToken0 + amountOutAfterTax
        );
        assertEq(address(this).balance, initialBalanceETH - 1 ether);
    }

    function testSwapExactETHForTokensSupportingFeeOnTransferTokensInsufficientAmountOut()
        public
    {
        token0Tax.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidityETH{value: 1 ether}(
            address(token0Tax),
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(
            address(token0Tax),
            address(weth),
            false
        );
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token0Tax);

        uint256 initialBalanceToken0 = token0Tax.balanceOf(address(this));
        uint256 initialBalanceETH = address(this).balance;
        uint256 amountIn = 1 ether;
        uint256 amountOut = router.getAmountOut(amountIn, path[0], path[1]);
        vm.expectRevert(LeetSwapV2Router01.InsufficientOutputAmount.selector);
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: 1 ether
        }(amountOut, path, address(this), block.timestamp + 1);

        assertEq(token0Tax.balanceOf(address(this)), initialBalanceToken0);
        assertEq(address(this).balance, initialBalanceETH);
    }

    function testSwapExactETHForTokensSupportingFeeOnTransferTokensDeadlineExpired()
        public
    {
        token0Tax.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidityETH{value: 1 ether}(
            address(token0Tax),
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(
            address(token0Tax),
            address(weth),
            false
        );
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token0Tax);

        uint256 initialBalanceToken0 = token0Tax.balanceOf(address(this));
        uint256 initialBalanceETH = address(this).balance;
        uint256 amountIn = 1 ether;
        uint256 amountOut = router.getAmountOut(amountIn, path[0], path[1]);
        vm.warp(2);
        vm.expectRevert(LeetSwapV2Router01.DeadlineExpired.selector);
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: 1 ether
        }(amountOut, path, address(this), 1);

        assertEq(token0Tax.balanceOf(address(this)), initialBalanceToken0);
        assertEq(address(this).balance, initialBalanceETH);
    }

    function testSwapExactTokensForTokensSupportingFeeOnTransferTokens()
        public
    {
        token0Tax.approve(address(router), 1 ether);
        token1.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidity(
            address(token0Tax),
            address(token1),
            1 ether,
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(
            address(token0Tax),
            address(token1),
            false
        );
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(token0Tax);
        path[1] = address(token1);

        uint256 initialBalanceToken0 = token0Tax.balanceOf(address(this));
        uint256 initialBalanceToken1 = token1.balanceOf(address(this));
        uint256 amountIn = 1 ether;
        uint256 amountInAfterTax = (amountIn * taxRate) / taxDivisor;
        uint256 amountOutAfterTax = router.getAmountsOut(
            amountInAfterTax,
            path
        )[1];
        token0Tax.approve(address(router), 1 ether);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOutAfterTax,
            path,
            address(this),
            block.timestamp + 1
        );

        assertTrue(
            token1.balanceOf(address(this)) >=
                initialBalanceToken1 + amountOutAfterTax
        );
        assertTrue(
            token0Tax.balanceOf(address(this)) <=
                initialBalanceToken0 - amountInAfterTax
        );
    }

    function testSwapExactTokensForTokensSupportingFeeOnTransferTokensInsufficientAmountOut()
        public
    {
        token0Tax.approve(address(router), 1 ether);
        token1.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidity(
            address(token0Tax),
            address(token1),
            1 ether,
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(
            address(token0Tax),
            address(token1),
            false
        );
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(token0Tax);
        path[1] = address(token1);

        uint256 initialBalanceToken0 = token0Tax.balanceOf(address(this));
        uint256 initialBalanceToken1 = token1.balanceOf(address(this));
        uint256 amountIn = 1 ether;
        uint256 amountOut = router.getAmountsOut(amountIn, path)[1];
        token0Tax.approve(address(router), 1 ether);
        vm.expectRevert(LeetSwapV2Router01.InsufficientOutputAmount.selector);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOut,
            path,
            address(this),
            block.timestamp + 1
        );

        assertEq(token0Tax.balanceOf(address(this)), initialBalanceToken0);
        assertEq(token1.balanceOf(address(this)), initialBalanceToken1);
    }

    function testSwapExactTokensForTokensSupportingFeeOnTransferTokensDeadlineExpired()
        public
    {
        token0Tax.approve(address(router), 1 ether);
        token1.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidity(
            address(token0Tax),
            address(token1),
            1 ether,
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(
            address(token0Tax),
            address(token1),
            false
        );
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(token0Tax);
        path[1] = address(token1);

        uint256 initialBalanceToken0 = token0Tax.balanceOf(address(this));
        uint256 initialBalanceToken1 = token1.balanceOf(address(this));
        uint256 amountIn = 1 ether;
        uint256 amountOut = router.getAmountsOut(amountIn, path)[1];
        token0Tax.approve(address(router), 1 ether);
        vm.warp(2);
        vm.expectRevert(LeetSwapV2Router01.DeadlineExpired.selector);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOut,
            path,
            address(this),
            1
        );

        assertEq(token0Tax.balanceOf(address(this)), initialBalanceToken0);
        assertEq(token1.balanceOf(address(this)), initialBalanceToken1);
    }

    function testSwapExactTokensForETHSupportingFeeOnTransferTokens() public {
        token0Tax.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidityETH{value: 1 ether}(
            address(token0Tax),
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(
            address(token0Tax),
            address(weth),
            false
        );
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(token0Tax);
        path[1] = address(weth);

        uint256 initialBalanceToken0 = token0Tax.balanceOf(address(this));
        uint256 initialBalanceETH = address(this).balance;
        uint256 amountIn = 1 ether;
        uint256 amountInAfterTax = (amountIn * taxRate) / taxDivisor;
        uint256 amountOutAfterTax = router.getAmountsOut(
            amountInAfterTax,
            path
        )[1];
        token0Tax.approve(address(router), 1 ether);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn,
            amountOutAfterTax,
            path,
            address(this),
            block.timestamp + 1
        );

        assertTrue(
            address(this).balance >= initialBalanceETH + amountOutAfterTax
        );
        assertTrue(
            token0Tax.balanceOf(address(this)) <=
                initialBalanceToken0 - amountInAfterTax
        );
    }

    function testSwapExactTokensForETHSupportingFeeOnTransferTokensInsufficientAmountOut()
        public
    {
        token0Tax.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidityETH{value: 1 ether}(
            address(token0Tax),
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(
            address(token0Tax),
            address(weth),
            false
        );
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(token0Tax);
        path[1] = address(weth);

        uint256 initialBalanceToken0 = token0Tax.balanceOf(address(this));
        uint256 initialBalanceETH = address(this).balance;
        uint256 amountIn = 1 ether;
        uint256 amountOut = router.getAmountsOut(amountIn, path)[1];
        token0Tax.approve(address(router), 1 ether);
        vm.expectRevert(LeetSwapV2Router01.InsufficientOutputAmount.selector);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn,
            amountOut,
            path,
            address(this),
            block.timestamp + 1
        );

        assertEq(token0Tax.balanceOf(address(this)), initialBalanceToken0);
        assertEq(address(this).balance, initialBalanceETH);
    }

    function testSwapExactTokensForETHSupportingFeeOnTransferTokensDeadlineExpired()
        public
    {
        token0Tax.approve(address(router), 1 ether);

        (, , uint256 liquidity) = router.addLiquidityETH{value: 1 ether}(
            address(token0Tax),
            1 ether,
            1 ether,
            1 ether,
            address(this),
            block.timestamp + 1
        );

        address pair = factory.getPair(
            address(token0Tax),
            address(weth),
            false
        );
        assertEq(IERC20(pair).balanceOf(address(this)), liquidity);
        LeetSwapV2Pair(pair).approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(token0Tax);
        path[1] = address(weth);

        uint256 initialBalanceToken0 = token0Tax.balanceOf(address(this));
        uint256 initialBalanceETH = address(this).balance;
        uint256 amountIn = 1 ether;
        uint256 amountOut = router.getAmountsOut(amountIn, path)[1];
        token0Tax.approve(address(router), 1 ether);
        vm.warp(2);
        vm.expectRevert(LeetSwapV2Router01.DeadlineExpired.selector);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn,
            amountOut,
            path,
            address(this),
            1
        );

        assertEq(token0Tax.balanceOf(address(this)), initialBalanceToken0);
        assertEq(address(this).balance, initialBalanceETH);
    }

    receive() external payable {}
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import {DeployLeetToken, LeetToken} from "../script/DeployLeetToken.s.sol";

import "../script/DeployDEXV2.s.sol";

contract TestLeetToken is Test {
    uint256 mainnetFork;

    DeployLeetToken public leetDeployer;
    LeetToken public leet;

    DeployDEXV2 public dexDeployer;
    LeetSwapV2Factory public factory;
    LeetSwapV2Router01 public router;

    IBaseV1Factory public cantoDEXFactory;

    IWCANTO public weth;
    IERC20 public note;

    address noteAccountant = 0x4F6DCfa2F69AF7350AAc48D3a3d5B8D03b5378AA;

    function setUp() public {
        mainnetFork = vm.createSelectFork(
            "https://canto.slingshot.finance",
            3149555
        );

        dexDeployer = new DeployDEXV2();
        (factory, router) = dexDeployer.run();
        weth = IWCANTO(router.WETH());
        note = IERC20(0x4e71A2E537B7f9D9413D3991D37958c0b5e1e503);

        cantoDEXFactory = IBaseV1Factory(dexDeployer.cantoDEXFactory());

        leetDeployer = new DeployLeetToken();
        leet = leetDeployer.run(address(router));

        vm.label(address(leetDeployer), "leet deployer");
        vm.label(address(factory), "factory");
        vm.label(address(router), "router");
        vm.label(address(leet), "leet");
        vm.label(address(weth), "wcanto");
        vm.label(address(note), "note");
        vm.label(address(cantoDEXFactory), "cantoDEXFactory");
        vm.label(noteAccountant, "note accountant");

        vm.deal(address(this), 100 ether);
        weth.deposit{value: 10 ether}();

        assertEq(leet.balanceOf(leet.owner()), 1337000 * 1e18);
    }

    function testAddLiquidityWithCanto() public {
        address liquidityManager = leet.owner();

        vm.startPrank(liquidityManager);

        leet.approve(address(router), 800e3 ether);
        router.addLiquidityETH{value: 10 ether}(
            address(leet),
            800e3 ether,
            0,
            0,
            liquidityManager,
            block.timestamp
        );

        vm.stopPrank();

        address pair = factory.getPair(address(leet), address(weth));
        assertEq(leet.balanceOf(pair), 800e3 ether);
        assertEq(IERC20(address(weth)).balanceOf(address(pair)), 10 ether);
    }

    function testAddLiquidityWithNote() public {
        address liquidityManager = leet.owner();

        vm.prank(noteAccountant);
        note.transfer(liquidityManager, 10 ether);

        vm.startPrank(liquidityManager);

        leet.approve(address(router), 800e3 ether);
        note.approve(address(router), 10 ether);
        router.addLiquidity(
            address(leet),
            address(note),
            800e3 ether,
            10 ether,
            0,
            0,
            liquidityManager,
            block.timestamp
        );

        vm.stopPrank();

        address pair = factory.getPair(address(leet), address(note));
        assertEq(leet.balanceOf(pair), 800e3 ether);
        assertEq(note.balanceOf(pair), 10 ether);
    }

    function testBuyTax() public {
        vm.prank(leet.owner());
        leet.enableTrading();
        vm.warp(block.timestamp + leet.sniperSellFeeDecayPeriod());

        testAddLiquidityWithCanto();
        vm.deal(address(this), 1 ether);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(leet);

        uint256 amountOut = router.getAmountOut(1 ether, path[0], path[1]);
        uint256 tax = (amountOut * leet.totalBuyFee()) / leet.FEE_DENOMINATOR();
        uint256 amountOutAfterTax = amountOut - tax;

        router.swapExactETHForTokens{value: 1 ether}(
            0,
            path,
            address(this),
            block.timestamp
        );

        assertEq(leet.balanceOf(address(this)), amountOutAfterTax);
    }

    function testSniperBuyTax() public {
        vm.prank(leet.owner());
        leet.enableTrading();
        vm.warp(leet.tradingEnabledTimestamp() + 1);

        testAddLiquidityWithCanto();
        vm.deal(address(this), 1 ether);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(leet);

        uint256 amountOut = router.getAmountOut(1 ether, path[0], path[1]);
        uint256 buyTax = (amountOut * leet.totalBuyFee()) /
            leet.FEE_DENOMINATOR();
        uint256 sniperBuyTax = (amountOut * leet.sniperBuyFee()) /
            leet.FEE_DENOMINATOR();
        uint256 amountOutAfterTax = amountOut - buyTax - sniperBuyTax;

        router.swapExactETHForTokens{value: 1 ether}(
            0,
            path,
            address(this),
            block.timestamp
        );

        assertEq(leet.balanceOf(address(this)), amountOutAfterTax);
    }

    function testSniperBuyTaxWithNote() public {
        vm.prank(leet.owner());
        leet.enableTrading();
        vm.warp(leet.tradingEnabledTimestamp() + 1);

        testAddLiquidityWithNote();

        vm.prank(noteAccountant);
        note.transfer(address(this), 1 ether);
        vm.deal(address(this), 1 ether);

        address[] memory path = new address[](2);
        path[0] = address(note);
        path[1] = address(leet);

        uint256 amountOut = router.getAmountOut(1 ether, path[0], path[1]);
        uint256 buyTax = (amountOut * leet.totalBuyFee()) /
            leet.FEE_DENOMINATOR();
        uint256 sniperBuyTax = (amountOut * leet.sniperBuyFee()) /
            leet.FEE_DENOMINATOR();
        uint256 amountOutAfterTax = amountOut - buyTax - sniperBuyTax;

        note.approve(address(router), UINT256_MAX);
        router.swapExactTokensForTokens(
            1 ether,
            0,
            path,
            address(this),
            block.timestamp
        );

        assertEq(leet.balanceOf(address(this)), amountOutAfterTax);
    }

    function testSellTax() public {
        vm.prank(leet.owner());
        leet.enableTrading();
        vm.warp(block.timestamp + leet.sniperSellFeeDecayPeriod());

        testAddLiquidityWithCanto();
        vm.deal(address(this), 0 ether);

        vm.prank(leet.owner());
        leet.transfer(address(this), 1 ether);
        leet.approve(address(router), UINT256_MAX);

        address[] memory path = new address[](2);
        path[0] = address(leet);
        path[1] = address(weth);

        uint256 amountInAfterTax = 1 ether -
            (1 ether * leet.totalSellFee()) /
            leet.FEE_DENOMINATOR();
        uint256 amountOut = router.getAmountOut(
            amountInAfterTax,
            path[0],
            path[1]
        );

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            1 ether,
            0,
            path,
            address(this),
            block.timestamp
        );

        assertEq(address(this).balance, amountOut);
    }

    function testSniperSellTax() public {
        vm.prank(leet.owner());
        leet.enableTrading();
        vm.warp(leet.tradingEnabledTimestamp() + 1);

        testAddLiquidityWithCanto();
        vm.deal(address(this), 0 ether);

        vm.prank(leet.owner());
        leet.transfer(address(this), 1 ether);
        leet.approve(address(router), UINT256_MAX);

        address[] memory path = new address[](2);
        path[0] = address(leet);
        path[1] = address(weth);

        uint256 amountInAfterTax = 1 ether -
            (1 ether * leet.totalSellFee()) /
            leet.FEE_DENOMINATOR() -
            (1 ether * leet.sniperSellFee()) /
            leet.FEE_DENOMINATOR();
        uint256 amountOut = router.getAmountOut(
            amountInAfterTax,
            path[0],
            path[1]
        );

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            1 ether,
            0,
            path,
            address(this),
            block.timestamp
        );

        assertEq(address(this).balance, amountOut);
    }

    function testSniperBuyFeeGetter() public {
        vm.prank(leet.owner());
        leet.enableTrading();
        vm.warp(leet.tradingEnabledTimestamp());

        uint256 sniperBuyBaseFee = 2000;
        uint256 decayPeriod = 15 minutes;
        uint256 decayStart = block.timestamp;

        assertEq(leet.sniperBuyFee(), sniperBuyBaseFee);

        vm.warp(decayStart + 11 minutes + 15 seconds);
        assertEq(leet.sniperBuyFee(), 500);

        vm.warp(decayStart + decayPeriod / 2);
        assertEq(leet.sniperBuyFee(), sniperBuyBaseFee / 2);

        vm.warp(decayStart + decayPeriod);
        assertEq(leet.sniperBuyFee(), 0);

        vm.warp(decayStart + decayPeriod * 2);
        assertEq(leet.sniperBuyFee(), 0);
    }

    function testSniperSellFeeGetter() public {
        vm.prank(leet.owner());
        leet.enableTrading();
        vm.warp(leet.tradingEnabledTimestamp());

        uint256 sniperSellBaseFee = 2000;
        uint256 decayPeriod = 24 hours;
        uint256 decayStart = block.timestamp;

        assertEq(leet.sniperSellFee(), sniperSellBaseFee);

        vm.warp(decayStart + 16 hours);
        assertEq(leet.sniperSellFee(), 667);

        vm.warp(decayStart + decayPeriod / 2);
        assertEq(leet.sniperSellFee(), sniperSellBaseFee / 2);

        vm.warp(decayStart + decayPeriod);
        assertEq(leet.sniperSellFee(), 0);

        vm.warp(decayStart + decayPeriod * 2);
        assertEq(leet.sniperSellFee(), 0);
    }

    function testPairAutoDetection() public {
        address pair = factory.getPair(address(leet), address(weth));
        vm.prank(leet.owner());
        leet.removeLeetPair(pair);

        testBuyTax();
    }

    function testSwappingFeesOnTransfer() public {
        testSniperBuyTaxWithNote();
        vm.warp(block.timestamp + leet.sniperSellFeeDecayPeriod());

        uint256 taxTokens = leet.balanceOf(address(leet));
        uint256 maxSwapFeesAmount = leet.maxSwapFeesAmount();
        uint256 amountToSwap = taxTokens > maxSwapFeesAmount
            ? maxSwapFeesAmount
            : taxTokens;
        uint256 amountOut = router.getAmountOut(
            amountToSwap,
            address(leet),
            address(note)
        );

        leet.transfer(address(42), 1);
        assertTrue(note.balanceOf(leet.treasuryFeeRecipient()) > 0);
        assertEq(note.balanceOf(leet.treasuryFeeRecipient()), amountOut);
    }

    function testSwappingFeesOnSells() public {
        testSniperBuyTaxWithNote();
        vm.warp(block.timestamp + leet.sniperSellFeeDecayPeriod());

        uint256 taxTokens = leet.balanceOf(address(leet));
        uint256 maxSwapFeesAmount = leet.maxSwapFeesAmount();
        uint256 amountToSwap = taxTokens > maxSwapFeesAmount
            ? maxSwapFeesAmount
            : taxTokens;
        uint256 amountOut = router.getAmountOut(
            amountToSwap,
            address(leet),
            address(note)
        );

        uint256 swapAmount = leet.balanceOf(address(this));
        address[] memory path = new address[](2);
        path[0] = address(leet);
        path[1] = address(note);

        leet.approve(address(router), swapAmount);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            swapAmount,
            0,
            path,
            address(this),
            block.timestamp
        );

        assertTrue(note.balanceOf(leet.treasuryFeeRecipient()) > 0);
        assertEq(note.balanceOf(leet.treasuryFeeRecipient()), amountOut);
    }

    function testMaxSwapFeesAmount() public {
        vm.prank(leet.owner());
        leet.enableTrading();

        testAddLiquidityWithNote();

        vm.prank(leet.owner());
        leet.transfer(address(leet), 1e3 ether);

        uint256 taxTokens = leet.balanceOf(address(leet));
        uint256 maxSwapFeesAmount = leet.maxSwapFeesAmount();
        uint256 amountToSwap = taxTokens > maxSwapFeesAmount
            ? maxSwapFeesAmount
            : taxTokens;
        uint256 amountOut = router.getAmountOut(
            amountToSwap,
            address(leet),
            address(note)
        );

        leet.transfer(address(42), 0);
        assertTrue(note.balanceOf(leet.treasuryFeeRecipient()) > 0);
        assertEq(note.balanceOf(leet.treasuryFeeRecipient()), amountOut);
    }

    function testSetTradingEnabledTimestamp() public {
        testAddLiquidityWithNote();

        uint256 tradingEnabledTimestamp = block.timestamp + 1 days;
        vm.prank(leet.owner());
        leet.setTradingEnabledTimestamp(tradingEnabledTimestamp);

        address[] memory path = new address[](2);
        path[0] = address(note);
        path[1] = address(leet);

        uint256 amountIn = 1 ether;
        vm.prank(noteAccountant);
        note.transfer(address(this), amountIn);
        note.approve(address(router), amountIn);

        vm.expectRevert(LeetToken.TradingNotEnabled.selector);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );

        vm.prank(leet.owner());
        leet.enableTrading();

        vm.expectRevert(LeetToken.TradingNotEnabled.selector);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );

        vm.warp(tradingEnabledTimestamp);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );

        assertEq(leet.sniperBuyFee(), leet.sniperBuyBaseFee());
        assertEq(leet.sniperSellFee(), leet.sniperSellBaseFee());
    }

    receive() external payable {}
}

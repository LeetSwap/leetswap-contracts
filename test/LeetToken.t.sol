// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import "./doubles/StubFeeDiscountOracle.sol";

import {DeployLeetToken, LeetToken, LeetChefV1, LeetBar} from "../script/DeployLeetToken.s.sol";
import "@leetswap/tokens/interfaces/IFeeDiscountOracle.sol";
import "../script/DeployDEXV2.s.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {WETH} from "solmate/tokens/WETH.sol";

contract TestLeetToken is Test {
    uint256 mainnetFork;

    DeployLeetToken public leetDeployer;
    LeetToken public leet;

    DeployDEXV2 public dexDeployer;
    LeetSwapV2Factory public factory;
    LeetSwapV2Router01 public router;

    IWCANTO public weth;
    MockERC20 public pairToken;

    function setUp() public {
        // mainnetFork = vm.createSelectFork(
        //     "https://canto.slingshot.finance",
        //     3149555
        // );

        dexDeployer = new DeployDEXV2();
        weth = IWCANTO(address(new WETH()));
        (factory, router) = dexDeployer.deploy(address(weth));
        // weth = IWCANTO(router.WETH());
        // pairToken = IERC20(0x4e71A2E537B7f9D9413D3991D37958c0b5e1e503);

        pairToken = new MockERC20("PairToken", "PT", 18);

        leetDeployer = new DeployLeetToken();
        leet = leetDeployer.run(address(router), address(pairToken));

        vm.label(address(leetDeployer), "leet deployer");
        vm.label(address(factory), "factory");
        vm.label(address(router), "router");
        vm.label(address(leet), "leet");
        vm.label(address(weth), "wcanto");
        vm.label(address(pairToken), "pair token");

        vm.prank(factory.owner());
        factory.setProtocolFeesShare(0);

        vm.startPrank(router.owner());
        router.setDeadlineEnabled(true);
        router.setLiquidityManageableEnabled(true);
        router.setLiquidityManageableWhitelistEnabled(false);
        vm.stopPrank();

        vm.startPrank(leet.owner());
        leet.setPairAutoDetectionEnabled(true);
        leet.setMaxWalletEnabled(false);
        vm.stopPrank();

        vm.deal(address(this), 100 ether);
        weth.deposit{value: 10 ether}();

        assertEq(leet.balanceOf(leet.owner()), 1337000 * 1e18);
    }

    function addLiquidityWithCanto(uint256 tokenAmount, uint256 cantoAmount)
        public
    {
        address liquidityManager = leet.owner();

        vm.startPrank(liquidityManager);

        leet.approve(address(router), tokenAmount);
        router.addLiquidityETH{value: cantoAmount}(
            address(leet),
            tokenAmount,
            0,
            0,
            liquidityManager,
            block.timestamp
        );

        vm.stopPrank();
    }

    function addLiquidityWithPairToken(
        uint256 tokenAmount,
        uint256 pairTokenAmount
    ) public {
        address liquidityManager = leet.owner();

        pairToken.mint(liquidityManager, pairTokenAmount);

        vm.startPrank(liquidityManager);

        leet.approve(address(router), tokenAmount);
        pairToken.approve(address(router), pairTokenAmount);
        router.addLiquidity(
            address(leet),
            address(pairToken),
            tokenAmount,
            pairTokenAmount,
            0,
            0,
            liquidityManager,
            block.timestamp
        );

        vm.stopPrank();
    }

    function testAddLiquidityWithCanto() public {
        addLiquidityWithCanto(800e3 ether, 10 ether);

        address pair = factory.getPair(address(leet), address(weth));
        assertEq(leet.balanceOf(pair), 800e3 ether);
        assertEq(IERC20(address(weth)).balanceOf(address(pair)), 10 ether);
    }

    function testAddLiquidityWithPairToken() public {
        addLiquidityWithPairToken(800e3 ether, 10 ether);

        address pair = factory.getPair(address(leet), address(pairToken));
        assertEq(leet.balanceOf(pair), 800e3 ether);
        assertEq(pairToken.balanceOf(pair), 10 ether);
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

    function testIndirectSwapTaxEnabled() public {
        vm.startPrank(leet.owner());
        leet.enableTrading();
        leet.setIndirectSwapFeeEnabled(true);
        vm.stopPrank();
        vm.warp(block.timestamp + leet.sniperSellFeeDecayPeriod());

        addLiquidityWithCanto(400e3 ether, 5 ether);
        addLiquidityWithPairToken(400e3 ether, 5 ether);
        vm.deal(address(this), 1 ether);

        address[] memory path = new address[](3);
        path[0] = address(weth);
        path[1] = address(leet);
        path[2] = address(pairToken);

        uint256 leetAmountOut = router.getAmountOut(1 ether, path[0], path[1]);
        uint256 tax = (leetAmountOut * leet.totalSellFee()) /
            leet.FEE_DENOMINATOR();
        uint256 leetAmountOutAfterTax = leetAmountOut - tax;
        uint256 pairTokenAmountOut = router.getAmountOut(
            leetAmountOutAfterTax,
            path[1],
            path[2]
        );

        assertEq(pairToken.balanceOf(address(this)), 0);
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: 1 ether
        }(0, path, address(this), block.timestamp);

        assertEq(pairToken.balanceOf(address(this)), pairTokenAmountOut);
    }

    function testIndirectSwapTaxDisabled() public {
        vm.prank(leet.owner());
        leet.enableTrading();
        vm.warp(block.timestamp + leet.sniperSellFeeDecayPeriod());

        addLiquidityWithCanto(400e3 ether, 5 ether);
        addLiquidityWithPairToken(400e3 ether, 5 ether);
        vm.deal(address(this), 1 ether);

        address[] memory path = new address[](3);
        path[0] = address(weth);
        path[1] = address(leet);
        path[2] = address(pairToken);

        uint256 pairTokenAmountOut = router.getAmountsOut(1 ether, path)[2];
        assertEq(pairToken.balanceOf(address(this)), 0);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: 1 ether
        }(0, path, address(this), block.timestamp);

        assertEq(pairToken.balanceOf(address(this)), pairTokenAmountOut);
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

    function testSniperBuyTaxWithPairToken() public {
        vm.prank(leet.owner());
        leet.enableTrading();
        vm.warp(leet.tradingEnabledTimestamp() + 1);

        testAddLiquidityWithPairToken();

        pairToken.mint(address(this), 1 ether);
        vm.deal(address(this), 1 ether);

        address[] memory path = new address[](2);
        path[0] = address(pairToken);
        path[1] = address(leet);

        uint256 amountOut = router.getAmountOut(1 ether, path[0], path[1]);
        uint256 buyTax = (amountOut * leet.totalBuyFee()) /
            leet.FEE_DENOMINATOR();
        uint256 sniperBuyTax = (amountOut * leet.sniperBuyFee()) /
            leet.FEE_DENOMINATOR();
        uint256 amountOutAfterTax = amountOut - buyTax - sniperBuyTax;

        pairToken.approve(address(router), UINT256_MAX);
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

    function testBuyFeeDiscount() public {
        uint256 taxDiscount = 0.5 ether;
        IFeeDiscountOracle oracle = new StubFeeDiscountOracle(taxDiscount);

        vm.startPrank(leet.owner());
        leet.setFeeDiscountOracle(oracle);
        leet.enableTrading();
        vm.stopPrank();
        vm.warp(block.timestamp + leet.sniperSellFeeDecayPeriod());

        testAddLiquidityWithCanto();
        vm.deal(address(this), 1 ether);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(leet);

        uint256 amountOut = router.getAmountOut(1 ether, path[0], path[1]);
        uint256 tax = (amountOut * leet.totalBuyFee()) /
            leet.FEE_DENOMINATOR() -
            taxDiscount;
        uint256 amountOutAfterTax = amountOut - tax;

        router.swapExactETHForTokens{value: 1 ether}(
            0,
            path,
            address(this),
            block.timestamp
        );

        assertEq(leet.balanceOf(address(this)), amountOutAfterTax);
    }

    function testSellFeeDiscount() public {
        uint256 taxDiscount = 0.5 ether;
        IFeeDiscountOracle oracle = new StubFeeDiscountOracle(taxDiscount);

        vm.startPrank(leet.owner());
        leet.setFeeDiscountOracle(oracle);
        leet.enableTrading();
        vm.stopPrank();
        vm.warp(block.timestamp + leet.sniperSellFeeDecayPeriod());

        testAddLiquidityWithCanto();
        vm.deal(address(this), 0 ether);

        uint256 sellAmount = 50e3 ether;
        vm.prank(leet.owner());
        leet.transfer(address(this), sellAmount);

        address[] memory path = new address[](2);
        path[0] = address(leet);
        path[1] = address(weth);

        uint256 amountInAfterTax = sellAmount -
            (sellAmount * leet.totalSellFee()) /
            leet.FEE_DENOMINATOR() +
            taxDiscount;
        uint256 amountOut = router.getAmountOut(
            amountInAfterTax,
            path[0],
            path[1]
        );

        assertEq(address(this).balance, 0);
        leet.approve(address(router), UINT256_MAX);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            sellAmount,
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
        vm.startPrank(leet.owner());
        leet.removeLeetPair(pair);
        leet.setPairAutoDetectionEnabled(true);
        vm.stopPrank();

        testBuyTax();
    }

    function testSwappingFeesOnTransfer() public {
        testSniperBuyTaxWithPairToken();
        vm.warp(block.timestamp + leet.sniperSellFeeDecayPeriod());

        uint256 taxTokens = leet.balanceOf(address(leet));
        uint256 maxSwapFeesAmount = leet.maxSwapFeesAmount();
        uint256 amountToSwap = taxTokens > maxSwapFeesAmount
            ? maxSwapFeesAmount
            : taxTokens;
        uint256 amountOut = router.getAmountOut(
            amountToSwap,
            address(leet),
            address(pairToken)
        );

        vm.prank(address(1337));
        leet.transfer(address(42), 0);
        assertTrue(pairToken.balanceOf(leet.treasuryFeeRecipient()) > 0);
        assertEq(pairToken.balanceOf(leet.treasuryFeeRecipient()), amountOut);
    }

    function testSwappingFeesOnSells() public {
        testSniperBuyTaxWithPairToken();
        vm.warp(block.timestamp + leet.sniperSellFeeDecayPeriod());

        uint256 taxTokens = leet.balanceOf(address(leet));
        uint256 maxSwapFeesAmount = leet.maxSwapFeesAmount();
        uint256 amountToSwap = taxTokens > maxSwapFeesAmount
            ? maxSwapFeesAmount
            : taxTokens;
        uint256 amountOut = router.getAmountOut(
            amountToSwap,
            address(leet),
            address(pairToken)
        );

        uint256 swapAmount = leet.balanceOf(address(this));
        address[] memory path = new address[](2);
        path[0] = address(leet);
        path[1] = address(pairToken);

        leet.approve(address(router), swapAmount);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            swapAmount,
            0,
            path,
            address(this),
            block.timestamp
        );

        assertTrue(pairToken.balanceOf(leet.treasuryFeeRecipient()) > 0);
        assertEq(pairToken.balanceOf(leet.treasuryFeeRecipient()), amountOut);
    }

    function testMaxSwapFeesAmount() public {
        vm.prank(leet.owner());
        leet.enableTrading();

        testAddLiquidityWithPairToken();

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
            address(pairToken)
        );

        vm.prank(address(1337));
        leet.transfer(address(42), 0);
        assertTrue(pairToken.balanceOf(leet.treasuryFeeRecipient()) > 0);
        assertEq(pairToken.balanceOf(leet.treasuryFeeRecipient()), amountOut);
    }

    function testSetTradingEnabledTimestamp() public {
        testAddLiquidityWithPairToken();

        uint256 tradingEnabledTimestamp = block.timestamp + 1 days;
        vm.prank(leet.owner());
        leet.setTradingEnabledTimestamp(tradingEnabledTimestamp);

        address[] memory path = new address[](2);
        path[0] = address(pairToken);
        path[1] = address(leet);

        uint256 amountIn = 1 ether;
        pairToken.mint(address(this), amountIn);
        pairToken.approve(address(router), amountIn);

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

    function testAddLiquidityWithPairTokenNotOwner() public {
        testSniperBuyTaxWithPairToken();
        // vm.deal(address(this), 1 ether);

        pairToken.mint(address(this), 1 ether);

        leet.approve(address(router), type(uint256).max);
        pairToken.approve(address(router), type(uint256).max);
        router.addLiquidity(
            address(leet),
            address(pairToken),
            leet.balanceOf(address(this)),
            1 ether,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    function testDeployAndLaunch() public {
        uint256 pairTokenLiquidityAmount = 5000 ether;
        pairToken.mint(address(this), pairTokenLiquidityAmount);

        pairToken.mint(leet.owner(), pairTokenLiquidityAmount);
        vm.stopPrank();

        (LeetToken _leet, LeetChefV1 _chef, LeetBar _bar) = leetDeployer
            .deployAndLaunch(
                router,
                IERC20Metadata(address(pairToken)),
                pairTokenLiquidityAmount,
                block.timestamp + 1
            );
        leet = _leet;

        address pair = factory.getPair(address(leet), address(pairToken));
        assertEq(pairToken.balanceOf(pair), pairTokenLiquidityAmount);
        assertEq(leet.balanceOf(address(_bar)), 1337 ether);
        assertEq(
            IERC20(pair).balanceOf(address(_chef)),
            IERC20(pair).totalSupply() - 1e3
        );

        vm.warp(leet.tradingEnabledTimestamp() + 1);

        pairToken.mint(address(this), 1 ether);
        vm.deal(address(this), 1 ether);

        address[] memory path = new address[](2);
        path[0] = address(pairToken);
        path[1] = address(leet);

        uint256 amountOut = router.getAmountOut(1 ether, path[0], path[1]);
        uint256 buyTax = (amountOut * leet.totalBuyFee()) /
            leet.FEE_DENOMINATOR();
        uint256 sniperBuyTax = (amountOut * leet.sniperBuyFee()) /
            leet.FEE_DENOMINATOR();
        uint256 amountOutAfterTax = amountOut - buyTax - sniperBuyTax;

        pairToken.approve(address(router), UINT256_MAX);
        router.swapExactTokensForTokens(
            1 ether,
            0,
            path,
            address(this),
            block.timestamp
        );

        assertEq(leet.balanceOf(address(this)), amountOutAfterTax);

        pairToken.mint(address(this), 1 ether);

        leet.approve(address(router), type(uint256).max);
        pairToken.approve(address(router), type(uint256).max);
        router.addLiquidity(
            address(leet),
            address(pairToken),
            leet.balanceOf(address(this)),
            1 ether,
            0,
            0,
            address(this),
            block.timestamp + 60
        );
    }

    receive() external payable {}
}

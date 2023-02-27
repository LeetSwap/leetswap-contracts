// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import "@leetswap/dex/v2/LeetSwapV2Router01.sol";
import "@leetswap/dex/v2/LeetSwapV2Factory.sol";
import "@leetswap/dex/v2/LeetSwapV2Pair.sol";
import "../script/DeployLeetToken.s.sol";

contract TestLeetToken is Test {
    uint256 mainnetFork;

    DeployLeetToken public deployer;
    LeetToken public leet;

    LeetSwapV2Factory public factory =
        LeetSwapV2Factory(0x432Aad747c5f126a313d918E15d8133fca571Df1);
    LeetSwapV2Router01 public router =
        LeetSwapV2Router01(payable(0x90DEc5d26CE471418265a314063955392E66765D));
    IBaseV1Factory public cantoDEXFactory =
        IBaseV1Factory(0xE387067f12561e579C5f7d4294f51867E0c1cFba);

    IWCANTO public weth;
    IERC20 public note = IERC20(0x4e71A2E537B7f9D9413D3991D37958c0b5e1e503);

    uint256 public taxRate;
    uint256 public taxDivisor;
    address public taxRecipient;

    function setUp() public {
        mainnetFork = vm.createSelectFork(
            "https://canto.slingshot.finance",
            3093626
        );

        deployer = new DeployLeetToken();
        leet = deployer.run(address(router));
        weth = router.wcanto();

        vm.label(address(deployer), "deployer");
        vm.label(address(factory), "factory");
        vm.label(address(router), "router");
        vm.label(address(leet), "leet");
        vm.label(address(weth), "wcanto");
        vm.label(address(note), "note");
        vm.label(address(cantoDEXFactory), "cantoDEXFactory");

        vm.deal(address(this), 100 ether);
        weth.deposit{value: 10 ether}();

        vm.prank(leet.owner());
        leet.enableTrading();

        assertEq(leet.balanceOf(leet.owner()), 1337000 * 1e18);
    }

    function testAddLiquidityWithCanto() public {
        vm.startPrank(leet.owner());

        leet.approve(address(router), 10 ether);
        router.addLiquidityETH{value: 10 ether}(
            address(leet),
            10 ether,
            0,
            0,
            address(deployer),
            block.timestamp
        );

        vm.stopPrank();

        address pair = factory.getPair(address(leet), address(weth));
        assertEq(leet.balanceOf(pair), 10 ether);
        assertEq(IERC20(address(weth)).balanceOf(address(pair)), 10 ether);
    }

    function testBuyTax() public {
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

    function testPairAutoDetection() public {
        address pair = factory.getPair(address(leet), address(weth));
        vm.prank(leet.owner());
        leet.removeLeetPair(pair);

        testBuyTax();
    }

    receive() external payable {}
}

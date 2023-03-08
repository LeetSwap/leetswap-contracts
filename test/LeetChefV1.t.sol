// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import "../script/DeployLeetChefV1.s.sol";

import {DeployLeetToken, LeetToken} from "../script/DeployLeetToken.s.sol";
import "../script/DeployDEXV2.s.sol";

contract TestLeetChefV1 is Test {
    uint256 mainnetFork;

    DeployLeetChefV1 chefDeployer;
    LeetChefV1 chef;

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

        chefDeployer = new DeployLeetChefV1();
        chef = chefDeployer.run(leet);

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

        vm.startPrank(leet.owner());
        leet.transfer(address(chef), 337000 * 1e18);
        leet.enableTrading();
        vm.stopPrank();

        assertEq(leet.balanceOf(leet.owner()), 1000000 * 1e18);
        assertEq(leet.balanceOf(address(chef)), 337000 * 1e18);

        vm.warp(block.timestamp + leet.sniperSellFeeDecayPeriod());
    }

    function addLiquidityWithCanto(uint256 leetAmount)
        public
        returns (uint256 liquidity)
    {
        address liquidityManager = leet.owner();

        vm.startPrank(liquidityManager);

        leet.approve(address(router), leetAmount);
        (, , liquidity) = router.addLiquidityETH{value: 10 ether}(
            address(leet),
            leetAmount,
            0,
            0,
            liquidityManager,
            block.timestamp
        );

        vm.stopPrank();
    }

    function addLiquidityWithNote(uint256 leetAmount)
        public
        returns (uint256 liquidity)
    {
        address liquidityManager = leet.owner();

        vm.prank(noteAccountant);
        note.transfer(liquidityManager, 10 ether);

        vm.startPrank(liquidityManager);

        leet.approve(address(router), leetAmount);
        note.approve(address(router), 10 ether);
        (, , liquidity) = router.addLiquidity(
            address(leet),
            address(note),
            leetAmount,
            10 ether,
            0,
            0,
            liquidityManager,
            block.timestamp
        );

        vm.stopPrank();
    }

    function buyLeetWithCanto(uint256 cantoAmount) public {
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(leet);

        uint256 amountOut = router.getAmountOut(cantoAmount, path[0], path[1]);
        uint256 tax = (amountOut * leet.totalBuyFee()) / leet.FEE_DENOMINATOR();
        uint256 amountOutAfterTax = amountOut - tax;

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: cantoAmount
        }(amountOutAfterTax, path, address(this), block.timestamp);
    }

    function buyLeetWithNote(uint256 noteAmount) public {
        address[] memory path = new address[](2);
        path[0] = address(note);
        path[1] = address(leet);

        uint256 amountOut = router.getAmountOut(noteAmount, path[0], path[1]);
        uint256 tax = (amountOut * leet.totalBuyFee()) / leet.FEE_DENOMINATOR();
        uint256 amountOutAfterTax = amountOut - tax;

        note.approve(address(router), noteAmount);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            noteAmount,
            amountOutAfterTax,
            path,
            address(this),
            block.timestamp
        );
    }

    function testClaimPendingLeet() public {
        uint256 liquidity = addLiquidityWithCanto(800e3);
        IERC20 lpToken = IERC20(router.pairFor(address(leet), address(weth)));
        uint256 emissionsPerSecond = 0.01 ether;
        uint256 allocPoints = 1;

        vm.startPrank(chef.owner());
        chef.add(allocPoints, lpToken, IRewarder(address(0)));
        chef.setPrimaryTokenPerSecond(emissionsPerSecond, true);
        vm.stopPrank();

        vm.prank(leet.owner());
        lpToken.transfer(address(this), liquidity);

        lpToken.approve(address(chef), liquidity);
        chef.deposit(0, liquidity, address(this));
        assertEq(lpToken.balanceOf(address(chef)), liquidity);

        uint256 elapsed = 666 seconds;
        uint256 pendingReward = emissionsPerSecond * elapsed;
        vm.warp(block.timestamp + elapsed);
        assertApproxEqAbs(
            chef.pendingPrimaryToken(0, address(this)),
            pendingReward,
            9
        );

        chef.harvest(0, address(this));
        assertApproxEqAbs(leet.balanceOf(address(this)), pendingReward, 9);

        vm.warp(block.timestamp + elapsed);
        assertApproxEqAbs(
            chef.pendingPrimaryToken(0, address(this)),
            pendingReward,
            9
        );

        chef.withdrawAndHarvest(0, liquidity, address(this));
        assertApproxEqAbs(leet.balanceOf(address(this)), pendingReward * 2, 9);
    }

    function testClaimPendingLeetWithNote() public {
        uint256 liquidity = addLiquidityWithNote(800e3);
        IERC20 lpToken = IERC20(router.pairFor(address(leet), address(note)));
        uint256 emissionsPerSecond = 0.01 ether;
        uint256 allocPoints = 1;

        vm.startPrank(chef.owner());
        chef.add(allocPoints, lpToken, IRewarder(address(0)));
        chef.setPrimaryTokenPerSecond(emissionsPerSecond, true);
        vm.stopPrank();

        vm.prank(leet.owner());
        lpToken.transfer(address(this), liquidity);

        lpToken.approve(address(chef), liquidity);
        chef.deposit(0, liquidity, address(this));
        assertEq(lpToken.balanceOf(address(chef)), liquidity);

        uint256 elapsed = 666 seconds;
        uint256 pendingReward = emissionsPerSecond * elapsed; // gotta subtract some wei to account for loss of precision
        vm.warp(block.timestamp + elapsed);
        assertApproxEqAbs(
            chef.pendingPrimaryToken(0, address(this)),
            pendingReward,
            9
        );

        chef.harvest(0, address(this));
        assertApproxEqAbs(leet.balanceOf(address(this)), pendingReward, 9);

        vm.warp(block.timestamp + elapsed);
        assertApproxEqAbs(
            chef.pendingPrimaryToken(0, address(this)),
            pendingReward,
            9
        );

        chef.withdrawAndHarvest(0, liquidity, address(this));
        assertApproxEqAbs(leet.balanceOf(address(this)), pendingReward * 2, 9);
    }

    function testClaimPendingLeetWithCantoAndNote() public {
        uint256 liquidityCanto = addLiquidityWithCanto(400e3);
        uint256 liquidityNote = addLiquidityWithNote(400e3);
        IERC20 lpTokenCanto = IERC20(
            router.pairFor(address(leet), address(weth))
        );
        IERC20 lpTokenNote = IERC20(
            router.pairFor(address(leet), address(note))
        );
        uint256 emissionsPerSecond = 0.01 ether;
        uint256 allocPointsCantoPool = 4;
        uint256 allocPointsNotePool = 6;
        uint256 totalAllocPoints = allocPointsCantoPool + allocPointsNotePool;

        vm.startPrank(chef.owner());
        chef.add(allocPointsCantoPool, lpTokenCanto, IRewarder(address(0)));
        chef.add(allocPointsNotePool, lpTokenNote, IRewarder(address(0)));
        chef.setPrimaryTokenPerSecond(emissionsPerSecond, true);
        vm.stopPrank();

        vm.startPrank(leet.owner());
        lpTokenCanto.transfer(address(this), liquidityCanto);
        lpTokenNote.transfer(address(this), liquidityNote);
        vm.stopPrank();

        lpTokenCanto.approve(address(chef), liquidityCanto);
        lpTokenNote.approve(address(chef), liquidityNote);
        chef.deposit(0, liquidityCanto, address(this));
        chef.deposit(1, liquidityNote, address(this));
        assertEq(lpTokenCanto.balanceOf(address(chef)), liquidityCanto);
        assertEq(lpTokenNote.balanceOf(address(chef)), liquidityNote);

        uint256 elapsed = 666 seconds;
        uint256 pendingRewardCantoPool = (emissionsPerSecond *
            elapsed *
            allocPointsCantoPool) / totalAllocPoints;
        uint256 pendingRewardNotePool = (emissionsPerSecond *
            elapsed *
            allocPointsNotePool) / totalAllocPoints;
        uint256 totalPendingReward = emissionsPerSecond * elapsed;
        vm.warp(block.timestamp + elapsed);
        assertApproxEqAbs(
            chef.pendingPrimaryToken(0, address(this)),
            pendingRewardCantoPool,
            9
        );
        assertApproxEqAbs(
            chef.pendingPrimaryToken(1, address(this)),
            pendingRewardNotePool,
            9
        );

        chef.harvest(0, address(this));
        chef.harvest(1, address(this));
        assertApproxEqAbs(leet.balanceOf(address(this)), totalPendingReward, 9);

        vm.warp(block.timestamp + elapsed);
        assertApproxEqAbs(
            chef.pendingPrimaryToken(0, address(this)),
            pendingRewardCantoPool,
            9
        );
        assertApproxEqAbs(
            chef.pendingPrimaryToken(1, address(this)),
            pendingRewardNotePool,
            9
        );

        chef.withdrawAndHarvest(0, liquidityCanto, address(this));
        chef.withdrawAndHarvest(1, liquidityNote, address(this));
        assertApproxEqAbs(
            leet.balanceOf(address(this)),
            totalPendingReward * 2,
            9
        );
    }

    function testClaimFees() public {
        uint256 liquidity = addLiquidityWithNote(800e3);
        IERC20 lpToken = IERC20(router.pairFor(address(leet), address(note)));
        uint256 emissionsPerSecond = 0.01 ether;
        uint256 allocPoints = 1;

        vm.startPrank(chef.owner());
        chef.add(allocPoints, lpToken, IRewarder(address(0)));
        chef.setPrimaryTokenPerSecond(emissionsPerSecond, true);
        vm.stopPrank();

        vm.prank(leet.owner());
        lpToken.transfer(address(this), liquidity);

        lpToken.approve(address(chef), liquidity);
        chef.deposit(0, liquidity, address(this));
        assertEq(lpToken.balanceOf(address(chef)), liquidity);

        uint256 buyAmount = 1 ether;
        uint256 tradingFees = factory.tradingFees(
            address(lpToken),
            address(this)
        );
        uint256 noteFeesAccrued = (buyAmount * tradingFees * liquidity) /
            1e4 /
            lpToken.totalSupply();
        assertEq(tradingFees, 30);

        vm.prank(noteAccountant);
        note.transfer(address(this), buyAmount);
        buyLeetWithNote(buyAmount);

        vm.prank(chef.owner());
        chef.claimLPFees(0);
        assertEq(note.balanceOf(chef.owner()), noteFeesAccrued);
    }

    function testClaimFeesWithExistingBalance() public {
        uint256 liquidity = addLiquidityWithNote(800e3);
        IERC20 lpToken = IERC20(router.pairFor(address(leet), address(note)));
        uint256 emissionsPerSecond = 0.01 ether;
        uint256 allocPoints = 1;

        vm.startPrank(chef.owner());
        chef.add(allocPoints, lpToken, IRewarder(address(0)));
        chef.setPrimaryTokenPerSecond(emissionsPerSecond, true);
        vm.stopPrank();

        vm.prank(leet.owner());
        lpToken.transfer(address(this), liquidity);

        lpToken.approve(address(chef), liquidity);
        chef.deposit(0, liquidity, address(this));
        assertEq(lpToken.balanceOf(address(chef)), liquidity);

        uint256 buyAmount = 1 ether;
        uint256 existingChefBalance = 0.5 ether;
        uint256 tradingFees = factory.tradingFees(
            address(lpToken),
            address(this)
        );
        uint256 noteFeesAccrued = (buyAmount * tradingFees * liquidity) /
            1e4 /
            lpToken.totalSupply();
        assertEq(tradingFees, 30);

        vm.prank(noteAccountant);
        note.transfer(address(this), buyAmount + existingChefBalance);
        note.transfer(address(chef), existingChefBalance);
        buyLeetWithNote(buyAmount);

        vm.prank(chef.owner());
        chef.claimLPFees(0);
        assertEq(note.balanceOf(chef.owner()), noteFeesAccrued);
        assertEq(note.balanceOf(address(chef)), existingChefBalance);
    }

    receive() external payable {}
}

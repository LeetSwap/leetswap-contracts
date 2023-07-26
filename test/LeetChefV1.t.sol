// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import "../script/DeployLeetChefV1.s.sol";
import "../script/DeployRewarders.s.sol";

import {DeployLeetToken, LeetToken} from "../script/DeployLeetToken.s.sol";
import "../script/DeployDEXV2.s.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {WETH} from "solmate/tokens/WETH.sol";

contract TestLeetChefV1 is Test {
    uint256 mainnetFork;

    DeployLeetChefV1 chefDeployer;
    LeetChefV1 chef;

    DeployLeetToken public leetDeployer;
    LeetToken public leet;

    DeployDEXV2 public dexDeployer;
    LeetSwapV2Factory public factory;
    LeetSwapV2Router01 public router;

    IWCANTO public weth;
    MockERC20 public pairToken;

    function setUp() public {
        vm.warp(42); // so we can go back in time 'till before deployment

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

        chefDeployer = new DeployLeetChefV1();
        chef = chefDeployer.run(leet);

        vm.label(address(leetDeployer), "leet deployer");
        vm.label(address(factory), "factory");
        vm.label(address(router), "router");
        vm.label(address(leet), "leet");
        vm.label(address(weth), "wcanto");
        vm.label(address(pairToken), "pairToken");

        vm.prank(factory.owner());
        factory.setProtocolFeesShare(0);

        vm.prank(router.owner());
        router.setDeadlineEnabled(true);

        vm.deal(address(this), 100 ether);
        weth.deposit{value: 10 ether}();

        vm.startPrank(leet.owner());
        leet.setPairAutoDetectionEnabled(true);
        leet.setMaxWalletEnabled(false);
        leet.transfer(address(chef), 337000 * 1e18);
        leet.enableTrading();
        vm.stopPrank();

        assertEq(leet.balanceOf(leet.owner()), 1000000 * 1e18);
        assertEq(leet.balanceOf(address(chef)), 337000 * 1e18);

        vm.warp(block.timestamp + leet.sniperSellFeeDecayPeriod());
    }

    function addLiquidityWithCanto(
        uint256 leetAmount
    ) public returns (uint256 liquidity) {
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

    function addLiquidityWithPairToken(
        uint256 leetAmount
    ) public returns (uint256 liquidity) {
        address liquidityManager = leet.owner();

        pairToken.mint(liquidityManager, 10 ether);

        vm.startPrank(liquidityManager);

        leet.approve(address(router), leetAmount);
        pairToken.approve(address(router), 10 ether);
        (, , liquidity) = router.addLiquidity(
            address(leet),
            address(pairToken),
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

    function buyLeetWithPairToken(uint256 pairTokenAmount) public {
        address[] memory path = new address[](2);
        path[0] = address(pairToken);
        path[1] = address(leet);

        uint256 amountOut = router.getAmountOut(
            pairTokenAmount,
            path[0],
            path[1]
        );
        uint256 tax = (amountOut * leet.totalBuyFee()) / leet.FEE_DENOMINATOR();
        uint256 amountOutAfterTax = amountOut - tax;

        pairToken.approve(address(router), pairTokenAmount);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            pairTokenAmount,
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

    function testClaimPendingLeetWithPairToken() public {
        uint256 liquidity = addLiquidityWithPairToken(800e3);
        IERC20 lpToken = IERC20(
            router.pairFor(address(leet), address(pairToken))
        );
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

    function testClaimPendingLeetWithCantoAndPairToken() public {
        uint256 liquidityCanto = addLiquidityWithCanto(400e3);
        uint256 liquidityPairToken = addLiquidityWithPairToken(400e3);
        IERC20 lpTokenCanto = IERC20(
            router.pairFor(address(leet), address(weth))
        );
        IERC20 lpTokenPairToken = IERC20(
            router.pairFor(address(leet), address(pairToken))
        );
        uint256 emissionsPerSecond = 0.01 ether;
        uint256 allocPointsCantoPool = 4;
        uint256 allocPointsPairTokenPool = 6;
        uint256 totalAllocPoints = allocPointsCantoPool +
            allocPointsPairTokenPool;

        vm.startPrank(chef.owner());
        chef.add(allocPointsCantoPool, lpTokenCanto, IRewarder(address(0)));
        chef.add(
            allocPointsPairTokenPool,
            lpTokenPairToken,
            IRewarder(address(0))
        );
        chef.setPrimaryTokenPerSecond(emissionsPerSecond, true);
        vm.stopPrank();

        vm.startPrank(leet.owner());
        lpTokenCanto.transfer(address(this), liquidityCanto);
        lpTokenPairToken.transfer(address(this), liquidityPairToken);
        vm.stopPrank();

        lpTokenCanto.approve(address(chef), liquidityCanto);
        lpTokenPairToken.approve(address(chef), liquidityPairToken);
        chef.deposit(0, liquidityCanto, address(this));
        chef.deposit(1, liquidityPairToken, address(this));
        assertEq(lpTokenCanto.balanceOf(address(chef)), liquidityCanto);
        assertEq(lpTokenPairToken.balanceOf(address(chef)), liquidityPairToken);

        uint256 elapsed = 666 seconds;
        uint256 pendingRewardCantoPool = (emissionsPerSecond *
            elapsed *
            allocPointsCantoPool) / totalAllocPoints;
        uint256 pendingRewardPairTokenPool = (emissionsPerSecond *
            elapsed *
            allocPointsPairTokenPool) / totalAllocPoints;
        uint256 totalPendingReward = emissionsPerSecond * elapsed;
        vm.warp(block.timestamp + elapsed);
        assertApproxEqAbs(
            chef.pendingPrimaryToken(0, address(this)),
            pendingRewardCantoPool,
            9
        );
        assertApproxEqAbs(
            chef.pendingPrimaryToken(1, address(this)),
            pendingRewardPairTokenPool,
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
            pendingRewardPairTokenPool,
            9
        );

        chef.withdrawAndHarvest(0, liquidityCanto, address(this));
        chef.withdrawAndHarvest(1, liquidityPairToken, address(this));
        assertApproxEqAbs(
            leet.balanceOf(address(this)),
            totalPendingReward * 2,
            9
        );
    }

    function testClaimFees() public {
        uint256 liquidity = addLiquidityWithPairToken(800e3);
        IERC20 lpToken = IERC20(
            router.pairFor(address(leet), address(pairToken))
        );
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
        uint256 pairTokenFeesAccrued = (buyAmount * tradingFees * liquidity) /
            1e4 /
            lpToken.totalSupply();
        assertEq(tradingFees, 30);

        pairToken.mint(address(this), buyAmount);
        buyLeetWithPairToken(buyAmount);

        vm.prank(chef.owner());
        chef.claimLPFees(0);
        assertEq(pairToken.balanceOf(chef.owner()), pairTokenFeesAccrued);
    }

    function testClaimFeesWithExistingBalance() public {
        uint256 liquidity = addLiquidityWithPairToken(800e3);
        IERC20 lpToken = IERC20(
            router.pairFor(address(leet), address(pairToken))
        );
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
        uint256 pairTokenFeesAccrued = (buyAmount * tradingFees * liquidity) /
            1e4 /
            lpToken.totalSupply();
        assertEq(tradingFees, 30);

        pairToken.mint(address(this), buyAmount + existingChefBalance);
        pairToken.mint(address(chef), existingChefBalance);
        buyLeetWithPairToken(buyAmount);

        vm.prank(chef.owner());
        chef.claimLPFees(0);
        assertEq(pairToken.balanceOf(chef.owner()), pairTokenFeesAccrued);
        assertEq(pairToken.balanceOf(address(chef)), existingChefBalance);
    }

    function testTimeLimitedRewarderPendingRewards() public {
        uint256 liquidity = addLiquidityWithCanto(800e3);
        IERC20 lpToken = IERC20(router.pairFor(address(leet), address(weth)));
        MockERC20 rewardToken = new MockERC20("RewardToken", "RT", 9);
        vm.label(address(rewardToken), "rewardToken");

        uint256 totalRewardableAmount = 70e12 * 10 ** rewardToken.decimals();
        uint256 duration = 60 days;

        uint256 startTimestamp = block.timestamp;
        TimeLimitedRewarder rewarder = new TimeLimitedRewarder(
            IERC20(address(rewardToken)), // secondary reward token
            totalRewardableAmount,
            address(chef),
            duration
        );
        vm.label(address(rewarder), "rewarder");

        vm.startPrank(chef.owner());
        chef.add(1 /*allocPoint*/, lpToken, rewarder);
        chef.setPrimaryTokenPerSecond(
            0.01 ether /*primary emissions per second*/,
            true
        );
        vm.stopPrank();

        // vm.prank(rewarder.owner());
        // rewarder.add(allocPoints, 0 /*pid*/);

        vm.prank(rewarder.owner());
        rewarder.set(0 /*pid*/, 1 /*allocPoints*/);

        rewardToken.mint(address(rewarder), totalRewardableAmount);

        vm.prank(leet.owner());
        lpToken.transfer(address(this), liquidity);

        lpToken.approve(address(chef), UINT256_MAX);
        chef.deposit(0, liquidity, address(this));
        assertEq(lpToken.balanceOf(address(chef)), liquidity);

        uint256 emissionsPerSecond = totalRewardableAmount / duration;
        uint256 elapsed = 1 seconds;
        uint256 pendingReward = emissionsPerSecond * elapsed;
        vm.warp(block.timestamp + elapsed);
        (
            IERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        ) = rewarder.pendingTokens(0, address(this), 0 /*dummy arg*/);
        assertTrue(rewardTokens[0] == IERC20(address(rewardToken)));
        assertApproxEqAbs(rewardAmounts[0], pendingReward, 9);

        uint256 initialBalance = IERC20(address(rewardToken)).balanceOf(
            address(this)
        );

        chef.harvest(0, address(this));
        assertApproxEqAbs(
            IERC20(address(rewardToken)).balanceOf(address(this)) -
                initialBalance,
            pendingReward,
            9
        );

        vm.warp(block.timestamp + elapsed);
        (rewardTokens, rewardAmounts) = rewarder.pendingTokens(
            0,
            address(this),
            0 /*dummy arg*/
        );
        assertApproxEqAbs(rewardAmounts[0], pendingReward, 9);

        chef.withdrawAndHarvest(0, liquidity, address(this));
        assertEq(lpToken.balanceOf(address(this)), liquidity);
        assertApproxEqAbs(
            IERC20(address(rewardToken)).balanceOf(address(this)) -
                initialBalance,
            pendingReward * 2,
            9
        );
        chef.deposit(0, liquidity, address(this));

        assertEq(rewarder.rewardPerSecond(), emissionsPerSecond);
        vm.warp(startTimestamp - 1);
        assertEq(rewarder.rewardPerSecond(), 0);
        vm.warp(startTimestamp + duration + 1);
        assertEq(rewarder.rewardPerSecond(), 0);

        vm.warp(startTimestamp + duration + 1 hours);
        chef.harvest(0, address(this));
        assertApproxEqAbs(
            IERC20(address(rewardToken)).balanceOf(address(this)) -
                initialBalance,
            totalRewardableAmount,
            1e9
        );
    }

    receive() external payable {}
}

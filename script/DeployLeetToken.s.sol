// SPDX-License-Identifier:AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {LeetToken, ILeetSwapV2Router01} from "@leetswap/tokens/LeetToken.sol";
import {LeetChefV1, IRewarder} from "@leetswap/farms/LeetChefV1.sol";
import {LeetBar} from "@leetswap/staking/LeetBar.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract DeployLeetToken is Test {
    using Strings for uint256;

    IERC20Metadata public wcanto =
        IERC20Metadata(0x04a72466De69109889Db059Cb1A4460Ca0648d9D);
    IERC20Metadata public note =
        IERC20Metadata(0x03F734Bd9847575fDbE9bEaDDf9C166F880B5E5f);

    uint256 public constant TOTAL_SUPPLY = 1337000 ether;
    uint256 public constant TEAM_SHARE = 500;
    uint256 public constant MARKETING_SHARE = 500;
    uint256 public constant LIQUIDITY_SHARE = 3000;
    uint256 public constant REWARDS_SHARE = 6000;
    uint256 public constant TOTAL_SHARE =
        TEAM_SHARE + MARKETING_SHARE + LIQUIDITY_SHARE + REWARDS_SHARE;

    uint64 public constant TEAM_CLIFF = 180 days;
    uint64 public constant TEAM_VESTING = 2 * 365 days;
    uint64 public constant MARKETING_VESTING = 2 * 365 days;

    uint256 public constant TEAM_SUPPLY =
        (TOTAL_SUPPLY * TEAM_SHARE) / TOTAL_SHARE;
    uint256 public constant MARKETING_SUPPLY =
        (TOTAL_SUPPLY * MARKETING_SHARE) / TOTAL_SHARE;
    uint256 public constant LIQUIDITY_SUPPLY =
        (TOTAL_SUPPLY * LIQUIDITY_SHARE) / TOTAL_SHARE;
    uint256 public constant REWARDS_SUPPLY =
        TOTAL_SUPPLY - TEAM_SUPPLY - MARKETING_SUPPLY - LIQUIDITY_SUPPLY;

    function setUp() public {
        console.log(
            "Running script on chain with ID:",
            block.chainid.toString()
        );
        assertEq(TOTAL_SHARE, 1e4);
    }

    function run(address router) external returns (LeetToken leet) {
        leet = deploy(router);
    }

    function deploy(address router) public returns (LeetToken leet) {
        vm.broadcast();
        return new LeetToken(router);
    }

    function deployAndLaunch(
        ILeetSwapV2Router01 router,
        uint256 noteLiquidityAmount,
        uint256 launchTimestamp
    )
        external
        returns (
            LeetToken leet,
            LeetChefV1 chef,
            LeetBar bar
        )
    {
        assertGt(launchTimestamp, block.timestamp);

        console.log("Trading will be enabled at:", launchTimestamp);
        console.log(
            "Initial liquidity NOTE:",
            noteLiquidityAmount / 10**note.decimals()
        );

        vm.startBroadcast();

        leet = new LeetToken(address(router));
        address sender = leet.owner();
        assertGe(note.balanceOf(sender), noteLiquidityAmount);
        console.log("Leet token deployed at:", address(leet));

        leet.setTradingEnabledTimestamp(launchTimestamp);
        assertEq(TOTAL_SUPPLY, leet.totalSupply());
        assertEq(leet.balanceOf(sender), TOTAL_SUPPLY);

        assertEq(
            TEAM_SUPPLY + MARKETING_SUPPLY + LIQUIDITY_SUPPLY + REWARDS_SUPPLY,
            TOTAL_SUPPLY
        );

        IERC20Metadata lpToken = IERC20Metadata(
            router.pairFor(address(leet), address(note))
        );
        assertEq(lpToken.totalSupply(), 0);

        VestingWallet teamWallet = new VestingWallet(
            sender, // beneficiary
            uint64(launchTimestamp + TEAM_CLIFF), // start
            TEAM_VESTING // duration
        );
        leet.transfer(address(teamWallet), TEAM_SUPPLY);

        VestingWallet marketingWallet = new VestingWallet(
            sender, // beneficiary
            uint64(launchTimestamp), // start
            MARKETING_VESTING // duration
        );
        leet.transfer(address(marketingWallet), MARKETING_SUPPLY);

        leet.approve(address(router), type(uint256).max);
        note.approve(address(router), type(uint256).max);
        uint256 initialLiquidityAmount = (LIQUIDITY_SUPPLY * 75) / 100;
        (, , uint256 liquidity) = router.addLiquidity(
            address(leet),
            address(note),
            initialLiquidityAmount,
            noteLiquidityAmount,
            0,
            0,
            sender,
            block.timestamp + 10 minutes
        );

        uint256 lpTokenBalance = lpToken.balanceOf(sender);
        assertEq(liquidity, lpTokenBalance);

        chef = new LeetChefV1(leet);
        console.log("LeetChefV1 deployed at:", address(chef));

        bar = new LeetBar(leet);
        console.log("LeetBar deployed at:", address(bar));

        uint256 barAmount = 1337 * 10**leet.decimals();
        leet.approve(address(bar), type(uint256).max);
        bar.enter(barAmount);
        assertEq(bar.balanceOf(sender), barAmount);

        chef.add(1000, lpToken, IRewarder(address(0)));
        lpToken.approve(address(chef), type(uint256).max);
        chef.deposit(0, lpTokenBalance, sender);
        leet.transfer(address(chef), REWARDS_SUPPLY - barAmount);
        leet.transfer(address(leet), LIQUIDITY_SUPPLY - initialLiquidityAmount);

        assertEq(leet.balanceOf(sender), 0);
        assertEq(leet.balanceOf(address(chef)), REWARDS_SUPPLY - barAmount);
        assertEq(leet.balanceOf(address(bar)), barAmount);
        assertEq(
            leet.balanceOf(address(leet)),
            LIQUIDITY_SUPPLY - initialLiquidityAmount
        );

        leet.setFarmsFeeRecipient(address(chef));
        leet.setStakingFeeRecipient(address(bar));
        leet.enableTrading();

        vm.stopBroadcast();
    }
}

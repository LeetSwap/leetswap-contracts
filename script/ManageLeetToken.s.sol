// SPDX-License-Identifier:AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "@leetswap/tokens/LeetToken.sol";
import "@leetswap/dex/v2/LeetSwapV2Router01.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract ManageLeetToken is Test {
    using Strings for uint256;

    address public wcanto = 0x4F9A0e7FD2Bf6067db6994CF12E4495Df938E6e9;

    function setUp() public view {
        console.log(
            "Running script on chain with ID:",
            block.chainid.toString()
        );
    }

    function addPair(LeetToken leet, address pair) public {
        vm.broadcast();
        leet.addLeetPair(pair);
    }

    function enableTrading(LeetToken leet) public {
        vm.broadcast();
        leet.enableTrading();
    }

    function setTradingEnabledTimestamp(LeetToken leet, uint256 timestamp)
        public
    {
        vm.broadcast();
        leet.setTradingEnabledTimestamp(timestamp);
    }

    function setMaxWalletEnabled(LeetToken leet, bool enabled) public {
        vm.broadcast();
        leet.setMaxWalletEnabled(enabled);
    }

    function setIndirectSwapFeeEnabled(
        LeetToken leet,
        bool indirectSwapFeeEnabled
    ) public {
        vm.broadcast();
        leet.setIndirectSwapFeeEnabled(indirectSwapFeeEnabled);
    }

    function whitelistLeet(LeetToken leet) public {
        LeetSwapV2Router01 router = LeetSwapV2Router01(
            payable(address(leet.swapFeesRouter()))
        );

        vm.startBroadcast();
        router.setLiquidityManageableEnabled(true);
        router.setLiquidityManageableWhitelistEnabled(true);
        router.addLiquidityManageableWhitelist(address(leet));
        vm.stopBroadcast();
    }

    function balanceOf(LeetToken leet, address account)
        public
        view
        returns (uint256 balance)
    {
        balance = leet.balanceOf(account);
    }

    function setMaxSwapFeesAmount(LeetToken leet, uint256 amount) public {
        vm.broadcast();
        leet.setMaxSwapFeesAmount(amount);
    }

    function setSwapFeesAtAmount(LeetToken leet, uint256 amount) public {
        vm.broadcast();
        leet.setSwapFeesAtAmount(amount);
    }

    function setFeeDiscountOracle(LeetToken leet, IFeeDiscountOracle oracle)
        public
    {
        vm.broadcast();
        leet.setFeeDiscountOracle(oracle);
    }

    function airdropHolders(
        LeetToken leet,
        string memory addressesFilename,
        string memory amountsFilename
    ) external {
        string memory root = string.concat(vm.projectRoot(), "/");

        string memory addressesPath = string.concat(root, addressesFilename);
        bytes memory addressesJson = vm.parseJson(vm.readFile(addressesPath));
        address[] memory addresses = abi.decode(addressesJson, (address[]));

        string memory amountsPath = string.concat(root, amountsFilename);
        bytes memory amountsJson = vm.parseJson(vm.readFile(amountsPath));
        uint256[] memory amounts = abi.decode(amountsJson, (uint256[]));

        uint256 totalAirdropAmount;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAirdropAmount += amounts[i];
        }
        console.log("Total airdrop amount:", totalAirdropAmount);

        vm.broadcast(msg.sender);
        leet.airdropHolders(addresses, amounts);
    }

    function buyLeet(
        ILeetSwapV2Router01 router,
        LeetToken leet,
        uint256 amountETH
    ) public {
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(leet);

        vm.broadcast();
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: amountETH
        }(0, path, msg.sender, block.timestamp);
    }

    function sellLeet(
        ILeetSwapV2Router01 router,
        LeetToken leet,
        uint256 amount
    ) public {
        address[] memory path = new address[](2);
        path[0] = address(leet);
        // path[1] = leet.swapPairToken();
        path[1] = router.WETH();

        vm.broadcast();
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            msg.sender,
            block.timestamp
        );
    }
}

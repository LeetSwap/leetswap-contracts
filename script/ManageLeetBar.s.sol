// SPDX-License-Identifier:AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "@leetswap/staking/LeetBar.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract ManageLeetBar is Test {
    using Strings for uint256;

    address public wcanto = 0x04a72466De69109889Db059Cb1A4460Ca0648d9D;

    function setUp() public view {
        console.log(
            "Running script on chain with ID:",
            block.chainid.toString()
        );
    }

    function enter(LeetBar bar, uint256 amount) public {
        IERC20 leet = bar.leet();

        vm.startBroadcast();

        leet.approve(address(bar), amount);
        bar.enter(amount);

        vm.stopBroadcast();
    }
}

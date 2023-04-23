// SPDX-License-Identifier:AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "@leetswap/staking/LeetBar.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract DeployLeetBar is Test {
    using Strings for uint256;

    address public wcanto = 0x4F9A0e7FD2Bf6067db6994CF12E4495Df938E6e9;

    function setUp() public view {
        console.log(
            "Running script on chain with ID:",
            block.chainid.toString()
        );
    }

    function run(IERC20 leet) external returns (LeetBar leetBar) {
        vm.broadcast();
        leetBar = new LeetBar(leet);
    }
}

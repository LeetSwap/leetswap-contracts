// SPDX-License-Identifier:AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "@leetswap/farms/LeetChefV1.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract DeployLeetChefV1 is Test {
    using Strings for uint256;

    function setUp() public view {
        console.log(
            "Running script on chain with ID:",
            block.chainid.toString()
        );
    }

    function run(IERC20 leet) external returns (LeetChefV1 leetChef) {
        vm.broadcast();
        leetChef = new LeetChefV1(leet);
    }
}

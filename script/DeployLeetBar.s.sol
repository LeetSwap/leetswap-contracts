// SPDX-License-Identifier:AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "@leetswap/staking/LeetBar.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract DeployLeetBar is Test {
    using Strings for uint256;

    address public wcanto = 0x826551890Dc65655a0Aceca109aB11AbDbD7a07B;
    ITurnstile public turnstile =
        ITurnstile(0xEcf044C5B4b867CFda001101c617eCd347095B44);

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

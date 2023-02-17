// SPDX-License-Identifier:AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "@leetswap/tokens/LeetToken.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract ManageLeetToken is Test {
    using Strings for uint256;

    address public wcanto = 0x826551890Dc65655a0Aceca109aB11AbDbD7a07B;

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
}

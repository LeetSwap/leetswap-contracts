// SPDX-License-Identifier:AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "@leetswap/farms/LeetChefV1.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract ManageLeetChefV1 is Test {
    using Strings for uint256;

    address public wcanto = 0x826551890Dc65655a0Aceca109aB11AbDbD7a07B;

    function setUp() public view {
        console.log(
            "Running script on chain with ID:",
            block.chainid.toString()
        );
    }

    function addLPToken(
        LeetChefV1 leetChef,
        IERC20 lpToken,
        uint256 allocPoints
    ) public {
        vm.broadcast();
        leetChef.add(allocPoints, lpToken, IRewarder(address(0)));
    }

    function addLPTokenWithRewarder(
        LeetChefV1 leetChef,
        IERC20 lpToken,
        uint256 allocPoints,
        IRewarder rewarder
    ) public {
        vm.broadcast();
        leetChef.add(allocPoints, lpToken, rewarder);
    }

    function setEmissionsPerSecond(
        LeetChefV1 leetChef,
        uint256 emissionsPerSecond
    ) public {
        vm.broadcast();
        leetChef.setPrimaryTokenPerSecond(emissionsPerSecond, true);
    }

    function claimAllLPFees(LeetChefV1 leetChef) public {
        vm.broadcast();
        leetChef.claimAllLPFees();
    }

    function pendingPrimaryToken(LeetChefV1 leetChef, uint256 pid)
        public
        view
        returns (uint256)
    {
        return leetChef.pendingPrimaryToken(pid, msg.sender);
    }

    function withdrawLeet(LeetChefV1 chef, uint256 amount) public {
        vm.broadcast();
        chef.reclaimPrimaryToken(amount);
    }
}

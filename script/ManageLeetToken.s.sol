// SPDX-License-Identifier:AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "@leetswap/tokens/LeetToken.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract ManageLeetToken is Test {
    using Strings for uint256;

    address public wcanto = 0x04a72466De69109889Db059Cb1A4460Ca0648d9D;

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

    function setIndirectSwapFeeEnabled(
        LeetToken leet,
        bool indirectSwapFeeEnabled
    ) public {
        vm.broadcast();
        leet.setIndirectSwapFeeEnabled(indirectSwapFeeEnabled);
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
}

// SPDX-License-Identifier:AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "@leetswap/dex/v2/LeetSwapV2Factory.sol";
import "@leetswap/dex/v2/LeetSwapV2Router01.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract DeployDEXV2 is Test {
    using Strings for uint256;

    mapping(uint256 => address) public wcantoAddresses;
    address public wcanto;

    function setUp() public {
        console.log(
            "Running script on chain with ID:",
            block.chainid.toString()
        );

        wcantoAddresses[8453] = 0x4200000000000000000000000000000000000006;
        wcantoAddresses[84531] = 0x4200000000000000000000000000000000000006;

        wcanto = wcantoAddresses[block.chainid];
        require(wcanto != address(0), "wcanto: unsupported chain");
    }

    function run()
        external
        returns (LeetSwapV2Factory factory, LeetSwapV2Router01 router)
    {
        (factory, router) = deploy(wcanto);

        console.log("Factory deployed at:", address(factory));
        console.log("Router deployed at:", address(router));

        bytes32 pairInitCodeHash = factory.pairCodeHash();
        console.logBytes32(pairInitCodeHash);
    }

    function deploy(
        address _wcanto
    ) public returns (LeetSwapV2Factory factory, LeetSwapV2Router01 router) {
        vm.startBroadcast();

        factory = new LeetSwapV2Factory();
        router = new LeetSwapV2Router01(address(factory), _wcanto);

        vm.stopBroadcast();
    }

    function deployRouter(
        address _factory
    ) public returns (LeetSwapV2Router01 router) {
        vm.startBroadcast();
        router = new LeetSwapV2Router01(address(_factory), wcanto);
    }
}

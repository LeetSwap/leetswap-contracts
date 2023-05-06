// SPDX-License-Identifier:AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "@leetswap/dex/v2/LeetSwapV2Factory.sol";
import "@leetswap/dex/v2/LeetSwapV2Router01.sol";
import "@leetswap/interfaces/ITurnstile.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract DeployDEXV2 is Test {
    using Strings for uint256;

    address public wcanto = 0x04a72466De69109889Db059Cb1A4460Ca0648d9D;
    address public cantoDEXFactory = 0x760a17e00173339907505B38F95755d28810570C;
    ITurnstile public turnstile =
        ITurnstile(0xEcf044C5B4b867CFda001101c617eCd347095B44);

    function setUp() public view {
        console.log(
            "Running script on chain with ID:",
            block.chainid.toString()
        );
    }

    function run()
        external
        returns (LeetSwapV2Factory factory, LeetSwapV2Router01 router)
    {
        vm.startBroadcast();

        factory = new LeetSwapV2Factory(turnstile);
        router = new LeetSwapV2Router01(
            address(factory),
            wcanto,
            cantoDEXFactory
        );

        router.setStablePair(0x252631e22e1ECc2fc0E811562605ed624B7E31d5, true); // NOTE/USDT
        router.setStablePair(0x2db30A39Ec88247da8906506DB8E9dd933A5C775, true); // NOTE/USDC

        address note = 0x03F734Bd9847575fDbE9bEaDDf9C166F880B5E5f;
        address usdc = 0xc51534568489f47949A828C8e3BF68463bdF3566;
        address eth = 0xCa03230E7FB13456326a234443aAd111AC96410A;
        address atom = 0x40E41DC5845619E7Ba73957449b31DFbfB9678b2;
        address usdt = 0x4fC30060226c45D8948718C95a78dFB237e88b40;

        router.setCantoDEXForTokens(note, usdc, true);
        router.setCantoDEXForTokens(note, usdt, true);
        router.setCantoDEXForTokens(wcanto, note, true);
        router.setCantoDEXForTokens(eth, wcanto, true);
        router.setCantoDEXForTokens(atom, wcanto, true);

        vm.stopBroadcast();

        console.log("Factory deployed at:", address(factory));
        console.log("Router deployed at:", address(router));

        bytes32 pairInitCodeHash = factory.pairCodeHash();
        console.logBytes32(pairInitCodeHash);
    }
}

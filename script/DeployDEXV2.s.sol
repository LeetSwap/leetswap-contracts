// SPDX-License-Identifier:AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "@leetswap/dex/v2/LeetSwapV2Factory.sol";
import "@leetswap/dex/v2/LeetSwapV2Router01.sol";
import "@leetswap/interfaces/ITurnstile.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract DeployDEXV2 is Test {
    using Strings for uint256;

    address public wcanto = 0x826551890Dc65655a0Aceca109aB11AbDbD7a07B;
    address public cantoDEXFactory = 0xE387067f12561e579C5f7d4294f51867E0c1cFba;
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

        router.setStablePair(0x35DB1f3a6A6F07f82C76fCC415dB6cFB1a7df833, true); // NOTE/USDT
        router.setStablePair(0x9571997a66D63958e1B3De9647C22bD6b9e7228c, true); // NOTE/USDC
        router.setStablePair(0x3CE59FaB4b43B2709343Ba29c768E222e080e2a4, true); // USDT/USDC

        address note = 0x4e71A2E537B7f9D9413D3991D37958c0b5e1e503;
        address usdc = 0x80b5a32E4F032B2a058b4F29EC95EEfEEB87aDcd;
        address eth = 0x5FD55A1B9FC24967C4dB09C513C3BA0DFa7FF687;
        address atom = 0xecEEEfCEE421D8062EF8d6b4D814efe4dc898265;
        address usdt = 0xd567B3d7B8FE3C79a1AD8dA978812cfC4Fa05e75;
        address upsample = 0x069C4887f2eafCbE7D3572e13b449A02B31D260C;
        address bank = 0x6f6BAe4110eCC33fE4E330b16b8df2A5E9807658;
        address topg = 0xe350b49e52c9d865735BFD77c956f64585Be7583;

        router.setCantoDEXForTokens(upsample, note, true);
        router.setCantoDEXForTokens(bank, wcanto, true);
        router.setCantoDEXForTokens(topg, wcanto, true);
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

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "@leetswap/dex/native/BaseV1-core.sol";
import {LeetSwapV1Router01} from "@leetswap/dex/v1/LeetSwapV1Router01.sol";
import {LeetSwapV1Router02} from "@leetswap/dex/v1/LeetSwapV1Router02.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract DeployDEXV1 is Test {
    using Strings for uint256;

    function setUp() public view {
        console.log(
            "Running script on chain with ID:",
            block.chainid.toString()
        );
    }

    function run() external {
        vm.startBroadcast();
        LeetSwapV1Router02 router = new LeetSwapV1Router02(
            0x760a17e00173339907505B38F95755d28810570C,
            0x04a72466De69109889Db059Cb1A4460Ca0648d9D,
            0xEcf044C5B4b867CFda001101c617eCd347095B44
        );
        router.setStablePair(0x35DB1f3a6A6F07f82C76fCC415dB6cFB1a7df833, true); // NOTE/USDT
        router.setStablePair(0x9571997a66D63958e1B3De9647C22bD6b9e7228c, true); // NOTE/USDC
        router.setStablePair(0x3CE59FaB4b43B2709343Ba29c768E222e080e2a4, true); // USDT/USDC

        uint256 beneficiaryTokenID = router.registerCSR();
        console.log(
            "CSR registered with beneficiaryTokenID:",
            beneficiaryTokenID
        );

        vm.stopBroadcast();
        console.log("Deployed router at", address(router));
    }

    function v1() external {
        vm.startBroadcast();
        LeetSwapV1Router01 router = new LeetSwapV1Router01(
            0x760a17e00173339907505B38F95755d28810570C,
            0x04a72466De69109889Db059Cb1A4460Ca0648d9D
        );
        router.setStablePair(0x35DB1f3a6A6F07f82C76fCC415dB6cFB1a7df833, true); // NOTE/USDT
        router.setStablePair(0x9571997a66D63958e1B3De9647C22bD6b9e7228c, true); // NOTE/USDC
        router.setStablePair(0x3CE59FaB4b43B2709343Ba29c768E222e080e2a4, true); // USDT/USDC

        vm.stopBroadcast();
        console.log("Deployed router at", address(router));
    }

    function getInitCode() external view {
        BaseV1Factory factory = BaseV1Factory(
            0x760a17e00173339907505B38F95755d28810570C
        );
        bytes32 initCode = factory.pairCodeHash();
        console.logBytes32(initCode);
    }
}

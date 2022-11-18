// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "../src/BaseV1-core.sol";
import "../src/LeetSwapV1Router01.sol";
import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Deploy is Test {
    using Strings for uint256;

    function setUp() public view {
        console.log(
            "Running script on chain with ID:",
            block.chainid.toString()
        );
    }

    function run() external {
        vm.startBroadcast();
        LeetSwapV1Router01 router = new LeetSwapV1Router01(
            0xE387067f12561e579C5f7d4294f51867E0c1cFba,
            0x826551890Dc65655a0Aceca109aB11AbDbD7a07B
        );
        router.setStablePair(0x35DB1f3a6A6F07f82C76fCC415dB6cFB1a7df833, true); // NOTE/USDT
        router.setStablePair(0x9571997a66D63958e1B3De9647C22bD6b9e7228c, true); // NOTE/USDC
        router.setStablePair(0x3CE59FaB4b43B2709343Ba29c768E222e080e2a4, true); // USDT/USDC

        vm.stopBroadcast();
        console.log("Deployed router at", address(router));
    }

    function getInitCode() external view {
        BaseV1Factory factory = BaseV1Factory(
            0xE387067f12561e579C5f7d4294f51867E0c1cFba
        );
        bytes32 initCode = factory.pairCodeHash();
        console.logBytes32(initCode);
    }
}

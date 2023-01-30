// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "../src/interfaces/Turnstile.sol";
import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract ManageTurnstile is Test {
    using Strings for uint256;

    function setUp() public view {
        console.log(
            "Running script on chain with ID:",
            block.chainid.toString()
        );
    }

    function withdraw(address _turnstile, uint256 _tokenID) external {
        Turnstile turnstile = Turnstile(_turnstile);
        uint256 amount = turnstile.balances(_tokenID);
        address payable recipient = payable(msg.sender);
        console.log("Withdrawing", amount.toString(), "from tokenID", _tokenID);
        console.log("Sending to", recipient);

        vm.startBroadcast();
        turnstile.withdraw(_tokenID, recipient, amount);
        vm.stopBroadcast();
    }
}

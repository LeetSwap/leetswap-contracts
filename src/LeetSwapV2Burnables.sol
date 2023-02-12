// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./interfaces/ILeetSwapV2Factory.sol";
import "./interfaces/ILeetSwapV2Burnables.sol";
import "./interfaces/ITurnstile.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LeetSwapV2Burnables is ILeetSwapV2Burnables, Ownable {
    address public immutable factory;

    mapping(address => uint256) public burnableSharesBps;

    constructor() {
        factory = msg.sender;
        ITurnstile turnstile = ILeetSwapV2Factory(factory).turnstile();
        uint256 csrTokenID = turnstile.getTokenId(factory);
        turnstile.assign(csrTokenID);
    }

    function burnableAmount(address token, uint256 amount)
        external
        view
        returns (uint256 burnAmount)
    {
        burnAmount = (amount * burnableSharesBps[token]) / 10000;
    }

    function setBurnableShare(address token, uint256 shareBps)
        external
        onlyOwner
    {
        require(shareBps <= 10000);
        burnableSharesBps[token] = shareBps;
    }
}

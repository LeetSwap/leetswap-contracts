// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./interfaces/ILeetSwapV2Burnables.sol";
import "./interfaces/ILeetSwapV2Factory.sol";
import "./interfaces/ILeetSwapV2Pair.sol";
import "./interfaces/ITurnstile.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Base V1 Fees contract is used as a 1:1 pair relationship to split out fees, this ensures that the curve does not need to be modified for LP shares
contract LeetSwapV2Fees {
    address internal immutable pair; // The pair it is bonded to
    address internal immutable token0; // token0 of pair, saved localy and statically for gas optimization
    address internal immutable token1; // Token1 of pair, saved localy and statically for gas optimization
    ILeetSwapV2Burnables public immutable burnables; // Contract that keeps track of what tokens shall be burned

    constructor(
        address _token0,
        address _token1,
        ILeetSwapV2Burnables _burnables
    ) {
        pair = msg.sender;
        token0 = _token0;
        token1 = _token1;
        burnables = _burnables;

        address factory = ILeetSwapV2Pair(pair).factory();
        ITurnstile turnstile = ILeetSwapV2Factory(factory).turnstile();
        uint256 csrTokenID = turnstile.getTokenId(factory);
        turnstile.assign(csrTokenID);
    }

    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    // Allow the pair to transfer fees to users
    function claimFeesFor(
        address recipient,
        uint256 amount0,
        uint256 amount1
    ) external {
        require(msg.sender == pair);
        if (amount0 > 0) {
            uint256 burnAmount = burnables.burnableAmount(token0, amount0);
            _safeTransfer(token0, recipient, amount0 - burnAmount);
            _safeTransfer(token0, address(0xdead), burnAmount);
        }
        if (amount1 > 0) {
            uint256 burnAmount = burnables.burnableAmount(token1, amount1);
            _safeTransfer(token1, recipient, amount1 - burnAmount);
            _safeTransfer(token1, address(0xdead), burnAmount);
        }
    }
}

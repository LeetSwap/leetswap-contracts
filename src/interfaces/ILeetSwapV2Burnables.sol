// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ILeetSwapV2Burnables {
    function burnableAmount(address token, uint256 amount)
        external
        returns (uint256 burnAmount);
}

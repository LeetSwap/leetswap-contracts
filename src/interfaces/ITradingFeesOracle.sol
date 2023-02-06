// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

interface ITradingFeesOracle {
    function getTradingFees(address pair, address to)
        external
        view
        returns (uint256);
}

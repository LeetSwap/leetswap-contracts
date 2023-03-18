// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@leetswap/tokens/interfaces/IFeeDiscountOracle.sol";

contract StubFeeDiscountOracle is IFeeDiscountOracle {
    uint256 public immutable DISCOUNT_AMOUNT;

    constructor(uint256 discountAmount) {
        DISCOUNT_AMOUNT = discountAmount;
    }

    function buyFeeDiscountFor(address account, uint256 transferAmount)
        public
        view
        returns (uint256)
    {
        account;
        transferAmount;
        return DISCOUNT_AMOUNT;
    }

    function sellFeeDiscountFor(address account, uint256 transferAmount)
        public
        view
        returns (uint256)
    {
        account;
        transferAmount;
        return DISCOUNT_AMOUNT;
    }
}

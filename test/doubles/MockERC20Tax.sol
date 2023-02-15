// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract MockERC20Tax is MockERC20 {
    uint256 public immutable taxRate;
    uint256 public immutable taxDivisor;
    address public immutable taxRecipient;
    mapping(address => bool) public pairs;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 taxRate_,
        uint256 taxDivisor_,
        address taxRecipient_
    ) MockERC20(name, symbol, decimals) {
        taxRate = taxRate_;
        taxDivisor = taxDivisor_;
        taxRecipient = taxRecipient_;
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        uint256 tax;
        if (pairs[msg.sender] || pairs[recipient]) {
            tax = (amount * taxRate) / taxDivisor;
            require(super.transfer(taxRecipient, tax));
        }
        return super.transfer(recipient, amount - tax);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        uint256 tax;
        if (pairs[sender] || pairs[recipient]) {
            tax = (amount * taxRate) / taxDivisor;
            require(super.transferFrom(sender, taxRecipient, tax));
        }
        return super.transferFrom(sender, recipient, amount - tax);
    }

    function setPair(address pair, bool isPair) external {
        pairs[pair] = isPair;
    }
}

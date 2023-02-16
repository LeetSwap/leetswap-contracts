// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import "../../src/interfaces/ILiquidityManageable.sol";

contract MockERC20LiquidityManageable is MockERC20, ILiquidityManageable {
    uint256 public immutable taxRate;
    uint256 public immutable taxDivisor;
    address public immutable taxRecipient;

    mapping(address => bool) public pairs;
    mapping(address => bool) public liquidityManagers;

    bool internal _isLiquidityManagementPhase;

    error NotLiquidityManager();

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

    modifier onlyLiquidityManager() {
        if (!liquidityManagers[msg.sender]) {
            revert NotLiquidityManager();
        }
        _;
    }

    function _shouldTakeTransferTax(address sender, address recipient)
        internal
        view
        returns (bool)
    {
        return
            !_isLiquidityManagementPhase && (pairs[sender] || pairs[recipient]);
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        uint256 tax;
        if (_shouldTakeTransferTax(msg.sender, recipient)) {
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
        if (_shouldTakeTransferTax(sender, recipient)) {
            tax = (amount * taxRate) / taxDivisor;
            require(super.transferFrom(sender, taxRecipient, tax));
        }
        return super.transferFrom(sender, recipient, amount - tax);
    }

    function isLiquidityManagementPhase() external view returns (bool) {
        return _isLiquidityManagementPhase;
    }

    function isLiquidityManager(address account)
        external
        view
        override
        returns (bool)
    {
        return liquidityManagers[account];
    }

    function setLiquidityManagementPhase(bool isLiquidityManagementPhase_)
        external
        onlyLiquidityManager
    {
        _isLiquidityManagementPhase = isLiquidityManagementPhase_;
    }

    function setPair(address pair, bool isPair) external {
        pairs[pair] = isPair;
    }

    function setLiquidityManager(address manager, bool isManager) external {
        liquidityManagers[manager] = isManager;
    }
}

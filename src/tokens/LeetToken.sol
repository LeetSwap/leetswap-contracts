// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "@leetswap/interfaces/ILiquidityManageable.sol";
import "@leetswap/dex/v2/interfaces/ILeetSwapV2Router01.sol";
import "@leetswap/dex/v2/interfaces/ILeetSwapV2Factory.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LeetToken is ERC20, Ownable, ILiquidityManageable {
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 public constant FEE_DENOMINATOR = 1e4;
    uint256 public constant MAX_FEE = 1000;
    ITurnstile public immutable turnstile;

    uint256 public burnBuyFee;
    uint256 public farmsBuyFee;
    uint256 public stakingBuyFee;
    uint256 public treasuryBuyFee;
    uint256 public totalBuyFee;

    uint256 public burnSellFee;
    uint256 public farmsSellFee;
    uint256 public stakingSellFee;
    uint256 public treasurySellFee;
    uint256 public totalSellFee;

    address public farmsFeeRecipient;
    address public stakingFeeRecipient;
    address public treasuryFeeRecipient;

    bool public tradingEnabled;
    bool public pairAutoDetectionEnabled;

    mapping(address => bool) public isExcludedFromFee;
    mapping(address => bool) public isLiquidityManager;

    bool internal _isLiquidityManagementPhase;
    mapping(address => bool) internal _isLeetPair;

    event BuyFeeUpdated(uint256 _fee, uint256 _previousFee);
    event SellFeeUpdated(uint256 _fee, uint256 _previousFee);
    event LeetPairAdded(address _pair);
    event LeetPairRemoved(address _pair);
    event AddressExcludedFromFees(address _address);
    event AddressIncludedInFees(address _address);

    error TradingNotEnabled();
    error FeeTooHigh();
    error InvalidFeeRecipient();
    error NotLiquidityManager();

    constructor(address _router) ERC20("Leet", "LEET") {
        ILeetSwapV2Router01 router = ILeetSwapV2Router01(_router);
        ILeetSwapV2Factory factory = ILeetSwapV2Factory(router.factory());
        turnstile = factory.turnstile();
        uint256 csrTokenID = turnstile.getTokenId(address(factory));
        turnstile.assign(csrTokenID);

        isExcludedFromFee[owner()] = true;
        isExcludedFromFee[address(this)] = true;
        isExcludedFromFee[DEAD] = true;

        burnBuyFee = 0;
        farmsBuyFee = 100;
        stakingBuyFee = 50;
        treasuryBuyFee = 0;
        setBuyFees(burnBuyFee, farmsBuyFee, stakingBuyFee, treasuryBuyFee);

        burnSellFee = 0;
        farmsSellFee = 100;
        stakingSellFee = 50;
        treasurySellFee = 0;
        setSellFees(burnSellFee, farmsSellFee, stakingSellFee, treasurySellFee);

        farmsFeeRecipient = owner();
        stakingFeeRecipient = owner();
        treasuryFeeRecipient = owner();

        isLiquidityManager[address(router)] = true;

        address pair = factory.createPair(address(this), router.WETH());
        _isLeetPair[pair] = true;
        pairAutoDetectionEnabled = true;

        _mint(owner(), 1337000 * 10**decimals());
    }

    modifier onlyLiquidityManager() {
        if (!isLiquidityManager[msg.sender]) {
            revert NotLiquidityManager();
        }
        _;
    }

    /************************************************************************/

    function isLeetPair(address _pair) public view returns (bool isPair) {
        if (_isLeetPair[_pair]) {
            return true;
        }

        if (!pairAutoDetectionEnabled) {
            return false;
        }

        (bool success, bytes memory data) = _pair.staticcall(
            abi.encodeWithSignature("factory()")
        );
        if (!success) {
            return false;
        }

        (success, data) = _pair.staticcall(abi.encodeWithSignature("token0()"));
        address token0 = abi.decode(data, (address));
        if (!success) {
            return false;
        } else if (token0 == address(this)) {
            return true;
        }

        (success, data) = _pair.staticcall(abi.encodeWithSignature("token1()"));
        address token1 = abi.decode(data, (address));
        if (!success) {
            return false;
        } else if (token1 == address(this)) {
            return true;
        }

        return false;
    }

    function _shouldTakeTransferTax(address sender, address recipient)
        internal
        view
        returns (bool)
    {
        if (isExcludedFromFee[sender] || isExcludedFromFee[recipient]) {
            return false;
        }

        return
            !_isLiquidityManagementPhase &&
            (isLeetPair(sender) || isLeetPair(recipient));
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        uint256 totalFeeAmount;
        uint256 burnFeeAmount;
        uint256 farmsFeeAmount;
        uint256 stakingFeeAmount;
        uint256 treasuryFeeAmount;

        if (
            !tradingEnabled &&
            !isExcludedFromFee[sender] &&
            !isExcludedFromFee[recipient]
        ) {
            revert TradingNotEnabled();
        }

        if (_shouldTakeTransferTax(sender, recipient)) {
            if (isLeetPair(sender)) {
                burnFeeAmount = (amount * burnBuyFee) / FEE_DENOMINATOR;
                farmsFeeAmount = (amount * farmsBuyFee) / FEE_DENOMINATOR;
                stakingFeeAmount = (amount * stakingBuyFee) / FEE_DENOMINATOR;
                treasuryFeeAmount = (amount * treasuryBuyFee) / FEE_DENOMINATOR;
            } else if (isLeetPair(recipient)) {
                burnFeeAmount = (amount * burnSellFee) / FEE_DENOMINATOR;
                farmsFeeAmount = (amount * farmsSellFee) / FEE_DENOMINATOR;
                stakingFeeAmount = (amount * stakingSellFee) / FEE_DENOMINATOR;
                treasuryFeeAmount =
                    (amount * treasurySellFee) /
                    FEE_DENOMINATOR;
            }

            totalFeeAmount =
                burnFeeAmount +
                farmsFeeAmount +
                stakingFeeAmount +
                treasuryFeeAmount;
        }

        if (totalFeeAmount > 0) {
            super._transfer(sender, DEAD, burnFeeAmount);
            super._transfer(sender, farmsFeeRecipient, farmsFeeAmount);
            super._transfer(sender, stakingFeeRecipient, stakingFeeAmount);
            super._transfer(sender, treasuryFeeRecipient, treasuryFeeAmount);
        }

        super._transfer(sender, recipient, amount - totalFeeAmount);
    }

    /************************************************************************/

    function isLiquidityManagementPhase() external view returns (bool) {
        return _isLiquidityManagementPhase;
    }

    function setLiquidityManagementPhase(bool isLiquidityManagementPhase_)
        external
        onlyLiquidityManager
    {
        _isLiquidityManagementPhase = isLiquidityManagementPhase_;
    }

    /************************************************************************/

    function addLeetPair(address _pair) external onlyOwner {
        _isLeetPair[_pair] = true;
        emit LeetPairAdded(_pair);
    }

    function removeLeetPair(address _pair) external onlyOwner {
        _isLeetPair[_pair] = false;
        emit LeetPairRemoved(_pair);
    }

    function excludeFromFee(address _account) external onlyOwner {
        isExcludedFromFee[_account] = true;
        emit AddressExcludedFromFees(_account);
    }

    function includeInFee(address _account) external onlyOwner {
        isExcludedFromFee[_account] = false;
        emit AddressIncludedInFees(_account);
    }

    function setFarmsFeeRecipient(address _account) external onlyOwner {
        if (_account == address(0)) {
            revert InvalidFeeRecipient();
        }
        farmsFeeRecipient = _account;
    }

    function setStakingFeeRecipient(address _account) external onlyOwner {
        if (_account == address(0)) {
            revert InvalidFeeRecipient();
        }
        stakingFeeRecipient = _account;
    }

    function setTreasuryFeeRecipient(address _account) external onlyOwner {
        if (_account == address(0)) {
            revert InvalidFeeRecipient();
        }

        treasuryFeeRecipient = _account;
    }

    function setBuyFees(
        uint256 _burnBuyFee,
        uint256 _farmsBuyFee,
        uint256 _stakingBuyFee,
        uint256 _treasuryBuyFee
    ) public onlyOwner {
        if (
            _burnBuyFee + _farmsBuyFee + _stakingBuyFee + _treasuryBuyFee >
            MAX_FEE
        ) {
            revert FeeTooHigh();
        }

        burnBuyFee = _burnBuyFee;
        farmsBuyFee = _farmsBuyFee;
        stakingBuyFee = _stakingBuyFee;
        treasuryBuyFee = _treasuryBuyFee;
        totalBuyFee = burnBuyFee + farmsBuyFee + stakingBuyFee + treasuryBuyFee;
    }

    function setSellFees(
        uint256 _burnSellFee,
        uint256 _farmsSellFee,
        uint256 _stakingSellFee,
        uint256 _treasurySellFee
    ) public onlyOwner {
        if (
            _burnSellFee + _farmsSellFee + _stakingSellFee + _treasurySellFee >
            MAX_FEE
        ) {
            revert FeeTooHigh();
        }

        burnSellFee = _burnSellFee;
        farmsSellFee = _farmsSellFee;
        stakingSellFee = _stakingSellFee;
        treasurySellFee = _treasurySellFee;
        totalSellFee =
            burnSellFee +
            farmsSellFee +
            stakingSellFee +
            treasurySellFee;
    }

    function setLiquidityManager(address _liquidityManager, bool _isManager)
        public
        onlyOwner
    {
        isLiquidityManager[_liquidityManager] = _isManager;
    }
}

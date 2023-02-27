// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "@leetswap/interfaces/ILiquidityManageable.sol";
import "@leetswap/dex/v2/interfaces/ILeetSwapV2Router01.sol";
import "@leetswap/dex/v2/interfaces/ILeetSwapV2Factory.sol";
import "@leetswap/dex/v2/interfaces/ILeetSwapV2Pair.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LeetToken is ERC20, Ownable, ILiquidityManageable {
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address public constant NOTE = 0x4e71A2E537B7f9D9413D3991D37958c0b5e1e503;
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
    uint256 public tradingEnabledTimestamp = 0; // 0 means trading is not active

    uint256 public sniperBuyBaseFee = 2000;
    uint256 public sniperBuyFeeDecayPeriod = 10 minutes;
    uint256 public sniperBuyFeeBurnShare = 2500;
    bool public sniperBuyFeeEnabled = true;

    uint256 public sniperSellBaseFee = 2000;
    uint256 public sniperSellFeeDecayPeriod = 24 hours;
    uint256 public sniperSellFeeBurnShare = 2500;
    bool public sniperSellFeeEnabled = true;

    bool public pairAutoDetectionEnabled;
    bool public indirectSwapFeeEnabled;

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
    error TradingAlreadyEnabled();
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
        farmsBuyFee = 75;
        stakingBuyFee = 25;
        treasuryBuyFee = 0;
        setBuyFees(burnBuyFee, farmsBuyFee, stakingBuyFee, treasuryBuyFee);

        burnSellFee = 0;
        farmsSellFee = 150;
        stakingSellFee = 100;
        treasurySellFee = 50;
        setSellFees(burnSellFee, farmsSellFee, stakingSellFee, treasurySellFee);

        farmsFeeRecipient = owner();
        stakingFeeRecipient = owner();
        treasuryFeeRecipient = owner();

        isLiquidityManager[address(router)] = true;

        address pair = factory.createPair(address(this), router.WETH());
        address notePair = factory.createPair(address(this), NOTE);
        _isLeetPair[pair] = true;
        _isLeetPair[notePair] = true;
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

        if (_pair.code.length == 0) {
            return false;
        }

        ILeetSwapV2Pair pair = ILeetSwapV2Pair(_pair);

        try pair.factory() returns (address factory) {
            if (factory == address(0)) {
                return false;
            }
        } catch {
            return false;
        }

        try pair.token0() returns (address token0) {
            if (token0 == address(this)) {
                return true;
            }
        } catch {
            return false;
        }

        try pair.token1() returns (address token1) {
            if (token1 == address(this)) {
                return true;
            }
        } catch {
            return false;
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

    function sniperBuyFee() public view returns (uint256) {
        if (!sniperBuyFeeEnabled) {
            return 0;
        }

        uint256 timeSinceLaunch = block.timestamp - tradingEnabledTimestamp;

        if (timeSinceLaunch >= sniperBuyFeeDecayPeriod) {
            return 0;
        }

        return
            sniperBuyBaseFee -
            (sniperBuyBaseFee * timeSinceLaunch) /
            sniperBuyFeeDecayPeriod;
    }

    function sniperSellFee() public view returns (uint256) {
        if (!sniperSellFeeEnabled) {
            return 0;
        }

        uint256 timeSinceLaunch = block.timestamp - tradingEnabledTimestamp;

        if (timeSinceLaunch >= sniperSellFeeDecayPeriod) {
            return 0;
        }

        return
            sniperSellBaseFee -
            (sniperSellBaseFee * timeSinceLaunch) /
            sniperSellFeeDecayPeriod;
    }

    /************************************************************************/

    function _takeBuyFee(address sender, uint256 amount)
        public
        returns (uint256)
    {
        if (totalBuyFee == 0) return 0;

        uint256 totalFeeAmount = (amount * totalBuyFee) / FEE_DENOMINATOR;
        uint256 burnFeeAmount = (totalFeeAmount * burnBuyFee) / totalBuyFee;
        uint256 farmsFeeAmount = (totalFeeAmount * farmsBuyFee) / totalBuyFee;
        uint256 stakingFeeAmount = (totalFeeAmount * stakingBuyFee) /
            totalBuyFee;
        uint256 treasuryFeeAmount = totalFeeAmount -
            burnFeeAmount -
            farmsFeeAmount -
            stakingFeeAmount;

        if (burnFeeAmount > 0) super._transfer(sender, DEAD, burnFeeAmount);

        if (farmsFeeAmount > 0)
            super._transfer(sender, farmsFeeRecipient, farmsFeeAmount);

        if (stakingFeeAmount > 0)
            super._transfer(sender, stakingFeeRecipient, stakingFeeAmount);

        if (treasuryFeeAmount > 0)
            super._transfer(sender, treasuryFeeRecipient, treasuryFeeAmount);

        return totalFeeAmount;
    }

    function _takeSellFee(address sender, uint256 amount)
        public
        returns (uint256)
    {
        if (totalSellFee == 0) return 0;

        uint256 totalFeeAmount = (amount * totalSellFee) / FEE_DENOMINATOR;
        uint256 burnFeeAmount = (totalFeeAmount * burnSellFee) / totalSellFee;
        uint256 farmsFeeAmount = (totalFeeAmount * farmsSellFee) / totalSellFee;
        uint256 stakingFeeAmount = (totalFeeAmount * stakingSellFee) /
            totalSellFee;
        uint256 treasuryFeeAmount = totalFeeAmount -
            burnFeeAmount -
            farmsFeeAmount -
            stakingFeeAmount;

        if (burnFeeAmount > 0) super._transfer(sender, DEAD, burnFeeAmount);

        if (farmsFeeAmount > 0)
            super._transfer(sender, farmsFeeRecipient, farmsFeeAmount);

        if (stakingFeeAmount > 0)
            super._transfer(sender, stakingFeeRecipient, stakingFeeAmount);

        if (treasuryFeeAmount > 0)
            super._transfer(sender, treasuryFeeRecipient, treasuryFeeAmount);

        return totalFeeAmount;
    }

    function _takeSniperBuyFee(address sender, uint256 amount)
        public
        returns (uint256)
    {
        uint256 totalFeeAmount = (amount * sniperBuyFee()) / FEE_DENOMINATOR;
        uint256 burnFeeAmount = (totalFeeAmount * sniperBuyFeeBurnShare) /
            FEE_DENOMINATOR;
        uint256 treasuryFeeAmount = totalFeeAmount - burnFeeAmount;

        if (burnFeeAmount > 0) super._transfer(sender, DEAD, burnFeeAmount);

        if (treasuryFeeAmount > 0)
            super._transfer(sender, treasuryFeeRecipient, treasuryFeeAmount);

        return totalFeeAmount;
    }

    function _takeSniperSellFee(address sender, uint256 amount)
        public
        returns (uint256)
    {
        uint256 totalFeeAmount = (amount * sniperSellFee()) / FEE_DENOMINATOR;
        uint256 burnFeeAmount = (totalFeeAmount * sniperSellFeeBurnShare) /
            FEE_DENOMINATOR;
        uint256 treasuryFeeAmount = totalFeeAmount - burnFeeAmount;

        if (burnFeeAmount > 0) super._transfer(sender, DEAD, burnFeeAmount);

        if (treasuryFeeAmount > 0)
            super._transfer(sender, treasuryFeeRecipient, treasuryFeeAmount);

        return totalFeeAmount;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        if (
            !tradingEnabled &&
            !isExcludedFromFee[sender] &&
            !isExcludedFromFee[recipient]
        ) {
            revert TradingNotEnabled();
        }

        bool takeFee = _shouldTakeTransferTax(sender, recipient);
        bool isBuy = isLeetPair(sender);
        bool isSell = isLeetPair(recipient);
        bool isIndirectSwap = isBuy && isSell;
        takeFee = takeFee && (indirectSwapFeeEnabled || !isIndirectSwap);

        uint256 totalFeeAmount;
        if (takeFee) {
            if (isSell) {
                totalFeeAmount = _takeSellFee(sender, amount);
                totalFeeAmount += _takeSniperSellFee(sender, amount);
            } else if (isBuy) {
                totalFeeAmount = _takeBuyFee(sender, amount);
                totalFeeAmount += _takeSniperBuyFee(sender, amount);
            }
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

    function setIndirectSwapFeeEnabled(bool _indirectSwapFeeEnabled)
        public
        onlyOwner
    {
        indirectSwapFeeEnabled = _indirectSwapFeeEnabled;
    }

    function enableTrading() public onlyOwner {
        if (tradingEnabled) revert TradingAlreadyEnabled();
        tradingEnabled = true;
        tradingEnabledTimestamp = block.timestamp;
    }

    function setPairAutoDetectionEnabled(bool _pairAutoDetectionEnabled)
        public
        onlyOwner
    {
        pairAutoDetectionEnabled = _pairAutoDetectionEnabled;
    }

    function setSniperBuyFeeEnabled(bool _sniperBuyFeeEnabled)
        public
        onlyOwner
    {
        sniperBuyFeeEnabled = _sniperBuyFeeEnabled;
    }

    function setSniperSellFeeEnabled(bool _sniperSellFeeEnabled)
        public
        onlyOwner
    {
        sniperSellFeeEnabled = _sniperSellFeeEnabled;
    }
}

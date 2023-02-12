// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./LeetSwapV2Pair.sol";
import "./LeetSwapV2Burnables.sol";
import "./interfaces/ILeetSwapV2Factory.sol";
import "./interfaces/ITradingFeesOracle.sol";
import "./interfaces/ITurnstile.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LeetSwapV2Factory is ILeetSwapV2Factory, Ownable {
    bool public isPaused;
    address public pauser;
    address public pendingPauser;
    ILeetSwapV2Burnables public burnables;
    ITurnstile public turnstile;
    ITradingFeesOracle public tradingFeesOracle;
    uint256 public protocolFeesShare;
    address public protocolFeesRecipient;

    mapping(address => mapping(address => mapping(bool => address)))
        internal _getPair;
    uint256 internal _tradingFees;

    address[] public allPairs;
    mapping(address => bool) public isPair; // simplified check if it's a pair, given that `stable` flag might not be available in peripherals

    address internal _temp0;
    address internal _temp1;
    bool internal _temp;

    event PairCreated(
        address indexed token0,
        address indexed token1,
        bool stable,
        address pair,
        uint256
    );

    constructor(ILeetSwapV2Burnables _burnables, ITurnstile _turnstile) {
        pauser = msg.sender;
        isPaused = false;
        burnables = _burnables;
        turnstile = _turnstile;
        turnstile.register(msg.sender);
        protocolFeesRecipient = msg.sender;
        _tradingFees = 30;
        protocolFeesShare = 0;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function setPauser(address _pauser) external {
        require(msg.sender == pauser);
        pendingPauser = _pauser;
    }

    function acceptPauser() external {
        require(msg.sender == pendingPauser);
        pauser = pendingPauser;
    }

    function setPause(bool _state) external {
        require(msg.sender == pauser);
        isPaused = _state;
    }

    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(LeetSwapV2Pair).creationCode);
    }

    function getInitializable()
        external
        view
        returns (
            address,
            address,
            bool
        )
    {
        return (_temp0, _temp1, _temp);
    }

    function getPair(
        address tokenA,
        address tokenB,
        bool stable
    ) external view override returns (address) {
        return _getPair[tokenA][tokenB][stable];
    }

    // UniswapV2 fallback
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address)
    {
        return _getPair[tokenA][tokenB][false];
    }

    function createPair(
        address tokenA,
        address tokenB,
        bool stable
    ) public returns (address pair) {
        require(tokenA != tokenB, "IA"); // PairFactoryV1: IDENTICAL_ADDRESSES
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "ZA"); // PairFactoryV1: ZERO_ADDRESS
        require(_getPair[token0][token1][stable] == address(0), "PE"); // PairFactoryV1: PAIR_EXISTS - single check is sufficient
        bytes32 salt = keccak256(abi.encodePacked(token0, token1, stable)); // notice salt includes stable as well, 3 parameters
        (_temp0, _temp1, _temp) = (token0, token1, stable);
        pair = address(new LeetSwapV2Pair{salt: salt}());
        _getPair[token0][token1][stable] = pair;
        _getPair[token1][token0][stable] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        isPair[pair] = true;
        emit PairCreated(token0, token1, stable, pair, allPairs.length);
    }

    // UniswapV2 fallback
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair)
    {
        return createPair(tokenA, tokenB, false);
    }

    function tradingFees(address pair, address to)
        external
        view
        returns (uint256 fees)
    {
        if (address(tradingFeesOracle) == address(0)) {
            fees = _tradingFees;
        } else {
            fees = tradingFeesOracle.getTradingFees(pair, to);
        }

        return fees > 100 ? 100 : fees; // max 1% fees
    }

    // **** ADMIN FUNCTIONS ****
    function setTradingFeesOracle(ITradingFeesOracle _tradingFeesOracle)
        external
        onlyOwner
    {
        tradingFeesOracle = _tradingFeesOracle;
    }

    function setProtocolFeesRecipient(address _protocolFeesRecipient)
        external
        onlyOwner
    {
        protocolFeesRecipient = _protocolFeesRecipient;
    }

    function setTradingFees(uint256 _fee) external onlyOwner {
        _tradingFees = _fee;
    }

    function setProtocolFeesShare(uint256 _protocolFeesShare)
        external
        onlyOwner
    {
        protocolFeesShare = _protocolFeesShare > 5000
            ? 5000
            : _protocolFeesShare; // max 50%
    }

    function setTurnstile(address _turnstile) external onlyOwner {
        turnstile = ITurnstile(_turnstile);
    }
}

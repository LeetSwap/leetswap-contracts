// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./LeetSwapV2Pair.sol";
import "./LeetSwapV2Burnables.sol";
import "./interfaces/ILeetSwapV2Factory.sol";
import "./interfaces/ITurnstile.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LeetSwapV2Factory is ILeetSwapV2Factory, Ownable {
    bool public isPaused;
    address public pauser;
    address public pendingPauser;
    ILeetSwapV2Burnables public burnables;
    ITurnstile public turnstile;

    mapping(address => mapping(address => mapping(bool => address)))
        internal _getPair;

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

    constructor(
        ILeetSwapV2Burnables _burnables,
        ITurnstile _turnstile,
        uint256 _csrTokenID
    ) {
        pauser = msg.sender;
        isPaused = false;
        burnables = _burnables;
        turnstile = _turnstile;
        turnstile.assign(_csrTokenID);
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
    ) external returns (address pair) {
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

    // **** CSR FUNCTIONS ****
    function setTurnstile(address _turnstile) external onlyOwner {
        turnstile = ITurnstile(_turnstile);
    }
}

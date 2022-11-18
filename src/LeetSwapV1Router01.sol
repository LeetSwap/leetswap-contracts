// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "./interfaces/IWCANTO.sol";
import "./interfaces/IBaseV1Factory.sol";
import "./interfaces/IBaseV1Pair.sol";
import "./BaseV1-libs.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LeetSwapV1Router01 is Ownable {
    struct Route {
        address from;
        address to;
        bool stable;
    }

    address public immutable factory;
    IWCANTO public immutable wcanto;
    uint256 internal constant MINIMUM_LIQUIDITY = 10**3;
    bytes32 immutable pairCodeHash;
    mapping(address => bool) public stablePairs;

    error TradeExpired();
    error InsufficientOutputAmount();
    error InvalidPath();
    error CantoTransferFailed();
    error IdenticalAddresses();
    error InsufficientAmount();
    error InsufficientAAmount();
    error InsufficientBAmount();
    error InsufficientLiquidity();
    error ZeroAddress();
    error DeadlineExpired();
    error ArrayLengthMismatch();
    error Unauthorized();

    modifier ensure(uint256 deadline) {
        if (deadline < block.timestamp) revert DeadlineExpired();
        _;
    }

    constructor(address _factory, address _wcanto) {
        factory = _factory;
        pairCodeHash = IBaseV1Factory(_factory).pairCodeHash();
        wcanto = IWCANTO(_wcanto);
    }

    receive() external payable {
        assert(msg.sender == address(wcanto)); // only accept ETH via fallback from the wcanto contract
    }

    function sortTokens(address tokenA, address tokenB)
        public
        pure
        returns (address token0, address token1)
    {
        if (tokenA == tokenB) revert IdenticalAddresses();
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        if (token0 == address(0)) revert ZeroAddress();
    }

    function _pairFor(
        address tokenA,
        address tokenB,
        bool stable
    ) internal view returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encodePacked(token0, token1, stable)),
                            pairCodeHash // init code hash
                        )
                    )
                )
            )
        );
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address tokenA, address tokenB)
        public
        view
        returns (address pair)
    {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        bool isStable = stablePairs[_pairFor(token0, token1, true)];
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(
                                abi.encodePacked(token0, token1, isStable)
                            ),
                            pairCodeHash // init code hash
                        )
                    )
                )
            )
        );
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address tokenA, address tokenB)
        public
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0, ) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1, ) = IBaseV1Pair(
            pairFor(tokenA, tokenB)
        ).getReserves();
        (reserveA, reserveB) = tokenA == token0
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountOut(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) public view returns (uint256 amount) {
        address pair = pairFor(tokenIn, tokenOut);
        if (IBaseV1Factory(factory).isPair(pair)) {
            amount = IBaseV1Pair(pair).getAmountOut(amountIn, tokenIn);
        }
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(uint256 amountIn, Route[] memory routes)
        public
        view
        returns (uint256[] memory amounts)
    {
        if (routes.length < 1) revert InvalidPath();
        amounts = new uint256[](routes.length + 1);
        amounts[0] = amountIn;
        for (uint256 i = 0; i < routes.length; i++) {
            address pair = pairFor(routes[i].from, routes[i].to);
            if (IBaseV1Factory(factory).isPair(pair)) {
                amounts[i + 1] = IBaseV1Pair(pair).getAmountOut(
                    amounts[i],
                    routes[i].from
                );
            }
        }
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quoteLiquidity(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        if (amountA <= 0) revert InsufficientAmount();
        if (reserveA <= 0 || reserveB <= 0) revert InsufficientLiquidity();
        amountB = (amountA * reserveB) / reserveA;
    }

    function isPair(address pair) public view returns (bool) {
        return IBaseV1Factory(factory).isPair(pair);
    }

    function _pathToRoutes(address[] calldata path)
        internal
        view
        returns (Route[] memory routes)
    {
        routes = new Route[](path.length - 1);
        for (uint256 i = 0; i < path.length - 1; i++) {
            bool isStable = stablePairs[pairFor(path[i], path[i + 1])];
            routes[i] = Route(path[i], path[i + 1], isStable);
        }
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(
        uint256[] memory amounts,
        Route[] memory routes,
        address _to
    ) internal virtual {
        for (uint256 i = 0; i < routes.length; i++) {
            (address token0, ) = sortTokens(routes[i].from, routes[i].to);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = routes[i].from == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < routes.length - 1
                ? pairFor(routes[i + 1].from, routes[i + 1].to)
                : _to;
            IBaseV1Pair(pairFor(routes[i].from, routes[i].to)).swap(
                amount0Out,
                amount1Out,
                to,
                new bytes(0)
            );
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        Route[] memory routes = _pathToRoutes(path);
        amounts = getAmountsOut(amountIn, routes);
        if (amounts[amounts.length - 1] < amountOutMin) {
            revert InsufficientOutputAmount();
        }
        _safeTransferFrom(
            routes[0].from,
            msg.sender,
            pairFor(routes[0].from, routes[0].to),
            amounts[0]
        );
        _swap(amounts, routes, to);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256[] memory amounts) {
        if (path[0] != address(wcanto)) revert InvalidPath();
        Route[] memory routes = _pathToRoutes(path);
        amounts = getAmountsOut(msg.value, routes);
        if (amounts[amounts.length - 1] < amountOutMin) {
            revert InsufficientOutputAmount();
        }
        wcanto.deposit{value: amounts[0]}();
        assert(
            wcanto.transfer(pairFor(routes[0].from, routes[0].to), amounts[0])
        );
        _swap(amounts, routes, to);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        if (path[path.length - 1] != address(wcanto)) {
            revert InvalidPath();
        }
        Route[] memory routes = _pathToRoutes(path);
        amounts = getAmountsOut(amountIn, routes);
        if (amounts[amounts.length - 1] < amountOutMin) {
            revert InsufficientOutputAmount();
        }
        _safeTransferFrom(
            routes[0].from,
            msg.sender,
            pairFor(routes[0].from, routes[0].to),
            amounts[0]
        );
        _swap(amounts, routes, address(this));
        wcanto.withdraw(amounts[amounts.length - 1]);
        _safeTransferETH(to, amounts[amounts.length - 1]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(
        address[] memory path,
        address _to
    ) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = sortTokens(input, output);
            IBaseV1Pair pair = IBaseV1Pair(pairFor(input, output));
            uint256 amountInput;
            uint256 amountOutput;
            {
                // scope to avoid stack too deep errors
                (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) = input == token0
                    ? (reserve0, reserve1)
                    : (reserve1, reserve0);
                amountInput =
                    IERC20(input).balanceOf(address(pair)) -
                    reserveInput;
                amountOutput = getAmountOut(amountInput, input, output);
            }
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOutput)
                : (amountOutput, uint256(0));
            address to;
            if (i < path.length - 2) {
                to = pairFor(output, path[i + 2]);
            } else {
                to = _to;
            }
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual ensure(deadline) {
        _safeTransferFrom(
            path[0],
            msg.sender,
            pairFor(path[0], path[1]),
            amountIn
        );
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        if (
            IERC20(path[path.length - 1]).balanceOf(to) - balanceBefore <
            amountOutMin
        ) {
            revert InsufficientOutputAmount();
        }
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual ensure(deadline) {
        if (path[0] != address(wcanto)) revert InvalidPath();
        uint256 amountIn = msg.value;
        IWCANTO(wcanto).deposit{value: amountIn}();
        assert(IWCANTO(wcanto).transfer(pairFor(path[0], path[1]), amountIn));
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        if (
            IERC20(path[path.length - 1]).balanceOf(to) - balanceBefore <
            amountOutMin
        ) {
            revert InsufficientOutputAmount();
        }
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual ensure(deadline) {
        if (path[path.length - 1] != address(wcanto)) {
            revert InvalidPath();
        }
        _safeTransferFrom(
            path[0],
            msg.sender,
            pairFor(path[0], path[1]),
            amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20(address(wcanto)).balanceOf(address(this));
        if (amountOut < amountOutMin) {
            revert InsufficientOutputAmount();
        }
        IWCANTO(wcanto).withdraw(amountOut);
        _safeTransferETH(to, amountOut);
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        require(amountADesired >= amountAMin);
        require(amountBDesired >= amountBMin);
        // create the pair if it doesn"t exist yet
        address _pair = IBaseV1Factory(factory).getPair(tokenA, tokenB, stable);
        if (_pair == address(0)) {
            _pair = IBaseV1Factory(factory).createPair(tokenA, tokenB, stable);
        }
        (uint256 reserveA, uint256 reserveB) = getReserves(tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = quoteLiquidity(
                amountADesired,
                reserveA,
                reserveB
            );
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) {
                    revert InsufficientBAmount();
                }
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = quoteLiquidity(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                assert(amountAOptimal <= amountADesired);
                if (amountAOptimal < amountAMin) {
                    revert InsufficientAAmount();
                }
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        ensure(deadline)
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        address pair = pairFor(tokenA, tokenB);
        bool isStable = stablePairs[pair];
        (amountA, amountB) = _addLiquidity(
            tokenA,
            tokenB,
            isStable,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );
        _safeTransferFrom(tokenA, msg.sender, pair, amountA);
        _safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IBaseV1Pair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountCANTOMin,
        address to,
        uint256 deadline
    )
        external
        payable
        ensure(deadline)
        returns (
            uint256 amountToken,
            uint256 amountCANTO,
            uint256 liquidity
        )
    {
        address pair = pairFor(token, address(wcanto));
        bool isStable = stablePairs[pair];
        (amountToken, amountCANTO) = _addLiquidity(
            token,
            address(wcanto),
            isStable,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountCANTOMin
        );
        _safeTransferFrom(token, msg.sender, pair, amountToken);
        wcanto.deposit{value: amountCANTO}();
        assert(wcanto.transfer(pair, amountCANTO));
        liquidity = IBaseV1Pair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountCANTO) {
            _safeTransferETH(msg.sender, msg.value - amountCANTO);
        }
    }

    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        if (!success) revert CantoTransferFailed();
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = pairFor(tokenA, tokenB);
        require(IBaseV1Pair(pair).transferFrom(msg.sender, pair, liquidity)); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = IBaseV1Pair(pair).burn(to);
        (address token0, ) = sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0
            ? (amount0, amount1)
            : (amount1, amount0);
        if (amountA < amountAMin) {
            revert InsufficientAAmount();
        }
        if (amountB < amountBMin) {
            revert InsufficientBAmount();
        }
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountCANTOMin,
        address to,
        uint256 deadline
    )
        public
        ensure(deadline)
        returns (uint256 amountToken, uint256 amountCANTO)
    {
        (amountToken, amountCANTO) = removeLiquidity(
            token,
            address(wcanto),
            liquidity,
            amountTokenMin,
            amountCANTOMin,
            address(this),
            deadline
        );
        _safeTransfer(token, to, amountToken);
        wcanto.withdraw(amountCANTO);
        _safeTransferETH(to, amountCANTO);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountCANTOMin,
        address to,
        uint256 deadline
    ) public virtual ensure(deadline) returns (uint256 amountCANTO) {
        (, amountCANTO) = removeLiquidity(
            token,
            address(wcanto),
            liquidity,
            amountTokenMin,
            amountCANTOMin,
            address(this),
            deadline
        );
        _safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        wcanto.withdraw(amountCANTO);
        _safeTransferETH(to, amountCANTO);
    }

    // **** LIBRARY FUNCTIONS ****
    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool)) == true)
        );
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        IERC20 tokenCon = IERC20(token);
        bool success = tokenCon.transferFrom(from, to, value);
        require(success);
    }

    function setStablePair(address pair, bool stable) external onlyOwner {
        stablePairs[pair] = stable;
    }

    function setStablePairs(address[] calldata pairs, bool[] calldata stable)
        external
        onlyOwner
    {
        if (pairs.length != stable.length) revert ArrayLengthMismatch();
        for (uint256 i = 0; i < pairs.length; i++) {
            stablePairs[pairs[i]] = stable[i];
        }
    }
}

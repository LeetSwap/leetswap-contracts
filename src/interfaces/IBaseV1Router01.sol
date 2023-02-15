// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "./IWCANTO.sol";

interface IBaseV1Router01 {
    struct route {
        address from;
        address to;
        bool stable;
    }

    function factory() external view returns (address);

    function wcanto() external view returns (IWCANTO);

    function note() external view returns (address);

    function Comptroller() external view returns (address);

    function sortTokens(address tokenA, address tokenB)
        external
        pure
        returns (address token0, address token1);

    function pairFor(
        address tokenA,
        address tokenB,
        bool stable
    ) external view returns (address pair);

    function getReserves(
        address tokenA,
        address tokenB,
        bool stable
    ) external view returns (uint256 reserveA, uint256 reserveB);

    function getAmountOut(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) external view returns (uint256 amount, bool stable);

    function getAmountsOut(uint256 amountIn, route[] memory routes)
        external
        view
        returns (uint256[] memory amounts);

    function isPair(address pair) external view returns (bool);

    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function addLiquidityCANTO(
        address token,
        bool stable,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountCANTOMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountCANTO,
            uint256 liquidity
        );

    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityCANTO(
        address token,
        bool stable,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountCANTOMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountCANTO);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactCANTOForTokens(
        uint256 amountOutMin,
        route[] calldata routes,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactTokensForCANTO(
        uint256 amountIn,
        uint256 amountOutMin,
        route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

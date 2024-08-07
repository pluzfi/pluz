// SPDX-License-Identifier: MIT
// ftm.guru's extension of Solidly's periphery (Router)
// https://github.com/andrecronje/solidly/blob/master/contracts/BaseV1-periphery.sol
// BaseV1Router02.sol : Supporting Fee-on-transfer Tokens
// https://github.com/ftm1337/solidly-with-FoT/blob/master/contracts/BaseV1-periphery.sol

pragma solidity 0.8.24;

// Experimental Extension [ftm.guru/solidly/BaseV1Router02]
// contract BaseV1Router02 is BaseV1Router01
// with Support for Fee-on-Transfer Tokens
interface ILynexRouterV2 {

    struct route {
        address from;
        address to;
        bool stable;
    }


    function getAmountOut(uint amountIn, address tokenIn, address tokenOut) external view returns (uint amount, bool stable);

    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

}

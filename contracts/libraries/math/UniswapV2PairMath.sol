// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "../../solady/src/tokens/ERC20.sol";
import "../../external/uniswap/interfaces/IUniswapV2Pair.sol";
import { UD60x18, sqrt, mul } from "@prb/math/src/UD60x18.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./MathUtils.sol";
import "../../interfaces/IAssetPriceProvider.sol";
import "../Errors.sol";

/// @title Uniswap V2 Pair Math
library UniswapV2PairMath {
    using MathUtils for uint256;
    using MathUtils for UD60x18;

    struct PairProps {
        SingleSideProps reserveA;
        SingleSideProps reserveB;
        uint256 totalSupply;
        uint8 lpTokenDecimals;
        /// @dev Prices are denominated in base asset so everything has to
        /// be scaled to 18 decimals and converted back to this at the end.
        uint8 baseAssetDecimals;
    }

    struct SingleSideProps {
        uint256 reserve;
        uint256 price;
        uint8 decimals;
    }

    struct ScaledSingleSide {
        UD60x18 reserve;
        UD60x18 price;
    }

    /// @dev Taken from https://github.com/Uniswap/v2-periphery/blob/master/contracts/UniswapV2Router02.sol#L49
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        require(amountA > 0, "UniswapV2Library: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        amountB = (amountA * (reserveB)) / reserveA;
    }

    function addLiquidity(
        IUniswapV2Pair pair,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired
    )
        internal
        view
        returns (uint256 amountA, uint256 amountB, uint256 reserveA, uint256 reserveB)
    {
        (reserveA, reserveB,) = pair.getReserves();
        (reserveA, reserveB) = address(tokenA) < address(tokenB) ? (reserveA, reserveB) : (reserveB, reserveA);

        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = UniswapV2PairMath.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = UniswapV2PairMath.quote(amountBDesired, reserveB, reserveA);
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function getIdealLiquidity(
        IUniswapV2Pair pair,
        address tokenA,
        address tokenB,
        uint256 amountADesired
    )
        internal
        view
        returns (uint256 amountAOptimal, uint256 amountBOptimal, uint256 reserveA, uint256 reserveB)
    {
        (reserveA, reserveB,) = pair.getReserves();
        (reserveA, reserveB) = address(tokenA) < address(tokenB) ? (reserveA, reserveB) : (reserveB, reserveA);
        amountBOptimal = UniswapV2PairMath.quote(amountADesired, reserveA, reserveB);
        amountAOptimal = amountADesired;
    }

    function fetchPairProps(
        IUniswapV2Pair pair,
        IAssetPriceProvider provider,
        uint8 baseAssetDecimals
    )
        internal
        view
        returns (PairProps memory)
    {
        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();
        (address token0, address token1) = (pair.token0(), pair.token1());

        uint256 _totalSupply = pair.totalSupply();
        uint8 _lpTokenDecimals = IERC20Metadata(address(pair)).decimals();
        return PairProps({
            reserveA: SingleSideProps({
                reserve: reserveA,
                price: provider.getAssetPrice(token0),
                decimals: IERC20Metadata(token0).decimals()
            }),
            reserveB: SingleSideProps({
                reserve: reserveB,
                price: provider.getAssetPrice(token1),
                decimals: IERC20Metadata(token1).decimals()
            }),
            totalSupply: _totalSupply,
            lpTokenDecimals: _lpTokenDecimals,
            baseAssetDecimals: baseAssetDecimals
        });
    }

    function scaleSingleSide(
        SingleSideProps memory props,
        uint8 priceDecimals
    )
        internal
        pure
        returns (ScaledSingleSide memory)
    {
        return ScaledSingleSide({
            reserve: props.reserve.fromTokenDecimals(props.decimals),
            price: props.price.fromTokenDecimals(priceDecimals)
        });
    }

    /// Calculates the price of an LP token based on https://blog.alphafinance.io/fair-lp-token-pricing/.
    function getFairPrice(PairProps memory props) internal pure returns (uint256 price) {
        ScaledSingleSide memory a = scaleSingleSide(props.reserveA, props.baseAssetDecimals);
        ScaledSingleSide memory b = scaleSingleSide(props.reserveB, props.baseAssetDecimals);
        UD60x18 scaledTotalSupply = props.totalSupply.fromTokenDecimals(props.lpTokenDecimals);

        UD60x18 r = sqrt(a.reserve * b.reserve);
        UD60x18 p = sqrt(a.price * b.price);
        UD60x18 rp2 = ((r * p * ud(2e18)) / scaledTotalSupply);
        return rp2.toTokenDecimals(props.baseAssetDecimals);
    }
}

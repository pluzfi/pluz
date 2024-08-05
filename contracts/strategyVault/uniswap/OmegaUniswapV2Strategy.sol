// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../StrategyVault.sol";
import "../../external/uniswap/interfaces/IUniswapV2Factory.sol";
import "../../external/uniswap/interfaces/IUniswapV2Pair.sol";
import "../../external/uniswap/interfaces/ILynexRouterV2.sol";
import "../../libraries/math/UniswapV2PairMath.sol";
import "../../periphery/UniswapV3Swapper.sol";

contract OmegaUniswapV2Strategy is StrategyVault, UniswapV3SwapZapper {
    using SafeERC20 for IERC20;

    struct InitParams {
        string name;
        string symbol;
        address tokenA;
        address tokenB;
        address factory;
        address liquidityRouter;
        address swapRouter;
        bytes inPath;
        bytes outPath;
    }

    IERC20 public immutable tokenB;
    IUniswapV2Factory public immutable factory;
    IUniswapV2Pair public immutable pair;

    /// @dev Router used for providing liquidity.
    ILynexRouterV2 public immutable liquidityRouter;
    uint256 private MIN_RANGE_BPS_A = 9920;
    uint256 private MIN_RANGE_BPS_B = 9950;
    // Calculate minSwap considering 2.25% slippage tolerance
    uint256 slippageTolerance = 225; // 2.25% as 225 bps

    constructor(
        address protocolGovernor_,
        VaultParams memory vaultParams_,
        InitParams memory params
    )
        StrategyVault(
            BaseInitParams({
                protocolGovernor: protocolGovernor_,
                vaultName: params.name,
                vaultSymbol: params.symbol,
                baseAsset: params.tokenA
            }),
            vaultParams_
        )
        UniswapV3SwapZapper(params.swapRouter, params.inPath, params.outPath)
    {
        tokenB = IERC20(params.tokenB);
        liquidityRouter = ILynexRouterV2(params.liquidityRouter);
        factory = IUniswapV2Factory(params.factory);
        pair = IUniswapV2Pair(factory.getPair(address(_baseAsset), address(tokenB)));

        require(address(pair) != address(0), "UniswapV2: The requested pair is not available");
    }

    function updatePaths(bytes memory inPath_, bytes memory outPath_) external onlyOwner {
        _updatePaths(inPath_, outPath_);
    }

    function setMinRangeBps(uint256 min_range_bps_a, uint256 min_range_bps_b) external onlyOwner {
        MIN_RANGE_BPS_A = min_range_bps_a;
        MIN_RANGE_BPS_B = min_range_bps_b;
    }

    function previewDeposit(uint256 assets) public view override returns (uint256 shares) {
        uint256 fee = (ud(assets) * _vaultParams.depositFee).unwrap();
        assets = assets - fee;

        uint256 amountADesired = assets / 2;

        // if you could perfectly swap half of the baseAsset for tokenB and Add Liquidity
        (uint256 amountA, uint256 amountB, uint256 reserve0, uint256 reserve1) =
            UniswapV2PairMath.getIdealLiquidity(pair, address(_baseAsset), address(tokenB), amountADesired);

        uint256 _totalSupply = pair.totalSupply();
        shares = ((amountA * _totalSupply) / reserve0 < (amountB * _totalSupply) / reserve1)
            ? (amountA * _totalSupply) / reserve0
            : (amountB * _totalSupply) / reserve1;

        return shares;
    }

    function previewWithdraw(uint256 shares) public view override returns (uint256 assets) {
        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();
        (uint256 reserve0,) = address(_baseAsset) < address(tokenB) ? (reserveA, reserveB) : (reserveB, reserveA);
        uint256 _totalSupply = pair.totalSupply();
        uint256 amount0 = (shares * reserve0) / _totalSupply;
        assets = amount0 * 2;
        return assets;
    }

    function _deposit(
        uint256 assets,
        bytes memory data,
        address recipient
    )
        internal
        virtual
        override
        returns (uint256 receivedShares)
    {
        uint256 halfAssets = (assets) / 2;

        // get tokenB amount
        (uint256 tokenBOutputQuote, bool stable) = liquidityRouter.getAmountOut(halfAssets, address(_baseAsset), address(tokenB));
        uint256 minSwap = tokenBOutputQuote * (10000 - slippageTolerance) / 10000;
        uint256 amountTokenB = _uniswapV3SwapIn(_baseAsset, tokenB, halfAssets, tokenBOutputQuote, minSwap);
        uint256 amountBaseAsset = _baseAsset.balanceOf(address(this));

        _baseAsset.approve(address(liquidityRouter), amountBaseAsset);
        tokenB.approve(address(liquidityRouter), amountTokenB);

        // Add liquidity using RouterV2
        (,, uint256 liquidity) = liquidityRouter.addLiquidity(
            address(_baseAsset),
            address(tokenB),
            stable,
            amountBaseAsset,
            amountTokenB,
            amountBaseAsset * MIN_RANGE_BPS_A / 10_000, // amountAMin price range
            amountTokenB * MIN_RANGE_BPS_B / 10_000, // amountBMin price range
            address(this),
            block.timestamp // deadline
        );

        // Refund any remaining tokens that were left over after LP provision.
        uint256 remainingTokenB = tokenB.balanceOf(address(this));
        if (remainingTokenB > 0) {
            tokenB.approve(address(liquidityRouter), remainingTokenB);
            // slither-disable-next-line unused-return
            // get _baseAsset amount
            (uint256 baseAssetOutputQuote, bool isStable) = liquidityRouter.getAmountOut(remainingTokenB, address(tokenB), address(_baseAsset));
            _uniswapV3SwapOut(tokenB, _baseAsset, remainingTokenB, baseAssetOutputQuote, 0);
        }
        _baseAsset.safeTransfer(recipient, _baseAsset.balanceOf(address(this)));

        receivedShares = liquidity;
        _mint(recipient, liquidity);
    }

    function _withdraw(
        address caller,
        uint256 shares,
        bytes memory data,
        address recipient
    )
        internal
        virtual
        override
        returns (uint256 receivedAssets)
    {
        receivedAssets = _removeLiquidity(caller, shares, data, recipient);
    }

    function _removeLiquidity(
        address caller,
        uint256 shares,
        bytes memory data,
        address recipient
    )
        internal
        returns (uint256 receivedAssets)
    {
        (uint256 minAssets, bool stable) = abi.decode(data, (uint256, bool));


        _burn(caller, shares);
        pair.approve(address(liquidityRouter), shares);

        (uint256 amountA, uint256 amountB) = liquidityRouter.removeLiquidity(
            address(_baseAsset),
            address(tokenB),
            stable,
            shares, // liquidity
            0,
            0,
            address(this),
            block.timestamp // deadline
        );

        (uint256 baseAssetOutputQuote, bool isStable) = liquidityRouter.getAmountOut(amountB, address(tokenB), address(_baseAsset));
        uint256 _baseAssetsReceived = _uniswapV3SwapOut(tokenB, _baseAsset, amountB, baseAssetOutputQuote, 0);
        receivedAssets = amountA + _baseAssetsReceived;

        require(receivedAssets >= minAssets, "UniswapV2StrategyVault: Received less than minAssets");
        // Transfer out everything, but only count the assets from the swap as explicitly received.
        _baseAsset.safeTransfer(recipient, _baseAsset.balanceOf(address(this)));
    }

    function getPositionValue(address account) public view virtual override returns (uint256 value) {
        uint256 totalShares = balanceOf(account);

        value = 0;

        if (totalShares > 0) {
            uint8 _baseDecimals = IERC20Metadata(address(_baseAsset)).decimals();
            UniswapV2PairMath.PairProps memory props =
                UniswapV2PairMath.fetchPairProps(pair, _getPriceProvider(), _baseDecimals);
            // Treat as fixed point math to inherently cancel out the decimals.
            value = ud(UniswapV2PairMath.getFairPrice(props)).mul(ud(totalShares)).unwrap();
        }
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../StrategyVault.sol";
import "../../external/uniswap/interfaces/IUniProxy.sol";
import "../../external/uniswap/interfaces/IHypervisor.sol";
import "../../libraries/math/UniswapV2PairMath.sol";
import "../../periphery/UniswapV3Swapper.sol";

contract GammaNarrowUniswapV3Strategy is StrategyVault, UniswapV3SwapZapper {
    using SafeERC20 for IERC20;

    struct InitParams {
        string name;
        string symbol;
        address tokenA;
        address tokenB;
        address uniProxy;
        address liquidityRouter;
        address pair;
        address swapRouter;
        bytes inPath;
        bytes outPath;
    }

    IERC20 public immutable tokenB;
    IUniProxy public immutable uniProxy;
    IHypervisor public immutable pair;

    /// @dev Router used for providing liquidity.
    IHypervisor public immutable liquidityRouter;
    uint256 private MIN_RANGE_BPS_A = 9920;
    uint256 private MIN_RANGE_BPS_B = 9950;

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
        liquidityRouter = IHypervisor(params.liquidityRouter);
        uniProxy = IUniProxy(params.uniProxy);
        pair = IHypervisor(params.pair);

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
        // TODO
        // uint256 fee = (ud(assets) * _vaultParams.depositFee).unwrap();
        // assets = assets - fee;

        // uint256 amountADesired = assets / 2;

        // // if you could perfectly swap half of the baseAsset for tokenB and Add Liquidity
        // (uint256 amountA, uint256 amountB, uint256 reserve0, uint256 reserve1) =
        //     UniswapV2PairMath.getIdealLiquidity(pair, address(_baseAsset), address(tokenB), amountADesired);

        // uint256 _totalSupply = pair.totalSupply();
        // shares = ((amountA * _totalSupply) / reserve0 < (amountB * _totalSupply) / reserve1)
        //     ? (amountA * _totalSupply) / reserve0
        //     : (amountB * _totalSupply) / reserve1;

        // return shares;
        return 0;
    }

    function previewWithdraw(uint256 shares) public view override returns (uint256 assets) {
        // TODO
        // (uint256 reserveA, uint256 reserveB,) = pair.getReserves();
        // (uint256 reserve0,) = address(_baseAsset) < address(tokenB) ? (reserveA, reserveB) : (reserveB, reserveA);
        // uint256 _totalSupply = pair.totalSupply();
        // uint256 amount0 = (shares * reserve0) / _totalSupply;
        // assets = amount0 * 2;
        // return assets;
        return 0;
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
        // (uint256 minSwap) = abi.decode(data, (uint256));

        uint256 baseAssetToTokenBRatio = _getBaseAssetToTokenBRatio();

        (uint256 baseAsset, uint256 baseAssetForTokenB, uint256 baseAssetRemaining) = _splitAssets(assets, baseAssetToTokenBRatio);

        uint256 minSwap = baseAssetForTokenB * MIN_RANGE_BPS_B / 10_000;
        uint256 amountTokenB = _uniswapV3SwapIn(_baseAsset, baseAssetForTokenB, minSwap);
        uint256 amountBaseAsset = _baseAsset.balanceOf(address(this)) - baseAssetRemaining;

        _baseAsset.approve(address(liquidityRouter), amountBaseAsset);
        tokenB.approve(address(liquidityRouter), amountTokenB);

        // Add liquidity
        uint256[4] memory minIn = [uint256(0), uint256(0), uint256(0), uint256(0)];
        (uint256 shares) = uniProxy.deposit(
            amountBaseAsset,
            amountTokenB,
            address(this),
            address(pair),
            minIn
        );

        // Refund any remaining tokens that were left over after LP provision.
        uint256 remainingTokenB = tokenB.balanceOf(address(this));
        if (remainingTokenB > 0) {
            tokenB.approve(address(liquidityRouter), remainingTokenB);
            // slither-disable-next-line unused-return
            _uniswapV3SwapOut(tokenB, remainingTokenB, 0);
        }
        _baseAsset.safeTransfer(recipient, _baseAsset.balanceOf(address(this)));

        receivedShares = shares;
        _mint(recipient, shares);
    }

    function _getBaseAssetToTokenBRatio() internal view returns (uint256) {
        (uint256 minWETHAmount, uint256 maxWETHAmount) = uniProxy.getDepositAmount(
            address(pair),
            address(_baseAsset),
            10000
        );
        uint256 targetTokenBAmount = (minWETHAmount + (maxWETHAmount - minWETHAmount) / 2) / 10**12;

        uint256 tokenBPrice = _getPriceProvider().getAssetPrice(address(tokenB));
        uint256 targetTokenBValueInBaseAsset = targetTokenBAmount * tokenBPrice / IERC20Metadata(address(tokenB)).decimals();

        // baseAsset:tokenB=1:?
        uint256 baseAssetToTokenBRatio = targetTokenBValueInBaseAsset / 10000;
        return baseAssetToTokenBRatio;
    }

    function _splitAssets(uint256 assets, uint256 baseAssetToTokenBRatio)
        internal
        pure
        returns (uint256 baseAsset, uint256 baseAssetForTokenB, uint256 baseAssetRemaining)
    {
        baseAsset = assets / (1 + baseAssetToTokenBRatio);
        baseAssetForTokenB = (assets * baseAssetToTokenBRatio) / (1 + baseAssetToTokenBRatio);
        baseAssetRemaining = assets - (baseAsset + baseAssetForTokenB);
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
        uint256 minAssets = abi.decode(data, (uint256));

        _burn(caller, shares);
        pair.approve(address(liquidityRouter), shares);

        uint256[4] memory minAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
        (uint256 amountA, uint256 amountB) = liquidityRouter.withdraw(
            shares, // liquidity
            address(this),
            address(this),
            minAmounts
        );

        uint256 _baseAssetsReceived = _uniswapV3SwapOut(tokenB, amountB, 0);
        receivedAssets = amountA + _baseAssetsReceived;

        require(receivedAssets >= minAssets, "UniswapV2StrategyVault: Received less than minAssets");
        // Transfer out everything, but only count the assets from the swap as explicitly received.
        _baseAsset.safeTransfer(recipient, _baseAsset.balanceOf(address(this)));
    }

    function getPositionValue(address account) public view virtual override returns (uint256 value) {
        uint256 totalShares = balanceOf(account);

        value = 0;

        if (totalShares > 0) {
            // TODO
            // uint8 _baseDecimals = IERC20Metadata(address(_baseAsset)).decimals();
            // UniswapV2PairMath.PairProps memory props =
            //     UniswapV2PairMath.fetchPairProps(pair, _getPriceProvider(), _baseDecimals);
            // // Treat as fixed point math to inherently cancel out the decimals.
            // value = ud(UniswapV2PairMath.getFairPrice(props)).mul(ud(totalShares)).unwrap();
        }
    }
}

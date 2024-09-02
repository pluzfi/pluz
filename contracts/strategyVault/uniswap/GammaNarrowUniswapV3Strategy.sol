// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../StrategyVault.sol";
import "../../interfaces/IStakingToken.sol";
import "../../interfaces/IRewardTracker.sol";
import "../../interfaces/IRewardDistributor.sol";
import "../../external/uniswap/interfaces/IGammaUniProxy.sol";
import "../../external/uniswap/interfaces/IHypervisor.sol";
import "../../external/uniswap/interfaces/IAlgebraFactory.sol";
import "../../external/uniswap/interfaces/algebra/IAlgebraPool.sol";
import "../../libraries/math/UniswapV2PairMath.sol";
import "../../periphery/UniswapV3Swapper.sol";
import "../../libraries/math/FullMath.sol";

contract GammaNarrowUniswapV3Strategy is StrategyVault, UniswapV3SwapZapper {
    using SafeERC20 for IERC20;

    struct InitParams {
        string name;
        string symbol;
        address tokenA;
        address tokenB;
        address factory;
        address gammaUniProxy;
        address gamma;
        address swapRouter;
        address stakingToken;
        address rewardToken;
        address rewardTracker;
        address treasury;
        uint256 treasuryRate;
        bytes inPath;
        bytes outPath;
    }

    struct PositionAmounts {
        uint256 totalAmount0;
        uint256 totalAmount1;
    }

    IERC20 public immutable tokenB;
    IAlgebraFactory public immutable factory;
    IAlgebraPool public immutable pool;
    IGammaUniProxy public immutable gammaUniProxy;
    IHypervisor public immutable gamma;
    IStakingToken public stakingToken; 
    IERC20 public rewardToken;
    IRewardTracker public rewardTracker;
    IRewardDistributor public rewardDistributor;
    address public treasury;
    uint256 public treasuryRate;

    uint256 private TOKEN_SCALE_FACTOR = 1000000;
    uint256 public constant PRECISION_18 = 1e18;
    uint256 public constant PRECISION_36 = 1e36;
    uint8 private token0Decimal;
    uint8 private token1Decimal;

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
        factory = IAlgebraFactory(params.factory);
        pool = IAlgebraPool(factory.poolByPair(address(_baseAsset), address(tokenB)));
        gammaUniProxy = IGammaUniProxy(params.gammaUniProxy);
        gamma = IHypervisor(params.gamma);
        stakingToken = IStakingToken(params.stakingToken);
        rewardToken = IERC20(params.rewardToken);
        rewardTracker = IRewardTracker(params.rewardTracker);
        treasury = params.treasury;
        treasuryRate = params.treasuryRate;
        token0Decimal = IERC20Metadata(address(_baseAsset)).decimals();
        token1Decimal = IERC20Metadata(address(tokenB)).decimals();

        require(address(gamma) != address(0), "UniswapV3: The requested gamma is not available");
    }

    function updatePaths(bytes memory inPath_, bytes memory outPath_) external onlyOwner {
        _updatePaths(inPath_, outPath_);
    }

    function updateRewardsTracker(address _rewardTracker) external onlyOwner {
        rewardTracker = IRewardTracker(_rewardTracker);
        rewardDistributor = IRewardDistributor(rewardTracker.getRewardDistributor());
    }

    function setTokenScaleFactor(uint256 newTokenScaleFactor) external onlyOwner {
        TOKEN_SCALE_FACTOR = newTokenScaleFactor;
    }

    function previewDeposit(uint256 assets) public view override returns (uint256 shares) {
        uint256 fee = (ud(assets) * _vaultParams.depositFee).unwrap();
        assets = assets - fee;

        uint256 value0Price = _getPriceProvider().getAssetPrice(address(_baseAsset));
        uint256 value1Price = _getPriceProvider().getAssetPrice(address(tokenB));
        (uint256 value0, uint256 value1, ) = _calculateAssetValueSplit(assets, value0Price, value1Price);

        uint256 amount0 = value0 * 10**token0Decimal / value0Price;
        uint256 amount1 = value1 * 10**token1Decimal / value1Price;

        (uint160 sqrtPrice, , , , , , ) = pool.globalState();
        uint256 price = FullMath.mulDiv(uint256(sqrtPrice) * (uint256(sqrtPrice)), PRECISION_36, 2**(96 * 2));

        (uint256 pool0, uint256 pool1) = gamma.getTotalAmounts();

        shares = amount1 + (amount0 * price / PRECISION_36);

        uint256 total = gamma.totalSupply();

        uint256 pool0PricedInToken1 = pool0 * price / PRECISION_36;
        shares = shares * total / (pool0PricedInToken1 + pool1);

        return shares;
    }

    function previewWithdraw(uint256 shares) public view override returns (uint256 assets) {
        PositionAmounts memory userAmounts = amountsForShares(shares);

        uint256 token0Price = _getPriceProvider().getAssetPrice(address(_baseAsset));
        uint256 token1Price = _getPriceProvider().getAssetPrice(address(tokenB));

        assets = userAmounts.totalAmount0 * token0Price / 10**token0Decimal + userAmounts.totalAmount1 * token1Price / token0Price;
    }

    function amountsForShares(uint256 shares) public view returns (PositionAmounts memory) {
        uint256 gammaTotalSupply = gamma.totalSupply();

        (uint256 userBase0, uint256 userBase1) = _calculateBasePosition(shares, gammaTotalSupply);
        (uint256 userLimit0, uint256 userLimit1) = _calculateLimitPosition(shares, gammaTotalSupply);

        uint256 unusedAmount0 = _calculateUnusedAmount0(shares, gammaTotalSupply);
        uint256 unusedAmount1 = _calculateUnusedAmount1(shares, gammaTotalSupply);

        return PositionAmounts({
            totalAmount0: userBase0 + userLimit0 + unusedAmount0,
            totalAmount1: userBase1 + userLimit1 + unusedAmount1
        });
    }

    function _calculateBasePosition(uint256 shares, uint256 gammaTotalSupply) internal view returns (uint256 userBase0, uint256 userBase1) {
        (uint256 baseLiquidity, uint256 base0, uint256 base1) = gamma.getBasePosition();
        uint256 userBaseLiquidity = baseLiquidity * shares * PRECISION_36 / gammaTotalSupply;
        
        userBase0 = base0 * userBaseLiquidity / (baseLiquidity * PRECISION_36);
        userBase1 = base1 * userBaseLiquidity / (baseLiquidity * PRECISION_36);
    }

    function _calculateLimitPosition(uint256 shares, uint256 gammaTotalSupply) internal view returns (uint256 userLimit0, uint256 userLimit1) {
        (uint256 limitLiquidity, uint256 limit0, uint256 limit1) = gamma.getLimitPosition();
        uint256 userLimitLiquidity = limitLiquidity * shares * PRECISION_36 / gammaTotalSupply;
        
        userLimit0 = limit0 * userLimitLiquidity / (limitLiquidity * PRECISION_36);
        userLimit1 = limit1 * userLimitLiquidity / (limitLiquidity * PRECISION_36);
    }

    function _calculateUnusedAmount0(uint256 shares, uint256 gammaTotalSupply) internal view returns (uint256) {
        return _baseAsset.balanceOf(address(gamma)) * shares / gammaTotalSupply;
    }

    function _calculateUnusedAmount1(uint256 shares, uint256 gammaTotalSupply) internal view returns (uint256) {
        return tokenB.balanceOf(address(gamma)) * shares / gammaTotalSupply;
    }

    function calculateAmountAB(uint256 assets) public view returns (uint256 amoutn0, uint256 amoutn1) {
        uint256 value0Price = _getPriceProvider().getAssetPrice(address(_baseAsset));
        uint256 value1Price = _getPriceProvider().getAssetPrice(address(tokenB));
        (uint256 valueA, uint256 valueB, ) = _calculateAssetValueSplit(assets, value0Price, value1Price);
        amoutn0 = valueA * 10**token0Decimal / value0Price;
        amoutn1 = valueB * 10**token1Decimal / value1Price;
    }

    function _calculateAssetValueSplit(uint256 assets, uint256 value0Price, uint256 value1Price)
        private
        view
        returns (uint256 value0, uint256 value1, uint256 baseAssetRemaining)
    {
        (uint256 minTokenBAmount, uint256 maxTokenBAmount) = gammaUniProxy.getDepositAmount(
            address(gamma),
            address(_baseAsset),
            TOKEN_SCALE_FACTOR
        );

        uint256 targetTokenBAmount = (minTokenBAmount + (maxTokenBAmount - minTokenBAmount) / 2);

        uint256 targetTokenBValueInBaseAsset = (targetTokenBAmount * value1Price) / value0Price;

        // baseAsset:tokenB ratio
        uint256 baseAssetToTokenBRatio = targetTokenBValueInBaseAsset;

        uint256 value = assets * value0Price / PRECISION_18;
        value0 = value * PRECISION_18 / (PRECISION_18 + baseAssetToTokenBRatio);
        value1 = (value * baseAssetToTokenBRatio) / (PRECISION_18 + baseAssetToTokenBRatio);
        baseAssetRemaining = value - (value0 + value1);
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
        (uint256 amountTokenB, uint256 amountBaseAsset) = _swapAndGetAmounts(assets, data);
        
        _baseAsset.approve(address(gamma), amountBaseAsset);
        tokenB.approve(address(gamma), amountTokenB);

        // Add liquidity
        uint256[4] memory minIn = [uint256(0), uint256(0), uint256(0), uint256(0)];
        (uint256 shares) = gammaUniProxy.deposit(
            amountBaseAsset,
            amountTokenB,
            address(this),
            address(gamma),
            minIn
        );

        // Refund any remaining tokens that were left over after LP provision.
        uint256 remainingTokenB = tokenB.balanceOf(address(this));
        if (remainingTokenB > 0) {
            tokenB.approve(address(swapProps.swapRouter), remainingTokenB);
            // slither-disable-next-line unused-return
            _uniswapV3SwapOut(tokenB, remainingTokenB, 0);
        }
        if (_baseAsset.balanceOf(address(this)) > 0) {
            _baseAsset.safeTransfer(recipient, _baseAsset.balanceOf(address(this)));
        }

        receivedShares = shares;
        _mint(recipient, shares);
    }

    function _swapAndGetAmounts(uint256 assets, bytes memory data)
        internal
        returns (uint256 amountTokenB, uint256 amountBaseAsset)
    {
        (uint256 MIN_RANGE_BPS_B) = abi.decode(data, (uint256));

        uint256 value0Price = _getPriceProvider().getAssetPrice(address(_baseAsset));
        uint256 value1Price = _getPriceProvider().getAssetPrice(address(tokenB));
        (uint256 valueA, uint256 valueB, ) = _calculateAssetValueSplit(assets, value0Price, value1Price);

        uint256 amountAIn = valueB * 10**token0Decimal / value0Price;
        _baseAsset.approve(address(swapProps.swapRouter), amountAIn);

        uint256 amountB = valueB * 10**token1Decimal / value1Price;
        uint256 minSwap = amountB * MIN_RANGE_BPS_B / 10_000;

        amountTokenB = _uniswapV3SwapIn(_baseAsset, amountAIn, minSwap);
        // valueA:valueB = newValueA:newValueB
        amountBaseAsset = amountTokenB * value1Price * valueA / (valueB * 1e18);
        amountBaseAsset = amountBaseAsset / 10**(18 - token0Decimal);
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
        gamma.approve(address(gamma), shares);

        uint256[4] memory minAmounts = [uint256(0), uint256(0), uint256(0), uint256(0)];
        (uint256 amountA, uint256 amountB) = gamma.withdraw(
            shares, // liquidity
            address(this),
            address(this),
            minAmounts
        );

        uint256 _baseAssetsReceived = _uniswapV3SwapOut(tokenB, amountB, 0);

        amountA = amountA * 10**(18 - token0Decimal);
        _baseAssetsReceived = _baseAssetsReceived * 10**(18 - token0Decimal);
        receivedAssets = amountA + _baseAssetsReceived;

        require(receivedAssets >= minAssets, "UniswapV3StrategyVault: Received less than minAssets");
        // Transfer out everything, but only count the assets from the swap as explicitly received.
        _baseAsset.safeTransfer(recipient, _baseAsset.balanceOf(address(this)));
    }

    function _claimRewards(address caller, address owner) internal virtual override returns (uint256[] memory rewards) {
        
    }

    function getPositionValue(address account) public view virtual override returns (uint256 value) {
        uint256 totalShares = balanceOf(account);

        value = 0;

        if (totalShares > 0) {
            value = previewWithdraw(totalShares);
        }
    }
}

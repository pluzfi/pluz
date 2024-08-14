// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../external/uniswap/interfaces/IUniswapV2Factory.sol";
import "../external/uniswap/interfaces/ISwapRouter.sol";

/// @dev Uses Uniswap V3 Swap Router to do an ExactInputMultiHop swap.
abstract contract UniswapV3SwapZapper {
    using SafeERC20 for IERC20;

    struct SwapProps {
        /// @dev Router used for swapping 50% of base asset back and forth between base and tokenB.
        ISwapRouter swapRouter;
        bytes inPath;
        bytes outPath;
    }

    SwapProps swapProps;

    constructor(address swapRouter_, bytes memory inPath_, bytes memory outPath_) {
        swapProps.swapRouter = ISwapRouter(swapRouter_);
        _updatePaths(inPath_, outPath_);
    }

    function getSwapProps() external view returns (SwapProps memory) {
        return swapProps;
    }

    function _updatePaths(bytes memory inPath_, bytes memory outPath_) internal {
        swapProps.inPath = inPath_;
        swapProps.outPath = outPath_;
    }

    function _uniswapV3SwapIn(
        IERC20 asset,
        uint256 amount,
        uint256 minAmount
    )
        internal
        returns (uint256 receivedAssets)
    {
        receivedAssets = _uniswapV3Swap(asset, amount, minAmount, swapProps.inPath);
    }

    function _uniswapV3SwapOut(
        IERC20 asset,
        uint256 amount,
        uint256 minAmount
    )
        internal
        returns (uint256 receivedAssets)
    {
        receivedAssets = _uniswapV3Swap(asset, amount, minAmount, swapProps.outPath);
    }

    function _uniswapV3Swap(
        IERC20 asset,
        uint256 amount,
        uint256 minAmount,
        bytes memory path
    )
        internal
        returns (uint256 receivedAssets)
    {
        asset.safeIncreaseAllowance(address(swapProps.swapRouter), amount);
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amount,
            amountOutMinimum: minAmount
        });
        receivedAssets = swapProps.swapRouter.exactInput(params);
    }
}

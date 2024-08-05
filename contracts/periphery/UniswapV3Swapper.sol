// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../external/uniswap/interfaces/IUniswapV2Factory.sol";
import "../external/uniswap/interfaces/ILynexOdosRouterV2.sol";

/// @dev Uses Uniswap V3 Swap Router to do an ExactInputMultiHop swap.
abstract contract UniswapV3SwapZapper {
    using SafeERC20 for IERC20;

    struct SwapProps {
        /// @dev Router used for swapping 50% of base asset back and forth between base and tokenB.
        ILynexOdosRouterV2 swapRouter;
        bytes inPathDefinition;
        bytes outPathDefinition;
    }

    SwapProps swapProps;

    constructor(address swapRouter_, bytes memory inPath_, bytes memory outPath_) {
        swapProps.swapRouter = ILynexOdosRouterV2(swapRouter_);
        _updatePaths(inPath_, outPath_);
    }

    function getSwapProps() external view returns (SwapProps memory) {
        return swapProps;
    }

    function _updatePaths(bytes memory inPath_, bytes memory outPath_) internal {
        swapProps.inPathDefinition = inPath_;
        swapProps.outPathDefinition = outPath_;
    }

    function _uniswapV3SwapIn(
        IERC20 inputToken,
        IERC20 outputToken,
        uint256 inputAmount,
        uint256 outputQuote,
        uint256 minAmount
    )
        internal
        returns (uint256 receivedAssets)
    {
        receivedAssets = _swapWithOdos(inputToken, outputToken, inputAmount, outputQuote, minAmount, swapProps.inPathDefinition);
    }

    function _uniswapV3SwapOut(
        IERC20 inputToken,
        IERC20 outputToken,
        uint256 inputAmount,
        uint256 outputQuote,
        uint256 minAmount
    )
        internal
        returns (uint256 receivedAssets)
    {
        receivedAssets = _swapWithOdos(inputToken, outputToken, inputAmount, outputQuote, minAmount, swapProps.outPathDefinition);
    }

    function _swapWithOdos(
        IERC20 inputToken,
        IERC20 outputToken,
        uint256 inputAmount,
        uint256 outputQuote,
        uint256 minAmount,
        bytes memory pathDefinition
    )
        internal
        returns (uint256 receivedAssets)
    {
        inputToken.safeIncreaseAllowance(address(swapProps.swapRouter), inputAmount);

        ILynexOdosRouterV2.swapTokenInfo memory tokenInfo = ILynexOdosRouterV2.swapTokenInfo({
            inputToken: address(inputToken),
            inputAmount: inputAmount,
            inputReceiver: address(swapProps.swapRouter),
            outputToken: address(outputToken),
            outputQuote: outputQuote,
            outputMin: minAmount,
            outputReceiver: address(this)
        });

        try swapProps.swapRouter.swap(tokenInfo, pathDefinition, address(this), 0) returns (uint256 amountOut) {
            receivedAssets = amountOut;
        } catch {
            revert("swap call failed");
        }
    }
}

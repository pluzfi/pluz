// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "../interfaces/IAccountManager.sol";
import "../interfaces/IProtocolGovernor.sol";
import "../interfaces/IStrategyVault.sol";
import "../system/ProtocolModule.sol";
import "../libraries/Errors.sol";
import "../solady/src/tokens/ERC20.sol";
import "../solady/src/utils/FixedPointMathLib.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract StrategyVaultEvents {
    /// @notice The deposit cap has been updated to `newDepositCap`
    event DepositCapUpdated(uint256 newDepositCap);
    event MaxDepositPerAccountUpdated(uint256 newMaxDeposit);
    event DepositFeeUpdated(uint256 newDepositFee);
    event WithdrawalFeeUpdated(uint256 newWithdrawalFee);
    event LiquidationSlippageModelUpdated(address newModel);
    event DepositFeeTaken(uint256 amount);
}

/// @dev Token precision is fixed to be 18 decimals.
abstract contract StrategyVault is IStrategyVault, Context, ERC20, ProtocolModule, Pausable, StrategyVaultEvents {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    error LiquidationInvalidAmountReceived(uint256 expected, uint256 actual);
    error InvalidLiquidationSlippageModel();

    struct BaseInitParams {
        address protocolGovernor;
        string vaultName;
        string vaultSymbol;
        address baseAsset;
    }

    struct VaultParams {
        /// @notice The maximum amount of baseAsset that can be deposited into the vault per user.
        uint256 maxDepositPerAccount;
        /// @notice The total cap to apply to deposits in baseAsset.
        uint256 totalDepositCap;
        UD60x18 depositFee;
        UD60x18 withdrawalFee;
        IStrategySlippageModel liquidationSlippageModel;
    }

    string private _tokenName;
    string private _tokenSymbol;

    /// @dev Asset that is deposited into the vault and received by a recipient on withdrawal.
    IERC20 internal immutable _baseAsset;

    /// @dev Amount of base asset deposited into the vault.
    uint256 internal _totalBaseDeposit;

    VaultParams internal _vaultParams;

    mapping(address => uint256) internal _baseDepositAmounts;

    constructor(BaseInitParams memory params, VaultParams memory risk) ProtocolModule(params.protocolGovernor) {
        // The initial deposit cap is set ot the max
        _tokenName = params.vaultName;
        _tokenSymbol = params.vaultSymbol;
        _baseAsset = IERC20(params.baseAsset);
        _vaultParams = risk;
    }

    function setTotalDepositCap(uint256 newDepositCap) external onlyOwner {
        _vaultParams.totalDepositCap = newDepositCap;
        emit DepositCapUpdated(newDepositCap);
    }

    function setMaxDepositPerAccount(uint256 newMaxDeposit) external onlyOwner {
        _vaultParams.maxDepositPerAccount = newMaxDeposit;
        emit MaxDepositPerAccountUpdated(newMaxDeposit);
    }

    function setDepositFee(UD60x18 newDepositFee) external onlyOwner {
        _vaultParams.depositFee = newDepositFee;
        emit DepositCapUpdated(newDepositFee.unwrap());
    }

    function setWithdrawalFee(UD60x18 newWithdrawalFee) external onlyOwner {
        _vaultParams.withdrawalFee = newWithdrawalFee;
        emit WithdrawalFeeUpdated(newWithdrawalFee.unwrap());
    }

    function setLiquidationSlippageModel(address model) external nonZeroAddress(model) onlyOwner {
        _vaultParams.liquidationSlippageModel = IStrategySlippageModel(model);

        try _vaultParams.liquidationSlippageModel.calculateSlippage(0) { }
        catch {
            revert InvalidLiquidationSlippageModel();
        }

        emit LiquidationSlippageModelUpdated(model);
    }

    /// @notice Let the owner pause the vault
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Let the owner pause the vault
    function unpause() external onlyOwner {
        _unpause();
    }

    function name() public view override returns (string memory) {
        return _tokenName;
    }

    function symbol() public view override returns (string memory) {
        return _tokenSymbol;
    }

    function getTotalDepositCap() external view returns (uint256) {
        return _vaultParams.totalDepositCap;
    }

    function getMaxDepositPerAccount() external view returns (uint256) {
        return _vaultParams.maxDepositPerAccount;
    }

    function getVaultParams() external view returns (VaultParams memory) {
        return _vaultParams;
    }

    function getBaseAsset() external view returns (IERC20) {
        return _baseAsset;
    }

    function getTotalBaseDeposit() external view returns (uint256) {
        return _totalBaseDeposit;
    }

    /// @dev BaseAsset is transferred out of the recipient.
    /// `msg.sender` should always be an AccountManager.
    function deposit(
        uint256 assets,
        bytes memory data,
        address recipient
    )
        external
        payable
        virtual
        whenProtocolNotDeprecated
        whenNotPaused
        onlyAccountManager
        returns (uint256 receivedShares)
    {
        if (assets == 0) revert Errors.ParamCannotBeZero();

        _totalBaseDeposit += assets;
        _baseDepositAmounts[recipient] += assets;

        if (_vaultParams.totalDepositCap != type(uint256).max && _totalBaseDeposit > _vaultParams.totalDepositCap) {
            revert Errors.DepositCapExceeded();
        }

        if (
            _vaultParams.maxDepositPerAccount != type(uint256).max
                && _baseDepositAmounts[recipient] > _vaultParams.maxDepositPerAccount
        ) revert Errors.MaxDepositPerAccountExceeded();

        _baseAsset.safeTransferFrom(recipient, address(this), assets);

        uint256 depositFee = 0;
        if (_vaultParams.depositFee > ZERO) {
            depositFee = (ud(assets) * _vaultParams.depositFee).unwrap();
            _baseAsset.safeTransfer(_getFeeCollector(), depositFee);
            emit DepositFeeTaken(depositFee);
        }

        receivedShares = _deposit(assets - depositFee, data, recipient);
    }

    function withdraw(uint256 shares, bytes memory data) external payable virtual returns (uint256 receivedAmount) {
        receivedAmount = _withdraw(msg.sender, shares, data, msg.sender);
        _deductFromDepositCap(msg.sender, receivedAmount);
    }

    function _deductFromDepositCap(address account, uint256 amount) internal {
        _totalBaseDeposit = _totalBaseDeposit.zeroFloorSub(amount);

        if (balanceOf(account) > 0) {
            _baseDepositAmounts[account] = _baseDepositAmounts[account].zeroFloorSub(amount);
        } else {
            _baseDepositAmounts[account] = 0;
        }
    }

    /// Second parameter is disregarded and kept to be backwards compatible with mainnet.
    /// @notice Used by our liquidation engine. Performs a full withdrawal for the `msg.sender`.
    function liquidate(
        address receiver,
        uint256,
        bytes memory data
    )
        external
        payable
        virtual
        returns (uint256 receivedAssets)
    {
        // We assume `msg.sender` is an IAccount because only AccountManagers can deposit into Strategies
        // on behalf of Accounts.

        uint256 totalShares = balanceOf(msg.sender);

        // Get the Manager that created the Account to check the Account's liquidation status
        IAccountManager manager = IAccount(msg.sender).getManager();
        AccountLib.LiquidationStatus memory status = manager.getAccountLiquidationStatus(msg.sender);

        if (!status.isLiquidating) {
            revert Errors.AccountNotBeingLiquidated();
        }

        // Calculate minimum amount to receive from full withdrawal based off:
        // - Slippage based off a model that increases as duration of liquidation time increases.
        // - Current position value of the Account via getPositionValue. This value MUST be derived from an manipulation
        // resistant method.
        // Slippage model increases as liquidation time increases to hedge against mispricing.

        // For example, if position is ETH and actual price on AMM is $1900 with oracle price being $2000, it will
        // expect $2000 * (1 - slippage %).
        // If this fails, time will pass and the slippage % will increase, reducing the expected amount and ensuring
        // liquidation happens at some point.

        // This is necessary to protect against liquidators sandwiching user positions.

        // In the future, an auction based liquidation mechanism should be used instead (i.e. selling position at a
        // discount based off oracle price, ensuring debt is paid upfront).

        uint256 timeSinceLiquidation = FixedPointMathLib.zeroFloorSub(block.timestamp, status.liquidationStartTime);
        UD60x18 slippage = _vaultParams.liquidationSlippageModel.calculateSlippage(timeSinceLiquidation);
        uint256 currentValue = getPositionValue(msg.sender);
        uint256 minAmountAfterSlippage = currentValue - ((ud(currentValue) * slippage).unwrap());

        // Encode 0 as minAmount because slippage is enforced after withdrawal and ignore data if it is empty.
        // Simple strategies will expect a minAmount value to use somewhere in the withdrawal step.
        if (keccak256(data) == keccak256("")) {
            receivedAssets = _withdraw(msg.sender, totalShares, abi.encode(0), receiver);
        } else {
            receivedAssets = _withdraw(msg.sender, totalShares, data, receiver);
        }

        if (receivedAssets < minAmountAfterSlippage) {
            revert LiquidationInvalidAmountReceived(minAmountAfterSlippage, receivedAssets);
        }

        _deductFromDepositCap(msg.sender, receivedAssets);
    }

    function estimateExecuteDepositGasLimit() external view virtual returns (uint256) {
        return 0;
    }

    function estimateExecuteWithdrawalGasLimit() external view virtual returns (uint256) {
        return 0;
    }

    function _deposit(uint256 assets, bytes memory data, address recipient) internal virtual returns (uint256);

    function _withdraw(
        address caller,
        uint256 shares,
        bytes memory data,
        address recipient
    )
        internal
        virtual
        returns (uint256);

    /// @notice This function allows users to simulate the effects of their withdrawal at the current block.
    /// @dev Use this to calculate the minAmount of lend token to withdraw during withdrawal
    /// @param shareAmount The amount of shares to redeem
    /// @return The amount of lend token that would be redeemed for the amount of shares provided
    function previewWithdraw(uint256 shareAmount) public view virtual returns (uint256);

    /// @notice This function allows users to simulate the effects of their deposit at the current block.
    /// @dev Use this to calculate the minAmount of shares to mint during deposit
    /// @param assetAmount The amount of assets to deposit
    /// @return The amount of shares that would be minted for the amount of asset provided
    function previewDeposit(uint256 assetAmount) public view virtual returns (uint256);

    /// @notice Gets the value of a user's position denominated in baseAsset.
    /// Similar to previewWithdraw, but it uses manipulation resistant pricing and may return a risk adjusted value
    /// instead of the actual value.
    function getPositionValue(address account) public view virtual returns (uint256);

    /// @notice Disables transfers other than mint and burn
    /// @dev Done explicitly because solady transfers do not prevent transferring to zero address.
    function transfer(address, uint256) public pure override returns (bool) {
        revert Errors.TransferDisabled();
    }

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert Errors.TransferDisabled();
    }
}

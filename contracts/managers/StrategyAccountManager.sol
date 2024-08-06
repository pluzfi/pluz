// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "./AccountManager.sol";
import "../solady/src/utils/FixedPointMathLib.sol";

/// @title Account Factory Events
/// @dev Place all events used by the AccountManager contract here
abstract contract StrategyAccountManagerEvents {
    /// @notice The owner has made their first deposit into `strategy`
    event StrategyActivated(address indexed owner, address indexed account, address indexed strategy);
    /// @notice The owner has withdrawn their last deposit from `strategy`
    event StrategyDeactivated(address indexed owner, address indexed account, address indexed strategy);
    /// @notice The admin has approved the account to use `strategy`
    event StrategyUpdated(address strategy, bool approval);
    /// @notice A user has deployed funds into a strategy.
    event StrategyDeposit(address indexed owner, address indexed strategy, address indexed account, uint256 amount);
    /// @notice A user has withdrawn funds from a strategy.
    event StrategyWithdrawal(address indexed owner, address indexed strategy, address indexed account, uint256 amount);
    /// @notice The slippage tolerated for withdraws from strategies has been updated to `tolerance`
    event MaximumSlippageToleranceUpdated(UD60x18 tolerance);
}

/// @title AccountManager
/// @notice The AccountManager contract deploys Account contracts.
/// Investment Accounts are only createable by the owner of this contract or
/// accounts approved by the admin (known as account creators).
abstract contract StrategyAccountManager is AccountManager, StrategyAccountManagerEvents {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;
    using Address for address;

    /// @notice The strategies that are approved to use for permissioned accounts
    mapping(address => bool) public approvedStrategies;

    /// @notice Map of accounts to their active strategies
    mapping(address => EnumerableSet.AddressSet) internal _activeStrategies;

    /// @notice Constructs the factory
    constructor(
        address protocolGovernor_,
        address liquidationReceiverImpl_
    )
        AccountManager(protocolGovernor_, liquidationReceiverImpl_)
    { }

    /// @notice Get an active strategy's address by index
    /// @param index The index of the active strategy
    function getActiveStrategy(address account, uint256 index) external view returns (address) {
        return _activeStrategies[account].at(index);
    }

    /// @notice Get the number of active strategies
    function getActiveStrategyCount(address account) external view returns (uint256) {
        return _activeStrategies[account].length();
    }

    /// @dev This is called by the Account to check if the strategy is approved.
    /// @dev Mainly to consolidate events into the Manager though.
    function strategyDeposit(
        address owner,
        address strategy,
        uint256 amount,
        bytes memory data
    )
        external
        payable
        virtual
        onlyAccount
        nonReentrant
        returns (uint256 shares)
    {
        shares = _strategyDeposit(msg.sender, owner, strategy, amount, data);
    }

    function _strategyDeposit(
        address caller,
        address owner,
        address strategy,
        uint256 amount,
        bytes memory data
    )
        internal
        returns (uint256 shares)
    {
        if (!approvedStrategies[strategy]) {
            revert Errors.StrategyNotApproved();
        }

        if (_activeStrategies[caller].add(strategy)) {
            emit StrategyActivated(owner, caller, strategy);
        }

        uint256 executionGasLimit = 0;
        if (strategy != address(0)) {
            executionGasLimit = IStrategyVault(strategy).estimateExecuteDepositGasLimit();
        }

        uint256 executionFee = 0;

        if (executionGasLimit > 0) {
            executionFee = executionGasLimit * tx.gasprice;
        }

        shares = IStrategyVault(strategy).deposit{ value: executionFee }(amount, data, caller);

        emit StrategyDeposit(owner, strategy, caller, amount);

        _requireSolvent(caller);
    }

    function strategyWithdrawal(
        address owner,
        address strategy,
        uint256 assets
    )
        external
        virtual
        onlyAccount
        nonReentrant
    {
        _strategyWithdrawal(msg.sender, owner, strategy, assets);
    }

    function _strategyWithdrawal(address caller, address owner, address strategy, uint256 assets) internal {
        emit StrategyWithdrawal(owner, strategy, caller, assets);

        // Deactivate the strategy if it has no more funds
        // Strategy balanceOf will not return less than 0
        // slither-disable-next-line incorrect-equality
        if (strategy != address(0) && IStrategyVault(strategy).getPositionValue(caller) == 0) {
            // slither-disable-next-line unused-return
            _activeStrategies[caller].remove(strategy);

            emit StrategyDeactivated(owner, caller, strategy);
        }

        _requireSolvent(caller);
    }

    /// @dev LiquidationReceiver is the recipient of the liquidated funds.
    /// In case of multi transaction withdrawal strategies, liquidator must wait for liquidationReceiver to receive
    /// funds before
    /// calling liquidationReceiver.repay().
    function liquidateStrategy(
        address account,
        address liquidationFeeTo,
        address strategy,
        bytes memory data
    )
        external
        payable
        virtual
        returns (ILiquidationReceiver liquidationReceiver_)
    {
        liquidationReceiver_ = _startLiquidation(account, liquidationFeeTo);

        // We calculate this as the strategy level now. Leftover for backwards compatibility.
        uint256 minAmountAfterSlippage = 0;

        uint256 executionGasLimit = 0;
        if (strategy != address(0)) {
            executionGasLimit = IStrategyVault(strategy).estimateExecuteWithdrawalGasLimit();
        }

        uint256 executionFee = 0;

        if (executionGasLimit > 0) {
            executionFee = executionGasLimit * tx.gasprice;
        }

        IInternalAccount(account).liquidateStrategy{ value: executionFee }(
            strategy, address(liquidationReceiver_), minAmountAfterSlippage, data
        );

        // Deactivate the strategy if it has no more funds
        // Strategy balanceOf will not return less than 0
        // slither-disable-next-line incorrect-equality
        if (strategy != address(0) && IStrategyVault(strategy).getPositionValue(account) == 0) {
            // slither-disable-next-line unused-return
            _activeStrategies[account].remove(strategy);

            emit StrategyDeactivated(_accountOwnerCache[account], account, strategy);
        }
    }

    /// @notice Get the value of all strategies investments
    /// @return totalValue The value of all strategy investments in lendAsset
    function getTotalAccountValue(address account) public view override returns (uint256 totalValue) {
        uint256 lendPoolBalance = _lendPoolActualAsset.balanceOf(address(account));
        uint256 decimals = IERC20Rebasing(address(_lendAsset)).getActualAssetDecimals();
        if (decimals == 6) {
            lendPoolBalance = lendPoolBalance * 10**12;
        }
        
        totalValue = lendPoolBalance;
        // Sum the value of all active strategy vaults
        // Note: This needs attention as getPositionValue may revert, it contains external calls
        // slither-disable-next-line calls-loop
        for (uint256 i = 0; i < _activeStrategies[account].length(); i++) {
            // Note: This needs attention as getPositionValue may revert, it contains external calls
            // slither-disable-next-line calls-loop
            totalValue += IStrategyVault(_activeStrategies[account].at(i)).getPositionValue(account);
        }
    }

    function updateStrategyApproval(address strategy, bool approval) external onlyOwner {
        approvedStrategies[strategy] = approval;
        emit StrategyUpdated(strategy, approval);
    }

    function isApprovedStrategy(address strategy) external view returns (bool) {
        return approvedStrategies[strategy];
    }
}

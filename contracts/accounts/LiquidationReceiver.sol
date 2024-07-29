// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "../interfaces/ILiquidationReceiver.sol";
import "../libraries/accounts/AccountLib.sol";
import "../libraries/traits/AddressCheckerTrait.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @title Contract is used to isolated proceeds from different Liquidators.
/// This is the recipient of liquidated funds.
/// Manager initializes an instance per (Liquidator, Account) pair.
/// When a Liquidator liquidates an Account, the funds land in here.
/// The Manager has control of these funds and pulls from this when performing a repayment.
/// Manager is trusted to send appropriate liquidationFee to `liquidationFeeTo`.
contract LiquidationReceiver is ILiquidationReceiver, Initializable, AddressCheckerTrait {
    using SafeERC20 for IERC20;

    Props props;

    /// @notice Empty constructor because this contract is deployed as a clone in the manager
    constructor() {
        _disableInitializers();
    }

    function initialize(Props memory props_)
        external
        virtual
        nonZeroAddress(address(props_.manager))
        nonZeroAddress(props_.liquidationFeeTo)
        initializer
    {
        props = props_;
    }

    function repay() external {
        uint256 amount = props.asset.balanceOf(address(this));

        // The fee is taken from anything sent through this method.
        AccountLib.LiquidationFee memory fee = props.manager.getLiquidationFee();

        uint256 protocolShare = ud(amount).mul(fee.protocolShare).unwrap();
        uint256 liquidatorShare = ud(amount).mul(fee.liquidatorShare).unwrap();

        address feeCollector = props.manager.getFeeCollector();
        props.asset.safeTransfer(feeCollector, protocolShare);
        props.asset.safeTransfer(props.liquidationFeeTo, liquidatorShare);

        props.manager.emitLiquidationFeeEvent(feeCollector, props.liquidationFeeTo, protocolShare, liquidatorShare);

        // Repay with remaining assets.
        amount = props.asset.balanceOf(address(this));
        props.asset.safeTransfer(address(props.account), amount);
        props.account.repay(amount);
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IFlashLoanLender {
    /**
     * @dev When `flashLoanSimple` is called on the Lender, it invokes the `receiveFlashLoanSimple` hook on the
     * recipient.
     *
     * At the time of the call, the Lending Pool will have transferred `amount` for `token` to the recipient. Before
     * this call returns, the recipient must have transferred `amount` plus `feeAmount` for the token back to the
     * Lender, or else the entire flash loan will revert.
     *
     * `userData` is the same value passed in the `ILendingPool.flashLoanSimple` call.
     *
     * The flash loan lender forwards the initiator of the loan.
     * It also expects back some call data from the receiver and returns it to the initiator.
     */
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes memory userData
    )
        external
        returns (bytes memory);
}

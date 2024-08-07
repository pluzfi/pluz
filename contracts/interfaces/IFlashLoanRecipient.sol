// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IFlashLoanRecipient {
    /**
     * @dev When `flashLoanSimple` is called on the Lending Pool, it invokes the `receiveFlashLoanSimple` hook on the
     * recipient.
     *
     * At the time of the call, the Lending Pool will have transferred `amount` for `token` to the recipient. Before
     * this
     * call returns, the recipient must have transferred `amount` plus `feeAmount` for the token back to the
     * Lending Pool, or else the entire flash loan will revert.
     *
     * `userData` is the same value passed in the `ILendingPool.flashLoanSimple` call.
     *
     * The flash loan lender forwards the initiator of the loan.
     * It also expects back the call data that it forwards to the initiator.
     * @return success True if the execution of the operation succeeds, false otherwise
     * @return data Any callback data that the initiator needs
     */
    function receiveFlashLoanSimple(
        address initiator,
        IERC20 token,
        uint256 amount,
        uint256 feeAmount,
        bytes memory userData
    )
        external
        returns (bool success, bytes memory data);
}

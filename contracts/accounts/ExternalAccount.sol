// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./BaseAccount.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";
import "../libraries/Errors.sol";

/// @title External Account
/// @notice This account type supports borrowing from the lending pool
/// directly to the owners wallet. LTVs on this account type will be
/// less than 100%. This account type relies on off-chain liquidations.
contract ExternalAccount is BaseAccount {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Initialize this permissionless account
    /// @param owner_ The borrower that owns this account
    function initialize(address owner_) public override initializer {
        _initialize(owner_);
    }

    //////////////////////////
    // Lending Pool Methods
    //////////////////////////

    /// @notice Borrow from the lending pool
    /// @param amount The amount to borrow
    function borrow(uint256 amount) external payable override onlyOwner whenNotPaused {
        uint256 amountBorrowed = _manager.borrow(amount);
        asset.safeTransfer(_msgSender(), amountBorrowed);
        emit Borrow(amountBorrowed);
    }

    /// @notice Repay the lending pool
    /// @param amount The amount to repay
    function repay(uint256 amount) external payable override whenNotPaused {
        uint256 amountRepaid = _manager.repay(address(this), amount);
        emit Repay(amountRepaid);
    }

    function getKind() external pure returns (bytes32) {
        return keccak256(abi.encode("OMEGA_EXTERNAL_ACCOUNT"));
    }
}

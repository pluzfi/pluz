/// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.24;
pragma abicoder v2;

/// @title UniProxy Interface
/// @notice Interface for the UniProxy contract
interface IUniProxy {

    /// @notice Deposit into the given position
    /// @param deposit0 Amount of token0 to deposit
    /// @param deposit1 Amount of token1 to deposit
    /// @param to Address to receive liquidity tokens
    /// @param pos Hypervisor Address
    /// @param minIn min assets to expect in position during a direct deposit 
    /// @return shares Amount of liquidity tokens received
    function deposit(
        uint256 deposit0,
        uint256 deposit1,
        address to,
        address pos,
        uint256[4] memory minIn
    ) external returns (uint256 shares);

    /// @notice Get the amount of token to deposit for the given amount of pair token
    /// @param pos Hypervisor Address
    /// @param token Address of token to deposit
    /// @param _deposit Amount of token to deposit
    /// @return amountStart Minimum amounts of the pair token to deposit
    /// @return amountEnd Maximum amounts of the pair token to deposit
    function getDepositAmount(
        address pos,
        address token,
        uint256 _deposit
    ) external view returns (uint256 amountStart, uint256 amountEnd);

    /// @notice Transfers the clearance to a new address
    /// @param newClearance The new clearance address
    function transferClearance(address newClearance) external;

    /// @notice Transfers ownership to a new address
    /// @param newOwner The new owner address
    function transferOwnership(address newOwner) external;

}

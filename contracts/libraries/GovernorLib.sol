// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

/// @notice Store keys used by stores in a Governor contract (ProtocolGovernor, etc).
library GovernorLib {
    ///////////////
    // COMMON
    ///////////////

    /// @notice Returns price of an asset given some address. Prices are denominated in the lending pool loan asset.
    bytes32 public constant PRICE_PROVIDER = keccak256(abi.encode("PRICE_PROVIDER"));

    /// @notice Address that receives fee generated by lending, accounts, and strategies
    bytes32 public constant FEE_COLLECTOR = keccak256(abi.encode("FEE_COLLECTOR"));

    bytes32 public constant STRATEGY_SLIPPAGE_MODEL = keccak256(abi.encode("STRATEGY_SLIPPAGE_MODEL"));

    /// @notice Address that is responsible for issuing gas reimbursements to protocol contracts
    bytes32 public constant GAS_TANK = keccak256(abi.encode("GAS_TANK"));

    /// @notice Lending Pool
    bytes32 public constant LENDING_POOL = keccak256(abi.encode("LENDING_POOL"));

    /// @notice Gelato Automate
    bytes32 public constant GELATO_AUTOMATE = keccak256(abi.encode("GELATO_AUTOMATE"));

    /// @notice Pyth Stable
    bytes32 public constant PYTH = keccak256(abi.encode("PYTH"));

    /// @notice Asset used to facilitate lending and borrowing.
    bytes32 public constant LEND_ASSET = keccak256(abi.encode("LEND_ASSET"));


    ///////////////
    // FEES
    ///////////////

    bytes32 public constant LENDING_FEE = keccak256(abi.encode("LENDING_FEE"));

    bytes32 public constant FLASH_LOAN_FEE = keccak256(abi.encode("FLASH_LOAN_FEE"));

    /// @notice % taken from any funds used to repay debt during liquidating state.
    /*
    If an Account with 100 USDC Strategy position gets liquidated with protocolShare of 4%, liquidatorShare of 1%.
        If no slippage, 100 USDC is received by Repayment contract.
        
        Repayment contract is executed with:
            - 4 USDC going to protocol
            - 1 USDC going to liquidator
            - 95 USDC going to repay Account debt
    */
    bytes32 public constant PROTOCOL_LIQUIDATION_SHARE = keccak256(abi.encode("PROTOCOL_LIQUIDATION_SHARE"));

    bytes32 public constant LIQUIDATOR_SHARE = keccak256(abi.encode("LIQUIDATOR_SHARE"));
}

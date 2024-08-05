// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity 0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { FixedPointMathLib } from "../libraries/solmate/src/utils/FixedPointMathLib.sol";

import { ERC20Rebasing } from "./ERC20Rebasing.sol";
import { SharesBase } from "./Shares.sol";
import { Predeploys } from "../libraries/Predeploys.sol";
import { Semver } from "../src/universal/Semver.sol";

/// @custom:proxied
/// @title WETHRebasing
/// @notice Rebasing ERC20 token that serves as WETH.
contract WETHRebasing is ERC20Rebasing, Semver, Ownable {

    IERC20 public immutable WETH;

    mapping(address => bool) public isAuthorized;

    /// @notice Emitted whenever tokens are deposited to an account.
    /// @param account Address of the account tokens are being deposited to.
    /// @param amount  Amount of tokens deposited.
    event Deposit(address indexed account, uint amount);

    /// @notice Emitted whenever tokens are withdrawn from an account.
    /// @param account Address of the account tokens are being withdrawn from.
    /// @param amount  Amount of tokens withdrawn.
    event Withdrawal(address indexed account, uint amount);

    error WETHTransferFailed();

    /// @notice Modifier to check if the caller is authorized
    modifier onlyAuthorized() {
        require(isAuthorized[msg.sender], "Caller is not authorized");
        _;
    }

    modifier onlyAuthorizedRole() {
        require(msg.sender == owner(), "Caller is not owner or account manager");
        _;
    }

    /// @custom:semver 1.0.0
    constructor(address _WETH)
        ERC20Rebasing(18)
        Semver(1, 0, 0)
    {
        WETH = IERC20(_WETH);
    }

    /// @notice Initializer.
    function initialize() external initializer {
        __ERC20Rebasing_init(
            "rebase Wrapped Ether",
            "rWETH",
            1e9
        );
    }

    /// @notice Sets an authorized account and approves the maximum WETH token allowance for it.
    function setAuthorizedAccount(address _account) external onlyAuthorizedRole {
        require(_account != address(0), "_account address not set");
        isAuthorized[_account] = true;
        WETH.approve(_account, type(uint256).max);
    }

    /// @notice             wrap WETH
    /// @param _amount      Amount of WETH to wrap
    /// msg.sender   Address to send rWETH
    function wrap(uint256 _amount) external onlyAuthorized {
        WETH.transferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, _amount);
    }

    /// @notice             Unwrap rWETH
    /// @param _amount      Amount of rWETH to unwrap
    /// msg.sender   Address to send WETH
    function unwrap(uint256 _amount) external onlyAuthorized {
        _burn(msg.sender, _amount);
        WETH.transfer(msg.sender, _amount);
    }

    function _mint(address _to, uint256 _amount) internal {
        if (_to == address(0)) {
            revert TransferToZeroAddress();
        }

        _deposit(_to, _amount);
        emit Transfer(address(0), _to, _amount);
    }

    function _burn(address _from, uint256 _amount) internal {
        if (_from == address(0)) {
            revert TransferFromZeroAddress();
        }

        _withdraw(_from, _amount);
        emit Transfer(_from, address(0), _amount);
    }

    /// @notice Allows a user to send WETH directly and have
    ///         their balance updated.
    receive() external payable {
        deposit();
    }

    /// @notice Deposit WETH and increase the wrapped balance.
    function deposit() public payable {
        address account = msg.sender;
        _deposit(account, msg.value);

        emit Deposit(account, msg.value);
    }

    /// @notice Withdraw WETH and decrease the wrapped balance.
    /// @param wad Amount to withdraw.
    function withdraw(uint256 wad) public {
        address account = msg.sender;
        _withdraw(account, wad);

        (bool success,) = account.call{value: wad}("");
        if (!success) revert WETHTransferFailed();

        emit Withdrawal(account, wad);
    }

    /// @notice Update the share price based on the rebased contract balance.
    function _addValue(uint256) internal override {
        if (msg.sender != REPORTER) {
            revert InvalidReporter();
        }

        uint256 yieldBearingEth = price * _totalShares;
        uint256 pending = address(this).balance - yieldBearingEth - _totalVoidAndRemainders;
        if (pending < _totalShares || _totalShares == 0) {
            return;
        }

        price += (pending / _totalShares);
    }

    /**
     * @dev The version parameter for the EIP712 domain.
     */
    function _EIP712Version() internal override view returns (string memory) {
        return version();
    }

    /// @notice Gets the actual asset address for this Rebasing token
    /// @return Address of the actual asset
    function getActualAsset() external view returns (address) {
        return address(WETH);
    }

    /// @notice Gets the decimals of the actual asset
    /// @return Decimals of the actual asset
    function getActualAssetDecimals() external view returns (uint8) {
        return 18;
    }
}

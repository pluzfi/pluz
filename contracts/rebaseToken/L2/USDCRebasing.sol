// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity 0.8.15;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import { ERC20Rebasing } from "./ERC20Rebasing.sol";
import { SharesBase } from "./Shares.sol";
import { Semver } from "../src/universal/Semver.sol";
import { Predeploys } from "../libraries/Predeploys.sol";

/// @custom:proxied
/// @title rUSDC
/// @notice Rebasing ERC20 token used for wrapping and unwrapping USDC into rUSDC tokens.
contract USDCRebasing is ERC20Rebasing, Semver, Ownable {

    IERC20 public immutable USDC;

    address public lendingPool;

    mapping(address => bool) public isAuthorized;

    /// @notice Address doesn't have role
    error UnauthorizedRole(address account, string role);

    /**
     * @notice Only allows the contract's own address to call the function.
     */
    modifier onlySelf() {
        if (msg.sender != address(this)) {
            revert UnauthorizedRole(msg.sender, "SELF");
        }
        _;
    }

    /// @notice Modifier to check if the caller is authorized
    modifier onlyAuthorized() {
        require(isAuthorized[msg.sender], "Caller is not authorized");
        _;
    }

    modifier onlyLendingPool() {
        require(msg.sender == lendingPool, "Caller is not lending pool");
        _;
    }

    /// @custom:semver 1.0.0
    /// @param _usdYieldManager Address of the USD Yield Manager. SharesBase yield reporter.
    /// @param _USDC        Address of USDC.
    constructor(address _usdYieldManager, address _USDC)
        ERC20Rebasing(_usdYieldManager, 18)
        Semver(1, 0, 0)
    {
        USDC = IERC20(_USDC);
        isAuthorized[_usdYieldManager] = true;
        USDC.approve(_usdYieldManager, type(uint256).max);
    }

    /// @notice Initializer
    function initialize() public initializer {
        __ERC20Rebasing_init("rebase USDC", "rUSDC", 1e9);
    }

    /// @notice Sets the lending pool
    function setLendingPool(address _lendingPool) external onlyOwner {
        require(_lendingPool != address(0), "Invalid lending pool address");
        lendingPool = _lendingPool;
    }

    /// @notice Sets an lending pool approves the maximum USDC token allowance for it.
    function setAuthorizedAccount() external onlyLendingPool {
        require(msg.sender != address(0), "_account address not set");
        isAuthorized[msg.sender] = true;
        USDC.approve(msg.sender, type(uint256).max);
    }

    /// @notice         wrap USDC
    /// @param _amount  Amount of USDC to wrap
    /// msg.sender      Address to send rUSDC
    function wrap(uint256 _amount) external onlyAuthorized {
        uint256 convertAmount = _amount / 10**12;

        USDC.transferFrom(msg.sender, address(this), convertAmount);
        _mint(msg.sender, _amount);
    }

    /// @notice         Unwrap rUSDC
    /// @param _amount  Amount of rUSDC to unwrap
    /// msg.sender      Address to send USDC
    function unwrap(uint256 _amount) external onlyAuthorized {
        uint256 convertAmount = _amount / 10**12;

        _burn(msg.sender, _amount);
        USDC.transfer(msg.sender, convertAmount);
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

    /**
     * @dev The version parameter for the EIP712 domain.
     */
    function _EIP712Version() internal override view returns (string memory) {
        return version();
    }

    /// @notice Gets the actual asset address for this Rebasing token
    /// @return Address of the actual asset
    function getActualAsset() external view returns (address) {
        return address(USDC);
    }

    /// @notice Gets the decimals of the actual asset
    /// @return Decimals of the actual asset
    function getActualAssetDecimals() external view returns (uint8) {
        return 6;
    }
}

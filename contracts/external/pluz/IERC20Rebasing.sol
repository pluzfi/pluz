// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "./IPluz.sol";

interface IERC20Rebasing {
    // changes the yield mode of the caller and update the balance
    // to reflect the configuration
    function configure(YieldMode) external returns (uint256);
    // "claimable" yield mode accounts can call this this claim their yield
    // to another address
    function claim(address recipient, uint256 amount) external returns (uint256);
    // read the claimable amount for an account
    function getClaimableAmount(address account) external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function getConfiguration(address contractAddress) external view returns (uint8);
     // Set authorized account
    function setAuthorizedAccount(address account) external;
    // wrap and unwrap functions
    function wrap(uint256 amount) external;
    function unwrap(uint256 amount) external;
}

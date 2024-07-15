// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

interface IGasTank {
    function allowList(address user) external returns (bool allowed);
    function accessControllers(address controller) external returns (bool allowed);
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function allowListUpdate(address contractAddress, bool allowed) external;
    function accessControllerUpdate(address accessController, bool allowed) external;
    function reimburseGas(address receiver, uint256 amount) external;
}

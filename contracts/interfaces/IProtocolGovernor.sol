// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { UD60x18 } from "@prb/math/src/UD60x18.sol";

interface IProtocolGovernor {
    function getOwner() external view returns (address);
    function getAddress(bytes32 id) external view returns (address);
    function getImmutableAddress(bytes32 id) external view returns (address);
    function setFee(bytes32 id, UD60x18 newFee) external;
    function getFee(bytes32 id) external view returns (UD60x18);

    function isProtocolDeprecated() external view returns (bool);
    // Accounts Managers can open loans on behalf of Accounts they create.
    function updateAccountManagerStatus(address manager, bool active) external;
    function isAccountManager(address manager) external view returns (bool);

    // RBAC
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewardDistributor {

    struct RewardInfo {
        IERC20 token;
        uint256 lastDistributionTime;
    }
    function viewRewards() external view returns (RewardInfo[] memory);
    function pendingRewards() external view returns (uint256[] memory);
    function distribute() external returns ( uint256[] memory );
}

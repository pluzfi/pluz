// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IRewardTracker {
    function depositBalances(address _account, address _depositToken) external view returns (uint256);
    function stakedAmounts(address _account) external view returns (uint256);
    function updateRewards() external;
    function stake(address _depositToken, uint256 _amount) external;
    function stakeForAccount(address _fundingAccount, address _account, address _depositToken, uint256 _amount) external;
    function unstake(address _depositToken, uint256 _amount) external;
    function unstakeForAccount(address _account, address _depositToken, uint256 _amount, address _receiver) external;
    function claim(address _receiver) external returns (uint256[] memory);
    function claimForAccount(address _account, address _receiver) external returns (uint256[] memory);
    function claimable(address _account) external view returns (uint256[] memory);
    function averageStakedAmounts(address _account,uint256 _index) external view returns (uint256);
    function cumulativeRewards(address _account,uint256 _index) external view returns (uint256);
    function getRewardDistributor() external view returns (address);
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./algebra/IAlgebraPool.sol";
interface IHypervisor {


  function deposit(
      uint256,
      uint256,
      address,
      address,
      uint256[4] memory minIn
  ) external returns (uint256);

  function withdraw(
    uint256,
    address,
    address,
    uint256[4] memory
  ) external returns (uint256, uint256);

  function compound() external returns (

    uint128 baseToken0Owed,
    uint128 baseToken1Owed,
    uint128 limitToken0Owed,
    uint128 limitToken1Owed
  );

  function compound(uint256[4] memory inMin) external returns (

    uint128 baseToken0Owed,
    uint128 baseToken1Owed,
    uint128 limitToken0Owed,
    uint128 limitToken1Owed
  );


  function rebalance(
    int24 _baseLower,
    int24 _baseUpper,
    int24 _limitLower,
    int24 _limitUpper,
    address _feeRecipient,
    uint256[4] memory minIn, 
    uint256[4] memory outMin
    ) external;

  function addBaseLiquidity(
    uint256 amount0, 
    uint256 amount1,
    uint256[2] memory minIn
  ) external;

  function addLimitLiquidity(
    uint256 amount0, 
    uint256 amount1,
    uint256[2] memory minIn
  ) external;   

  function pullLiquidity(
    int24 tickLower,
    int24 tickUpper,
    uint128 shares,
    uint256[2] memory amountMin
  ) external returns (
    uint256 base0,
    uint256 base1
  );

  function pullLiquidity(
    uint256 shares,
    uint256[4] memory minAmounts 
  ) external returns(
      uint256 base0,
      uint256 base1,
      uint256 limit0,
      uint256 limit1
  );

  function addLiquidity(
      int24 tickLower,
      int24 tickUpper,
      uint256 amount0,
      uint256 amount1,
      uint256[2] memory inMin
  ) external;

  function pool() external view returns (IAlgebraPool);

  function currentTick() external view returns (int24 tick);
  
  function tickSpacing() external view returns (int24 spacing);

  function baseLower() external view returns (int24 tick);

  function baseUpper() external view returns (int24 tick);

  function limitLower() external view returns (int24 tick);

  function limitUpper() external view returns (int24 tick);

  function token0() external view returns (IERC20);

  function token1() external view returns (IERC20);

  function deposit0Max() external view returns (uint256);

  function deposit1Max() external view returns (uint256);

  function balanceOf(address) external view returns (uint256);

  function approve(address, uint256) external returns (bool);

  function transferFrom(address, address, uint256) external returns (bool);

  function transfer(address, uint256) external returns (bool);

  function getTotalAmounts() external view returns (uint256 total0, uint256 total1);
  
  function getBasePosition() external view returns (uint256 liquidity, uint256 total0, uint256 total1);

  function totalSupply() external view returns (uint256 );

  function setWhitelist(address _address) external;
  
  function setFee(uint8 newFee) external;

  function setTickSpacing(int24 newTickSpacing) external;
  
  function removeWhitelisted() external;

  function transferOwnership(address newOwner) external;

  function toggleDirectDeposit() external;

}
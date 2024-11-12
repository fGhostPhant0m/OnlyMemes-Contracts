//SPDX-License-Identifier: None

pragma solidity ^0.8.27;

import "contracts/interfaces/IUniswapV2Pair.sol";
import "contracts/interfaces/IUniswapV2Factory.sol";
import "contracts/Incentives/interfaces/IVoter.sol";
import "contracts/Incentives/interfaces/iChef.sol";

contract feeAggregator {

uint256 public feeToDAO;
uint256 public feeToBribes;
address public factory;
address public voter;
address public router;
address public chef;

mapping (address => bool) isIncentivised;
mapping (address => bool) isPair;


constructor(uint256 _feeToDao, uint256 _feeToBribes) {
feeToDAO = _feeToDao;
feeToBribes = _feeToBribes;
}
 function syncPairs() external {

 }
 function syncFarms() external {

 }

 function sendBribes() external {

 }
 function sendFees() external {

 }
}
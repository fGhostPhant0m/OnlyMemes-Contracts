//SPDX-License-Identifier: None

pragma solidity 0.8.27;


import {IERC20} from  "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
 

interface IChef {
    
     struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. RSIXs to distribute per block.
        uint256 lastRewardTime;  // Last block time that FGHSTs distribution occurs.
        uint256 accRSIXPerShare; // Accumulated rSIX per share, times 1e12. See below.
        address strategy;           //Which Protocol strategy is to be used. 
    }
    function getPID(address lp) external view returns (uint256 pid);
    function readPoolList() external view returns (IERC20[] memory );
function getPoolInfo(uint256 pid) external view returns (IERC20 _lpToken, uint256 allocPoint, uint256 lastRewardTime, uint256 accRSIXPerShare, address strategy );
      function poolLength() external view returns (uint256);
      function set(uint256 _pid, uint256 _allocPoint) external;
}
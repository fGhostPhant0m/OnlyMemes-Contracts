// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import  "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "../libraries/SafeMath.sol";  
import "./memERC20.sol";
import "./IVoter.sol";    

// The fGhost's MEMEChef is a fork of 0xDao Garden by 0xDaov1
// The biggest change made from SushiSwap is using per second instead of per block for rewards
// This is due to Fantoms extremely inconsistent block times
// The other biggest change was the removal of the migration functions
// It also has some view functions for Quality Of Life such as PoolId lookup and a query of all pool addresses.
// Note that it's ownable and the owner wields tremendous power. 
//
// Have fun reading it. Hopefully it's bug-free. 
contract GhostChef is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Only
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accOnlyPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accOnlyPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. ONLYs to distribute per block.
        uint256 lastRewardTime;  // Last block time that ONLYs distribution occurs.
        uint256 accOnlyPerShare; // Accumulated Only per share, times 1e12. See below.

    }

    // such a cool token!
    MemeToken public only;
    address multiSig;
    // Only tokens created per second.
    uint256 public immutable OnlyPerSecond;
    uint256 public feeToDAO = 10; //0.1% deposit fee
    uint256 public constant MaxAllocPoint = 4000;
    address public Voter;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    mapping (address => uint256) public poolId;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block time when Only mining starts.
    uint256 public immutable startTime;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        MemeToken _only,
        uint256 _onlyPerSecond,
        uint256 _startTime,
        address _multiSig
    ) Ownable(msg.sender){
        only = _only;
        OnlyPerSecond = _onlyPerSecond;
        startTime = _startTime;
        multiSig = _multiSig;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function checkForDuplicate(IERC20 _lpToken) internal view {
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; _pid++) {
            require(poolInfo[_pid].lpToken != _lpToken, "add: pool already exists!!!!");
        }

    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken) external onlyOwner {
        require(_allocPoint <= MaxAllocPoint, "add: too many alloc points!!");

        checkForDuplicate(_lpToken); // ensure you cant add duplicate pools

        massUpdatePools();

        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardTime: lastRewardTime,
            accOnlyPerShare: 0
        }));
        poolId[address(_lpToken)] = poolInfo.length - 1;
    }

    // Update the given pool's Only allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint) external {
        require (msg.sender == Voter, "only Voter can set");
        require(_allocPoint <= MaxAllocPoint, "add: too many alloc points!!");


        massUpdatePools();

        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }
    
    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        _from = _from > startTime ? _from : startTime;
        if (_to < startTime) {
            return 0;
        }
        return _to - _from;
    }

    // View function to see pending Onlys on frontend.
    function pendingOnly(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accOnlyPerShare = pool.accOnlyPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 OnlyReward = multiplier.mul(OnlyPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            accOnlyPerShare = accOnlyPerShare.add(OnlyReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accOnlyPerShare).div(1e12).sub(user.rewardDebt);
        }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
     uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 OnlyReward = multiplier.mul(OnlyPerSecond).mul(pool.allocPoint).div(totalAllocPoint);

        
        only.mint(address(this), OnlyReward);

        pool.accOnlyPerShare = pool.accOnlyPerShare.add(OnlyReward.mul(1e12).div(lpSupply));
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit LP tokens to MasterChef for Only allocation.
      function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        uint256 pending = user.amount.mul(pool.accOnlyPerShare).div(1e12).sub(user.rewardDebt);

        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accOnlyPerShare).div(1e12);

        if(pending > 0) {
            safeOnlyTransfer(msg.sender, pending);
        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {  
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);

  

        uint256 pending = user.amount.mul(pool.accOnlyPerShare).div(1e12).sub(user.rewardDebt);

        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accOnlyPerShare).div(1e12);

        if(pending > 0) {
            safeOnlyTransfer(msg.sender, pending);
        }
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function harvestAll() public {
        uint256 length = poolInfo.length;
        uint calc;
        uint pending;
        UserInfo storage user;
        PoolInfo storage pool;
        uint totalPending;
        for (uint256 pid = 0; pid < length; ++pid) {
            user = userInfo[pid][msg.sender];
            if (user.amount > 0) {
                pool = poolInfo[pid];
                updatePool(pid);

                calc = user.amount.mul(pool.accOnlyPerShare).div(1e12);
                pending = calc.sub(user.rewardDebt);
                user.rewardDebt = calc;

                if(pending > 0) {
                    totalPending+=pending;
                }
            }
        }
        if (totalPending > 0) {
            safeOnlyTransfer(msg.sender, totalPending);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
     
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint oldUserAmount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        pool.lpToken.safeTransfer(address(msg.sender), oldUserAmount);
        emit EmergencyWithdraw(msg.sender, _pid, oldUserAmount);

    }

    // Safe Only transfer function, just in case if rounding error causes pool to not have enough ONLYs.
    function safeOnlyTransfer(address _to, uint256 _amount) internal {
        uint256 OnlyBal = only.balanceOf(address(this));
        if (_amount > OnlyBal) {
            only.transfer(_to, OnlyBal);
        } else {
            only.transfer(_to, _amount);
        }
    }
  
    function resetAllowance(address strat, address lp) internal {
                 IERC20(lp).approve(strat, 0);
              IERC20(lp).approve(strat, type(uint).max);
    }
  
    function getPID(address lp) external view returns (uint256 pid){
        pid = poolId[lp]; 
    }
  
    function readPoolList() external view returns (IERC20[] memory ){
         uint256 length = poolInfo.length;
         IERC20 [] memory result = new IERC20 [](length);
           for (uint256 i = 0; i < length; ++i){
                result[i] = poolInfo[i].lpToken;               
           }
            return result;   
            }
    
     function getPoolInfo(uint256 pid) external view returns (IERC20 _lpToken, uint256 allocPoint, uint256 lastRewardTime, uint256 accOnlyPerShare) {
           _lpToken = poolInfo[pid].lpToken;
        allocPoint = poolInfo[pid].allocPoint;
        lastRewardTime = poolInfo[pid].lastRewardTime;
        accOnlyPerShare = poolInfo[pid].accOnlyPerShare;

        }
     function setVoter(address voter) external onlyOwner {
           require(Voter == address(0));
        Voter = voter;
     }


    }



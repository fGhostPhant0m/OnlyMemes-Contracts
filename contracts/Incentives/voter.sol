//SPDX-License-Identifier: None
 
pragma solidity 0.8.27;

import "./iChef.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import  "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/Imeme.sol";   
  
contract voter is Ownable {
      using SafeERC20 for IERC20;

        struct votes {
              uint256 pid;
              uint256 amount;
              bool claimed;

}
        struct bribeInfo {
            address reward;
            uint256 epoch;
            uint256 amount;
            uint256 claimed;
        }

address public masterChef;
address public votingToken; //Token to vote with
uint256 public lastEpoch; //block.timestamp of last epoch flip
uint256 public epochLength; //How long an epoch is in seconds
uint256 public totalWeight; // total voting weight this epoch
uint256 public Epoch; //  Current Epoch 
address [] public Bribes; //Array of whitelisted Bribes
IMeme meme = IMeme(votingToken);
IChef chef = IChef(masterChef);

mapping(address => bool) public isBribeWhitelisted;
mapping(address => uint256) public userLocks; //user -> tokens used to vote this epoch
mapping(uint256 => uint256) public voterTurnouts; // epoch -> votes
mapping(address => uint256) public lastClaim; //user -> Epoch of last claimed rewards
mapping(uint256 => mapping(uint256 => uint256)) public voteResults;  // epoch -> poolID -> votes
mapping ( uint256 => mapping(uint256 => bribeInfo[] )) public bribeRewards; // epoch -> poolID -> list of bribe rewards and amounts.
mapping(address => mapping(uint256 => votes[])) public userVotes; //user -> epoch -> votes. 

    constructor (
    address _masterChef, 
    uint256 epochInSeconds,
    address token
                ) 
    Ownable(msg.sender)
    {
    masterChef = _masterChef;
    epochLength = epochInSeconds;
    votingToken = token;
    }

function vote(uint256 pid, uint256 amount) public {
    require (votesLeft(msg.sender) <= amount);
    _lockTokens(amount, msg.sender);
    uint256 i = userVotes[msg.sender][Epoch].length;
    (bool voted, uint256 voteId) = _alreadyVoted(msg.sender, pid);
    if (!voted) {
        userVotes[msg.sender][Epoch][i] = votes(pid, amount, false);
   
    }
        else  {
            userVotes[msg.sender][Epoch][voteId].amount += amount;
      
    }
        voteResults[Epoch][pid] += amount;
        voterTurnouts[Epoch] += amount;
        totalWeight += amount;
} 

function multiVote(votes [] memory Votes) external {
    uint256 length = Votes.length;
    for (uint256 i; i < length; ++i) {
        uint256 pid = Votes[i].pid;
        uint256 amount = Votes[i].amount;
        vote(pid, amount);
    }
}

function bribe(uint256 pid, address reward, uint256 amount) external {
    require(isBribeWhitelisted[reward] == true, "Token not Whitelisted");
 (bool isBribe, uint256 farmId) = _isBribe(reward,pid,Epoch);
 if(isBribe == true){
    IERC20(reward).safeTransferFrom(msg.sender, address(this), amount);
    bribeRewards[Epoch][pid][farmId].amount += amount;

 }
  else {IERC20(reward).safeTransferFrom(msg.sender, address(this), amount);
 uint256 i = bribeRewards[Epoch][pid].length;
 bribeRewards[Epoch][pid][i] = bribeInfo(reward, Epoch, amount, 0);}
 
}


function claimEverything() external {

uint256 latestClaim = lastClaim[msg.sender] + 1; // Latest Claim available
uint256 numEpochs = Epoch - latestClaim; // How many epochs since last claim
for (uint256 i; i < numEpochs; ++i) {
 
   claimBribes(latestClaim);
  ++ latestClaim; 
}

}

function claimBribes( uint256 epoch) public {
 
 require (epoch < Epoch, "Bribe not available yet"); //You can only claim bribes after Epoch flips
 
    uint256 length = userVotes[msg.sender][epoch].length;
     for (uint256 j; j < length; ++j) {
   
     uint256 _pid = userVotes[msg.sender][epoch][j].pid;
     require (!userVotes[msg.sender][epoch][j].claimed, "Bribes already claimed");

     bribeInfo [] memory bribes = new bribeInfo [](length);

     bribes = pendingRewards(msg.sender, _pid, epoch);

     IERC20(bribes[j].reward).safeTransfer(msg.sender, bribes[j].amount);

     userVotes[msg.sender][epoch][j].claimed == true;
  }
}

function flip() public {
require (block.timestamp > lastEpoch + epochLength); //require epoch time has elapsed
//tally vote
    uint256 length = chef.poolLength();
    uint256 totalVotes = voterTurnouts[Epoch];
    uint256 maxAllocPoints = 4000 * (length -1);
//convert all votes to allocPoints
    for (uint256 i; i < length; ++i){
    uint256 votesForEpoch = voteResults[Epoch][i];
    uint256 allocPercent = votesForEpoch / totalVotes * 100;
    uint256 allocPoint = maxAllocPoints / 100 * allocPercent; 
    if (allocPoint > 4000){allocPoint = 4000;}
    //Set new allocPoints according to vote turn out
        chef.set(i, allocPoint);

    }
        ++ Epoch;
        totalWeight = 0;
        lastEpoch = block.timestamp;

}

function votesLeft(address user) public view returns(uint256 amount) {

 return IERC20(votingToken).balanceOf(user) - votesUsed(user);

}

function votesUsed(address user) public view returns(uint256 amount) {
 
 return userLocks[user];
 
}

function pendingRewards(address user, uint256 pid, uint256 epoch) public view returns(bribeInfo [] memory) {
 uint256 length = userVotes[user][epoch].length;
 bribeInfo [] memory bribes = new bribeInfo [](length);
 for (uint256 i; i < length; ++i){
  uint256 amountVoted = userVotes[user][epoch][i].amount;
    address _bribe = bribeRewards[epoch][pid][i].reward;
    uint256 totalBribes = bribeRewards[epoch][pid][i].amount;
    uint256 totalVotes = voteResults[epoch][pid];
    uint256 shares = totalBribes / totalVotes;
    uint256 amountOwed = amountVoted * shares;
    bribes[i] = bribeInfo(_bribe, epoch, amountOwed, 0);
}
return bribes;
}

function _lastEpoch() external view returns (uint256) { 
    return lastEpoch;
}

function _epochLength() external view returns(uint256) {
 return epochLength;
}

function _lockTokens(uint256 amount, address user) internal {
    userLocks[user] += amount;
    meme.lockTokens(amount, user);
}

function _isBribe(address reward, uint256 pid, uint256 epoch) internal view returns (bool isBribe, uint256 farmId) {
 for (uint256 i; i < bribeRewards[epoch][pid].length; ++ i ) {
    if (bribeRewards[epoch][pid][i].reward == reward) {
        isBribe = true; 
        farmId = i;
    }
 }
 return (isBribe, farmId);
}

function _alreadyVoted(address user, uint256 pid) internal view returns (bool voted, uint256 voteId) {
    uint256 i = userVotes[msg.sender][Epoch].length;
     for (uint256 j; j < i; ++j){
            if (pid == userVotes[user][Epoch][j].pid){
            voted = true;
            voteId = j;
            }
        }
        return (voted, voteId);
}

function _unlockTokens(address user) external {
 require (msg.sender == votingToken);
 userLocks[user] = 0;
}

function currentEpoch() external view returns (uint256) {
    return Epoch;
}

}

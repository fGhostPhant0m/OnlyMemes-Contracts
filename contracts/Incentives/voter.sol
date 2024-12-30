//SPDX-License-Identifier: None
pragma solidity 0.8.27;

import "contracts/interfaces/IChef.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "contracts/interfaces/IMeme.sol";   
import "contracts/interfaces/IOnlyMemesPair.sol";
  
contract voter is Ownable, ReentrancyGuard {
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

    uint256 public constant MAX_BRIBES_PER_POOL = 10;
    uint256 private constant MAX_ALLOC_POINTS = 4000;
    uint256 public constant MINIMUM_BRIBE_AMOUNT = 1e18; // 1 full token minimum bribe
    uint256 public constant VOTE_BUFFER_TIME = 1 hours; // Buffer before epoch can be flipped
    uint256 public constant MAX_BUFFER_TIME = 4 hours; // Maximum time buffer can be active
    uint256 public constant MAXIMUM_VOTE_AMOUNT = 42e24; // 42M tokens - reasonable max to prevent overflow

    address public immutable masterChef;
    address public immutable votingToken;
    uint256 public lastEpoch;
    uint256 public immutable epochLength;
    uint256 public totalWeight;
    uint256 public Epoch;
    uint256 public bufferStart;
    IMeme immutable meme;
    IChef immutable chef;

    mapping(address => bool) public isBribeWhitelisted;
    mapping(address => uint256) public userLocks;
    mapping(uint256 => uint256) public voterTurnouts;
    mapping(address => uint256) public lastClaim;
    mapping(uint256 => mapping(uint256 => uint256)) public voteResults;
    mapping(uint256 => mapping(uint256 => bribeInfo[])) public bribeRewards;
    mapping(address => mapping(uint256 => votes[])) public userVotes;
    mapping(uint256 => bool) public isEpochSealed;
    mapping(uint256 => bool) public isEpochFinalized;

    error InsufficientVotes();
    error BribeNotWhitelisted();
    error EpochNotEnded();
    error BribesAlreadyClaimed();
    error ZeroVotes();
    error DivisionByZero();
    error InvalidEpoch();
    error InvalidToken();
    error NotAuthorized();
    error ClaimTooEarly();
    error InvalidPid();
    error DuplicatePid();
    error Overflow(); 
    error TooManyBribes();
    error BribeTooSmall();
    error VoteAmountTooLarge();
    error BufferPeriodTooEarly();
    error BufferPeriodExpired();
    error EpochSealed();
    error BufferNotStarted();
    error NoLocksToUnlock();
    error NoClaimableEpochs();
    error EpochAlreadyFinalized();

    event BribeWhitelistUpdated(address indexed token, bool status);
    event BribeClaimed(address indexed user, uint256 indexed epoch, uint256 indexed pid, address reward, uint256 amount);
    event VoteCast(address indexed user, uint256 indexed pid, uint256 amount);
    event EpochFlipped(uint256 indexed newEpoch, uint256 timestamp);
    event BribeAdded(address indexed token, uint256 indexed pid, uint256 indexed epoch, uint256 amount);
    event ClaimSkipped(uint256 indexed epoch);
    event BufferPeriodStarted(uint256 indexed epoch, uint256 startTime);
    event EpochFinalized(uint256 indexed epoch, uint256 timestamp);

    constructor(
        address _masterChef, 
        uint256 epochLength_,
        address _token
    ) 
        Ownable(msg.sender)
    {
        require(_masterChef != address(0), "Zero address chef");
        require(_token != address(0), "Zero address token");
        require(epochLength_ > VOTE_BUFFER_TIME * 2 + 1 hours, "Epoch too short");
        
        masterChef = _masterChef;
        epochLength = epochLength_;
        votingToken = _token;
        meme = IMeme(_token);
        chef = IChef(_masterChef);
    }

    function vote(uint256 pid, uint256 amount) public {
        if (pid >= chef.poolLength()) revert InvalidPid();
        if (votesLeft(msg.sender) < amount) revert InsufficientVotes();
        if (amount > MAXIMUM_VOTE_AMOUNT) revert VoteAmountTooLarge();
        if (isEpochSealed[Epoch]) revert EpochSealed();
        if (block.timestamp >= lastEpoch + epochLength - VOTE_BUFFER_TIME) revert BufferPeriodTooEarly();
        
        _lockTokens(amount, msg.sender);
        (bool voted, uint256 voteId) = _hasVotedForEpoch(msg.sender, pid, Epoch);
        
        if (!voted) {
            userVotes[msg.sender][Epoch].push(votes(pid, amount, false));
        } else {
            uint256 newTotal = userVotes[msg.sender][Epoch][voteId].amount + amount;
            if (newTotal > MAXIMUM_VOTE_AMOUNT) revert VoteAmountTooLarge();
            userVotes[msg.sender][Epoch][voteId].amount = newTotal;
        }
        
        voteResults[Epoch][pid] += amount;
        voterTurnouts[Epoch] += amount;
        totalWeight += amount;

        emit VoteCast(msg.sender, pid, amount);
    }

    function multiVote(votes[] calldata Votes) external {
        uint256 length = Votes.length;
        uint256 poolLength = chef.poolLength();
        bool[] memory seenPids = new bool[](poolLength);
        
        for (uint256 i; i < length; ++i) {
            uint256 pid = Votes[i].pid;
            if (pid >= poolLength) revert InvalidPid();
            if (seenPids[pid]) revert DuplicatePid();
            seenPids[pid] = true;
            vote(pid, Votes[i].amount);
        }
    }

    function bribe(uint256 pid, address reward, uint256 amount) external {
        if (!isBribeWhitelisted[reward]) revert BribeNotWhitelisted();
        if (pid >= chef.poolLength()) revert InvalidPid();
        if (amount < MINIMUM_BRIBE_AMOUNT) revert BribeTooSmall();
        if (isEpochSealed[Epoch]) revert EpochSealed();
        
        (bool isBribe, uint256 farmId) = _isBribe(reward, pid, Epoch);
        if (!isBribe && bribeRewards[Epoch][pid].length >= MAX_BRIBES_PER_POOL) {
            revert TooManyBribes();
        }
        
        IERC20(reward).safeTransferFrom(msg.sender, address(this), amount);
        
        if (isBribe) {
            bribeRewards[Epoch][pid][farmId].amount += amount;
        } else {
            bribeRewards[Epoch][pid].push(bribeInfo(reward, Epoch, amount, 0));
        }

        emit BribeAdded(reward, pid, Epoch, amount);
    }

    function startBuffer() external {
        if (block.timestamp < lastEpoch + epochLength - VOTE_BUFFER_TIME) revert BufferPeriodTooEarly();
        if (block.timestamp > lastEpoch + epochLength) revert BufferPeriodExpired();
        if (isEpochSealed[Epoch]) revert EpochSealed();

        isEpochSealed[Epoch] = true;
        bufferStart = block.timestamp;
        
        emit BufferPeriodStarted(Epoch, block.timestamp);
    }

    function flip() external {
        if (!isEpochSealed[Epoch]) revert EpochNotEnded();
        if (isEpochFinalized[Epoch]) revert EpochAlreadyFinalized();
        if (block.timestamp < bufferStart + VOTE_BUFFER_TIME) revert BufferPeriodTooEarly();
        if (block.timestamp > bufferStart + MAX_BUFFER_TIME) revert BufferPeriodExpired();
        if (bufferStart == 0) revert BufferNotStarted();
        
        uint256 length = chef.poolLength();
        if (length == 0) revert InvalidPid();
        
        uint256 totalVotes = voterTurnouts[Epoch];
        if (totalVotes == 0) revert ZeroVotes();
        
        // Safe math for allocation points
        for (uint256 i; i < length; ++i) {
            uint256 votesForEpoch = voteResults[Epoch][i];
            uint256 allocPoint;
            if (votesForEpoch > 0) {
                allocPoint = (votesForEpoch * MAX_ALLOC_POINTS) / totalVotes;
                if (allocPoint > MAX_ALLOC_POINTS) {
                    allocPoint = MAX_ALLOC_POINTS;
                }
            }
            chef.set(i, allocPoint);
        }
        
        isEpochFinalized[Epoch] = true;
        emit EpochFinalized(Epoch, block.timestamp);
        
        uint256 newEpoch = Epoch + 1;
        Epoch = newEpoch;
        totalWeight = 0;
        lastEpoch = block.timestamp;
        bufferStart = 0;

        emit EpochFlipped(newEpoch, block.timestamp);
    }

    function claimEverything() external nonReentrant {
        uint256 latestClaim = lastClaim[msg.sender];
        if (latestClaim >= Epoch) revert ClaimTooEarly();
        
        uint256 claimStart = latestClaim + 1;
        uint256 claimEnd = Epoch;
        
        if (claimStart >= claimEnd) revert NoClaimableEpochs();

        for (uint256 epochToClaim = claimStart; epochToClaim < claimEnd; epochToClaim++) {
            if (!isEpochFinalized[epochToClaim]) {
                emit ClaimSkipped(epochToClaim);
                continue;
            }

            uint256 length = userVotes[msg.sender][epochToClaim].length;
            bool hasUnclaimedVotes = false;
            
            for (uint256 i = 0; i < length; i++) {
                if (!userVotes[msg.sender][epochToClaim][i].claimed) {
                    hasUnclaimedVotes = true;
                    break;
                }
            }
            
            if (hasUnclaimedVotes) {
                _claimBribesForEpoch(epochToClaim);
            } else {
                emit ClaimSkipped(epochToClaim);
            }
        }
        
        lastClaim[msg.sender] = claimEnd - 1;
    }

    function claimBribes(uint256 epoch) public nonReentrant {
        if (epoch >= Epoch) revert EpochNotEnded();
        if (!isEpochFinalized[epoch]) revert EpochNotEnded();
        _claimBribesForEpoch(epoch);
    }

    function setWhitelistedBribe(address token, bool status) external onlyWhitelister {
        if (token == address(0)) revert InvalidEpoch();
        isBribeWhitelisted[token] = status;
        emit BribeWhitelistUpdated(token, status);
    }

    function votesLeft(address user) public view returns(uint256) {
        return IERC20(votingToken).balanceOf(user) - votesUsed(user);
    }

    function votesUsed(address user) public view returns(uint256) {
        return userLocks[user];
    }

    function pendingRewards(address user, uint256 pid, uint256 epoch) public view returns(bribeInfo[] memory) {
        uint256 bribeLength = bribeRewards[epoch][pid].length;
        bribeInfo[] memory bribes = new bribeInfo[](bribeLength);
        
        uint256 totalVotes = voteResults[epoch][pid];
        if (totalVotes == 0) return bribes;
        
        uint256 amountVoted;
        (bool voted, uint256 voteId) = _hasVotedForEpoch(user, pid, epoch);
        if (voted) {
            amountVoted = userVotes[user][epoch][voteId].amount;
        }
        
        for (uint256 i; i < bribeLength; ++i) {
            bribeInfo storage _bribe = bribeRewards[epoch][pid][i];
            uint256 unclaimedBribes = _bribe.amount - _bribe.claimed;
            if (unclaimedBribes > 0) {
                // Check for overflow in multiplication
                uint256 numerator = amountVoted * unclaimedBribes;
                if (numerator / amountVoted != unclaimedBribes) revert Overflow();
                
                uint256 amountOwed = numerator / totalVotes;
                bribes[i] = bribeInfo(_bribe.reward, epoch, amountOwed, 0);
            }
        }
        
        return bribes;
    }

    function _claimBribesForEpoch(uint256 epoch) internal {
        uint256 length = userVotes[msg.sender][epoch].length;
        for (uint256 j; j < length; ++j) {
            if (userVotes[msg.sender][epoch][j].claimed) revert BribesAlreadyClaimed();
            
            uint256 _pid = userVotes[msg.sender][epoch][j].pid;
            bribeInfo[] memory bribes = pendingRewards(msg.sender, _pid, epoch);
            
            // Mark as claimed before external calls
            userVotes[msg.sender][epoch][j].claimed = true;
            
            uint256 bribeLength = bribes.length;
            for (uint256 k; k < bribeLength; ++k) {
                if (bribes[k].amount > 0) {
                    // Update claimed amount in storage
                    bribeRewards[epoch][_pid][k].claimed += bribes[k].amount;
                    // Transfer rewards
                    IERC20(bribes[k].reward).safeTransfer(msg.sender, bribes[k].amount);
                    emit BribeClaimed(msg.sender, epoch, _pid, bribes[k].reward, bribes[k].amount);
                }
            }
        }
        
        lastClaim[msg.sender] = epoch;
    }

    function _hasVotedForEpoch(address user, uint256 pid, uint256 epoch) internal view returns (bool voted, uint256 voteId) {
        uint256 length = userVotes[user][epoch].length;
        for (uint256 j; j < length; ++j) {
            if (pid == userVotes[user][epoch][j].pid) {
                return (true, j);
            }
        }
        return (false, 0);
    }

    function _lockTokens(uint256 amount, address user) internal {
        userLocks[user] += amount;
        meme.lockTokens(amount, user);
    }

    function _isBribe(address reward, uint256 pid, uint256 epoch) internal view returns (bool isBribe, uint256 farmId) {
        uint256 length = bribeRewards[epoch][pid].length;
        for (uint256 i; i < length; ++i) {
            if (bribeRewards[epoch][pid][i].reward == reward) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    function _unlockTokens(address user) external {
        if (msg.sender != votingToken) revert NotAuthorized();
        uint256 currentLocks = userLocks[user];
        if (currentLocks == 0) revert NoLocksToUnlock();
        userLocks[user] = 0;
    }
    
    function getPID(address lp) public returns (uint256 _pid){
         return chef.getPID(lp);
    } 

    function _epochLength() external view returns(uint256) {
        return epochLength;
    }

    function _lastEpoch() external view returns (uint256){
        return lastEpoch;
    }

    modifier onlyWhitelister() {
        address _owner = owner();
        require (msg.sender == _owner || msg.sender == masterChef , "Not Approved to Whitelist");
        _;
    }
}
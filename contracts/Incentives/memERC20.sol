//SPDX-License-Identifier: None

pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IVoter.sol";

contract MemeToken is ERC20, Ownable {

    uint256 internal _totalSupply;
    uint256 internal _maxSupply;
    address public Voter;
    mapping (address => uint256) public amountLocked;
    IVoter voter = IVoter(Voter);

    constructor(uint256 initialSupply, uint256 maximumSupply)ERC20("Only Memes", "ONLY")Ownable(msg.sender){
        _totalSupply = initialSupply;
        _maxSupply = maximumSupply;
        _mint(msg.sender, initialSupply);
    }

     function totalSupply() public view override returns (uint256) {
        return _totalSupply - balanceOf(address(0));
    }

    function mint( address account, uint256 amount) external onlyOwner {
        
            uint256 _maxMint = _maxSupply - totalSupply();
     
          if (amount > _maxMint){ 
             amount = _maxMint; }
 
             _mint(account, amount);
             _totalSupply += amount;
    }

    function burn(uint256 amount) external {
        _totalSupply -= amount; 
        _burn(msg.sender, amount);
  
    }

    function maxSupply() external view returns (uint256) {
        return _maxSupply;
    }
    
    function setVoter(address _voter) external onlyOwner{
        require(Voter == address(0));
        Voter = _voter;
 }
 function lockTokens(uint256 amount, address user) external {
require (msg.sender == Voter, "only Voter can lock");
require (amount + amountLocked[user] <= balanceOf(user), "Fully Locked");
amountLocked[user] += amount;

 }

 function transfer(address to, uint256 value) public override returns (bool) {
        address owner = _msgSender();
        if (Voter != address(0) && block.timestamp > voter._lastEpoch() + voter._epochLength()) {
                    voter._unlockTokens(owner);
                    _transfer(owner, to, value); 
        return true;
        }
        else {
         require (value <= balanceOf(owner) - amountLocked[owner], "Value exceeds unlocked balance");
        _transfer(owner, to, value);
        return true; 
        }

    }
  function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        address spender = _msgSender();
        if (Voter != address(0) && block.timestamp > voter._lastEpoch() + voter._epochLength()) {
             voter._unlockTokens(spender);
              _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
        }
        else {
        require (value <= balanceOf(from) - amountLocked[from], "Value exceeds unlocked balance");
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
         }
    }
 } 



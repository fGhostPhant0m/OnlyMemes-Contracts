// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IOnlyMemesPair} from "./interfaces/IOnlyMemesPair.sol";
import {OnlyMemesERC20} from "./OnlyMemesERC20.sol";
import {Math} from "./libraries/Math.sol";
import {UQ112x112} from "./libraries/UQ112x112.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import "contracts/interfaces/IOnlyMemesCallee.sol";
import "contracts/interfaces/IOnlyMemesFactory.sol";
import "contracts/interfaces/IVoter.sol";



contract OnlyMemesPair is IOnlyMemesPair, OnlyMemesERC20 {
    using UQ112x112 for uint224;

    uint256 public constant override MINIMUM_LIQUIDITY = 10**3;
    
    address public override factory;
    address public override token0;
    address public override token1;
    IVoter public voter;
    address public multisig;
    address public chef;
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;
    uint256 private Pid;
    uint256 public override price0CumulativeLast;
    uint256 public override price1CumulativeLast;
    uint256 public override kLast;
    

    uint256 private unlocked = 1;
    
    error AddressNotSet();
    error CalculationOverflow();

    modifier lock() {
        require(unlocked == 1, "OnlyMemes: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    constructor() {
        factory = msg.sender;
    }

    function setFeeAddresses(IVoter _voter, address _multisig, address _chef) external {
        require(msg.sender == factory, "OnlyMemes: FORBIDDEN");
        require(address(_voter) != address(0) && _multisig != address(0), "OnlyMemes: ZERO_ADDRESS");
        voter = _voter;
        multisig = _multisig;
        chef = _chef;
    }

    function getReserves() public view override returns (
        uint112 _reserve0,
        uint112 _reserve1,
        uint32 _blockTimestampLast
    ) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "OnlyMemes: TRANSFER_FAILED"
        );
    }

    function initialize(address _token0, address _token1) external override {
        require(msg.sender == factory, "OnlyMemes: FORBIDDEN");
        token0 = _token0; 
        token1 = _token1;
    }

    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) private {
        require(
            balance0 <= type(uint112).max && balance1 <= type(uint112).max,
            "OnlyMemes: OVERFLOW"
        );
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        unchecked {
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;
            if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
                price0CumulativeLast += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
                price1CumulativeLast += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
            }
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    function calculateTokenAmount(
        uint256 reserve,
        uint256 share,
        uint256 _totalSupply
    ) external pure returns (uint256) {
        return (share * reserve) / _totalSupply;
    }

   function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IOnlyMemesFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast;
        
        if (feeOn) {
            if (_kLast != 0) {
                if (address(voter) == address(0) || multisig == address(0)) revert AddressNotSet();
                
                uint256 rootK = Math.sqrt(uint256(_reserve0) * _reserve1);
                uint256 rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply * (rootK - rootKLast);
                    uint256 denominator = rootK + rootKLast;
                    uint256 totalLiquidity = numerator / denominator;
                    
                    if (totalLiquidity > 0) {
                        bool isWhitelisted = voter.isBribeWhitelisted(address(this));
                        uint256 voterShare = (totalLiquidity * 30) / 100;
                        uint256 multisigShare = (totalLiquidity * 5) / 100;
                        uint256 lpShare = isWhitelisted ? 
                            (totalLiquidity * 15) / 100 : 
                            (totalLiquidity * 45) / 100; // 15% base + 30% from voter share
                        
                        // Only bribe if whitelisted
                        if (isWhitelisted) {
                            try this.calculateTokenAmount(_reserve0, voterShare, totalSupply) returns (uint256 amount0Voter) {
                                try this.calculateTokenAmount(_reserve1, voterShare, totalSupply) returns (uint256 amount1Voter) {
                                    _safeApprove(token0, address(voter), amount0Voter);
                                    _safeApprove(token1, address(voter), amount1Voter);
                                    voter.bribe(Pid, token0, amount0Voter);
                                    voter.bribe(Pid, token1, amount1Voter);
                                } catch {
                                    revert CalculationOverflow();
                                }
                            } catch {
                                revert CalculationOverflow();
                            }
                        }
                        
                        // Calculate and transfer multisig share
                        try this.calculateTokenAmount(_reserve0, multisigShare, totalSupply) returns (uint256 amount0Multisig) {
                            try this.calculateTokenAmount(_reserve1, multisigShare, totalSupply) returns (uint256 amount1Multisig) {
                                _safeTransfer(token0, multisig, amount0Multisig);
                                _safeTransfer(token1, multisig, amount1Multisig);
                            } catch {
                                revert CalculationOverflow();
                            }
                        } catch {
                            revert CalculationOverflow();
                        }
                        
                        // Mint LP to multisig
                        if (lpShare > 0) _mint(multisig, lpShare);
                        
                        // Update reserves to match new balances after transfers
                        _update(
                            IERC20(token0).balanceOf(address(this)),
                            IERC20(token1).balanceOf(address(this)),
                            reserve0,
                            reserve1
                        );
                    }
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    function mint(address to) external override lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min(
                (amount0 * _totalSupply) / _reserve0,
                (amount1 * _totalSupply) / _reserve1
            );
        }
        require(liquidity > 0, "OnlyMemes: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * reserve1;
        emit Mint(msg.sender, amount0, amount1);
    }

    function burn(address to) external override lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        address _token0 = token0;
        address _token1 = token1;
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply;
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;
        require(
            amount0 > 0 && amount1 > 0,
            "OnlyMemes: INSUFFICIENT_LIQUIDITY_BURNED"
        );
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * reserve1;
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(
    uint256 amount0Out,
    uint256 amount1Out,
    address to,
    bytes calldata data
) external override lock { 
    require(amount0Out > 0 || amount1Out > 0, "OnlyMemes: INSUFFICIENT_OUTPUT_AMOUNT");
    (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
    require(amount0Out < _reserve0 && amount1Out < _reserve1, "OnlyMemes: INSUFFICIENT_LIQUIDITY");

    uint256 balance0;
    uint256 balance1;
    { // scope for _token{0,1}, avoids stack too deep errors
        address _token0 = token0;
        address _token1 = token1;
        require(to != _token0 && to != _token1, "OnlyMemes: INVALID_TO");
        if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out);
        if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out);
        if (data.length > 0) IOnlyMemesCallee(to).OnlyMemesCall(msg.sender, amount0Out, amount1Out, data);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
    }
    uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
    uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
    require(amount0In > 0 ||  amount1In > 0, "OnlyMemes: INSUFFICIENT_INPUT_AMOUNT");
    { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        require(
            amount0In * 99 * _reserve1 >= amount1Out * 100 * _reserve0 &&
            amount1In * 99 * _reserve0 >= amount0Out * 100 * _reserve1,
            "OnlyMemes: K"
        );
    }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

     function _safeApprove(address token, address spender, uint256 value) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.approve.selector, spender, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "OnlyMemes: APPROVE_FAILED"
        );
    }


    function skim(address to) external override lock {
        address _token0 = token0;
        address _token1 = token1;
        _safeTransfer(
            _token0,
            to,
            IERC20(_token0).balanceOf(address(this)) - reserve0
        );
        _safeTransfer(
            _token1,
            to,
            IERC20(_token1).balanceOf(address(this)) - reserve1
        );
    }

    function sync() external override lock {
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );
    }
    function setPID(uint256 pid) external {
        require (msg.sender == chef);
        Pid = pid;
    }
}
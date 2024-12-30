// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IOnlyMemesFactory} from "./interfaces/IOnlyMemesFactory.sol";
import {IOnlyMemesPair} from "./interfaces/IOnlyMemesPair.sol";
import {OnlyMemesPair} from "./OnlyMemesPair.sol";
import {IVoter} from "./interfaces/IVoter.sol";

contract OnlyMemesFactory is IOnlyMemesFactory {
    bytes32 public constant PAIR_HASH = keccak256(type(OnlyMemesPair).creationCode);

    address public override feeTo;
    address public override feeToSetter;
    address public immutable multisig;
    IVoter public immutable voter;
    address public immutable chef;

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;

    constructor(
        address _feeToSetter,
        IVoter _voter,
        address _multisig,
        address _chef
    ) {
        require(_feeToSetter != address(0), "OnlyMemes: ZERO_ADDRESS");
        require(address(_voter) != address(0), "OnlyMemes: ZERO_VOTER");
        require(_multisig != address(0), "OnlyMemes: ZERO_MULTISIG");
        
        feeToSetter = _feeToSetter;
        voter = _voter;
        multisig = _multisig;
        chef = _chef;
    }

    function allPairsLength() external view override returns (uint256) {
        return allPairs.length;
    }

    function createPair(
        address tokenA,
        address tokenB
    ) external override returns (address pair) {
        require(tokenA != tokenB, "OnlyMemes: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "OnlyMemes: ZERO_ADDRESS");
        require(
            getPair[token0][token1] == address(0),
            "OnlyMemes: PAIR_EXISTS"
        );

        pair = address(
            new OnlyMemesPair{
                salt: keccak256(abi.encodePacked(token0, token1))
            }()
        );
        
        IOnlyMemesPair(pair).initialize(token0, token1);
        IOnlyMemesPair(pair).setFeeAddresses(voter, multisig, chef);
        
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external override {
        require(msg.sender == feeToSetter, "OnlyMemes: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external override {
        require(msg.sender == feeToSetter, "OnlyMemes: FORBIDDEN");
        require(_feeToSetter != address(0), "OnlyMemes: ZERO_ADDRESS");
        feeToSetter = _feeToSetter;
    }
}
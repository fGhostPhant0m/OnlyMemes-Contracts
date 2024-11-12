// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {UniswapV2Pair} from "./UniswapV2Pair.sol";

contract UniswapV2Factory is IUniswapV2Factory {
    bytes32 public constant PAIR_HASH =
        keccak256(type(UniswapV2Pair).creationCode);

    address public override feeTo;
    address public override feeToSetter;
    uint8 _totalFee;
    uint8 _feesForSetter;

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view override returns (uint256) {
        return allPairs.length;
    }

       function createPair(
        address tokenA,
        address tokenB,
        uint8 totalFee,
        uint8 _feeToSetter
    ) external override returns (address pair) {
        require(tokenA != tokenB, "UniswapV2: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2: ZERO_ADDRESS");
        require(
            getPair[token0][token1] == address(0),
            "UniswapV2: PAIR_EXISTS"
        ); // single check is sufficient

pair = address
(new UniswapV2Pair{
    salt: keccak256(abi.encodePacked(token0, token1))
    } (totalFee,_feeToSetter));

        IUniswapV2Pair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external override {
        require(msg.sender == feeToSetter, "UniswapV2: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external override {
        require(msg.sender == feeToSetter, "UniswapV2: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }

    function getAllPairs() external view returns (address [] memory) {
        return allPairs; 
    }

}

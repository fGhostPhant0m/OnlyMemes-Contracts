//SPDX-License-Identifier: None

pragma solidity 0.8.27;

interface IMeme {
    function lockTokens(uint256 amount, address user) external;
}
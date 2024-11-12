//SPDX-License-Identifier: None

pragma solidity 0.8.27;

interface IVoter {
    function _lastEpoch() external view returns (uint256);

    function _epochLength() external view returns(uint256);

    function _unlockTokens(address user) external;
}
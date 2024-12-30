// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IVoter {
    function isBribeWhitelisted(address token) external view returns (bool);
    function setWhitelistedBribe(address token, bool status) external;
    function bribe(uint256 pid, address reward, uint256 amount) external;
    function _lastEpoch() external view returns (uint256);
    function _epochLength() external view returns(uint256);
    function _unlockTokens(address owner) external;
}
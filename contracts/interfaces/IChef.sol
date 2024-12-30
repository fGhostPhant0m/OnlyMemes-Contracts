// SPDX-License-Identifier: None
pragma solidity 0.8.27;

interface IChef {
    /**
     * @notice Get the total number of pools in the chef contract
     * @return Number of pools
     */
    function poolLength() external view returns (uint256);

    /**
     * @notice Set the allocation points for a pool
     * @param pid Pool ID to modify
     * @param allocPoint New allocation points for the pool
     */
    function set(uint256 pid, uint256 allocPoint) external;

    function getPID(address lp) external returns (uint256 pid);
}
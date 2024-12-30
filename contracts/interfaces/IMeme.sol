// SPDX-License-Identifier: None
pragma solidity 0.8.27;

interface IMeme {
    /**
     * @notice Lock tokens for voting
     * @param amount Amount of tokens to lock
     * @param user Address of the user whose tokens are being locked
     */
    function lockTokens(uint256 amount, address user) external;

    /**
     * @notice Get the balance of tokens for a user
     * @param account Address of the user to check balance for
     * @return The token balance of the given account
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice Check if tokens are currently locked for a user
     * @param user Address of the user to check locks for
     * @return Boolean indicating if user has locked tokens
     */
    function isLocked(address user) external view returns (bool);

    /**
     * @notice Transfer tokens from one address to another
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param amount Amount of tokens to transfer
     * @return Boolean indicating if the transfer was successful
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /**
     * @notice Transfer tokens to another address
     * @param to Address to transfer to
     * @param amount Amount of tokens to transfer
     * @return Boolean indicating if the transfer was successful
     */
    function transfer(address to, uint256 amount) external returns (bool);
}
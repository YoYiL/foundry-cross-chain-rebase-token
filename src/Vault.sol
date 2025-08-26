// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol"; // Added later, shown for context

contract Vault {
    /* --------------------------------- errors --------------------------------- */
    error Vault_RedeemFailed();
    error Vault_DepositAmountIsZero(); // Added for deposit check
    /* ----------------------------- State variables ---------------------------- */

    IRebaseToken private immutable i_rebaseToken; // Type will be interface

    /* --------------------------------- Events --------------------------------- */
    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    /* -------------------------------------------------------------------------- */
    /*                                  Modifiers                                 */
    /* -------------------------------------------------------------------------- */

    /* -------------------------------------------------------------------------- */
    /*                                  Functions                                 */
    /* -------------------------------------------------------------------------- */
    constructor(IRebaseToken _rebaseToken) {
        // Parameter type will be interface
        i_rebaseToken = _rebaseToken;
    }

    /* -------------------------------------------------------------------------- */
    /*                             External Functions                             */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Fallback function to accept ETH rewards sent directly to the contract.
     * @dev Any ETH sent to this contract's address without data will be accepted.
     */
    receive() external payable {}

    /**
     * @notice Allows a user to deposit ETH and receive an equivalent amount of RebaseTokens.
     * @dev The amount of ETH sent with the transaction (msg.value) determines the amount of tokens minted.
     * Assumes a 1:1 peg for ETH to RebaseToken for simplicity in this version.
     */
    function deposit() external payable {
        // The amount of ETH sent is msg.value
        // The user making the call is msg.sender
        uint256 amountToMint = msg.value;

        // Ensure some ETH is actually sent
        if (amountToMint == 0) {
            revert Vault_DepositAmountIsZero(); // Consider adding a custom error
        }
        uint256 interestRate = i_rebaseToken.getInterestRate();

        // Call the mint function on the RebaseToken contract
        i_rebaseToken.mint(msg.sender, amountToMint, interestRate);

        // Emit an event to log the deposit
        emit Deposit(msg.sender, amountToMint);
    }

    /**
     * @notice Allows a user to burn their RebaseTokens and receive a corresponding amount of ETH.
     * @param _amount The amount of RebaseTokens to redeem.
     * @dev Follows Checks-Effects-Interactions pattern. Uses low-level .call for ETH transfer.
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        // 1. Effects (State changes occur first)
        // Burn the specified amount of tokens from the caller (msg.sender)
        // The RebaseToken's burn function should handle checks for sufficient balance.
        i_rebaseToken.burn(msg.sender, _amount);
        // 2. Interactions (External calls / ETH transfer last)
        // Send the equivalent amount of ETH back to the user
        (bool success,) = payable(msg.sender).call{value: _amount}("");

        // Check if the ETH transfer succeeded
        if (!success) {
            revert Vault_RedeemFailed(); // Use the custom error
        }

        // Emit an event logging the redemption
        emit Redeem(msg.sender, _amount);
    }
    /* -------------------------------------------------------------------------- */
    /*                              Public Functions                              */
    /* -------------------------------------------------------------------------- */

    /* -------------------------------------------------------------------------- */
    /*                             Internal Functions                             */
    /* -------------------------------------------------------------------------- */

    /* -------------------------------------------------------------------------- */
    /*                              Private Funtions                              */
    /* -------------------------------------------------------------------------- */

    /* -------------------------------------------------------------------------- */
    /*                  internal & private view & pure functions                  */
    /* -------------------------------------------------------------------------- */

    /* -------------------------------------------------------------------------- */
    /*                   external & public view & pure functions                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Gets the address of the RebaseToken contract associated with this vault.
     * @return The address of the RebaseToken.
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken); // Cast to address for return
    }
}

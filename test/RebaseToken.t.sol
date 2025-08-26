// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {console} from "forge-std/console.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    uint256 public constant SEND_VALUE = 100 ether;

    function addRewardsToVault(uint256 amount) public {
        // send some rewards to the vault using the receive function
        payable(address(vault)).call{value: amount}("");
    }

    // Setup function and test functions will follow
    function setUp() public {
        // Impersonate the 'owner' address for deployments and role granting
        vm.startPrank(owner);
        vm.deal(owner, 10 ether);

        // console2.log("owner address balance:", owner.balance);
        // console2.log("user address balance:", user.balance);
        // console2.log("Test address balance", address(this).balance);
        rebaseToken = new RebaseToken();

        // Deploy Vault: requires IRebaseToken.
        // Direct casting (IRebaseToken(rebaseToken)) is invalid.
        // Correct way: cast rebaseToken to address, then to IRebaseToken.
        vault = new Vault(IRebaseToken(address(rebaseToken)));

        // Grant the MINT_AND_BURN_ROLE to the Vault contract.
        // The grantMintAndBurnRole function expects an address.
        rebaseToken.grantMintAndBurnRole(address(vault));

        // Send 1 ETH to the Vault to simulate initial funds.
        // The target address must be cast to 'payable'.
        (bool success,) = payable(address(vault)).call{value: 1 ether}("");

        // console2.log("Transfer 1 ether to Vault:", success);
        require(success, "ETH transfer to vault failed");
        // It's good practice to handle the success flag, though omitted for brevity here.

        // Stop impersonating the 'owner'
        vm.stopPrank();
    }

    // Test if interest accrues linearly after a deposit.
    // 'amount' will be a fuzzed input.
    function testDepositLinear(uint256 amount) public {
        console2.log("owner address balance:", owner.balance);
        console.log("user address balance:", user.balance);
        // Constrain the fuzzed 'amount' to a practical range.
        // Min: 0.00001 ETH (1e5 wei), Max: type(uint96).max to avoid overflows.
        amount = bound(amount, 1e5, type(uint96).max);

        // 1. User deposits 'amount' ETH
        vm.startPrank(user); // Actions performed as 'user'
        vm.deal(user, amount); // Give 'user' the 'amount' of ETH to deposit

        // TODO: Implement deposit logic:
        vault.deposit{value: amount}(); // Example

        // 2. TODO: Check initial rebase token balance for 'user'
        uint256 initialBalance = rebaseToken.balanceOf(user);

        // 3. TODO: Warp time forward and check balance again
        uint256 timeDelta = 1 days; // Example
        vm.warp(block.timestamp + timeDelta);
        uint256 balanceAfterFirstWarp = rebaseToken.balanceOf(user);
        uint256 interestFirstPeriod = balanceAfterFirstWarp - initialBalance;
        // 4. TODO: Warp time forward by the same amount and check balance again
        vm.warp(block.timestamp + timeDelta); // Warp by another 'timeDelta'
        uint256 balanceAfterSecondWarp = rebaseToken.balanceOf(user);
        uint256 interestSecondPeriod = balanceAfterSecondWarp - balanceAfterFirstWarp;

        // TODO: Assert that interestFirstPeriod == interestSecondPeriod for linear accrual.
        assertApproxEqAbs(interestFirstPeriod, interestSecondPeriod, 1);

        vm.stopPrank(); // Stop impersonating 'user'
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        // Deposit funds
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        // Redeem funds
        vault.redeem(amount);

        uint256 balance = rebaseToken.balanceOf(user);
        console2.log("User balance2:", balance);
        console.log("User balance1:", balance);
        assertEq(balance, 0);
        assertEq(address(user).balance, amount);
        vm.stopPrank();
    }

    function testRedeemAfterTimeHasPassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max); // this is a crazy number of years - 2^96 seconds is a lot
        depositAmount = bound(depositAmount, 1e5, type(uint96).max); // this is an Ether value of max 2^78 which is crazy

        // Deposit funds
        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();

        // check the balance has increased after some time has passed
        vm.warp(time);

        // Get balance after time has passed
        uint256 balance = rebaseToken.balanceOf(user);

        // Add rewards to the vault
        vm.deal(owner, balance - depositAmount);
        vm.prank(owner);
        addRewardsToVault(balance - depositAmount);

        // Redeem funds
        vm.prank(user);
        vault.redeem(balance);

        uint256 ethBalance = address(user).balance;

        assertEq(balance, ethBalance);
        assertGt(balance, depositAmount);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e3, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e3);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address userTwo = makeAddr("userTwo");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 userTwoBalance = rebaseToken.balanceOf(userTwo);
        assertEq(userBalance, amount);
        assertEq(userTwoBalance, 0);

        // Update the interest rate so we can check the user interest rates are different after transferring.
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // Send half the balance to another user
        vm.prank(user);
        rebaseToken.transfer(userTwo, amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 userTwoBalancAfterTransfer = rebaseToken.balanceOf(userTwo);
        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(userTwoBalancAfterTransfer, userTwoBalance + amountToSend);
        // After some time has passed, check the balance of the two users has increased
        vm.warp(block.timestamp + 1 days);
        uint256 userBalanceAfterWarp = rebaseToken.balanceOf(user);
        uint256 userTwoBalanceAfterWarp = rebaseToken.balanceOf(userTwo);
        // check their interest rates are as expected
        // since user two hadn't minted before, their interest rate should be the same as in the contract
        uint256 userTwoInterestRate = rebaseToken.getUserInterestRate(userTwo);
        assertEq(userTwoInterestRate, 5e10);
        // since user had minted before, their interest rate should be the previous interest rate
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        assertEq(userInterestRate, 5e10);

        assertGt(userBalanceAfterWarp, userBalanceAfterTransfer);
        assertGt(userTwoBalanceAfterWarp, userTwoBalancAfterTransfer);
    }

    function testCannotSetInterestRate(uint256 newInterestRate) public {
        // Update the interest rate
        vm.startPrank(user);
        vm.expectRevert();
        rebaseToken.setInterestRate(newInterestRate);
        vm.stopPrank();
    }

    function testCannotCallMint() public {
        // Deposit funds
        vm.startPrank(user);
        uint256 interestRate = rebaseToken.getInterestRate();
        vm.expectRevert();
        rebaseToken.mint(user, SEND_VALUE, interestRate);
        vm.stopPrank();
    }

    function testCannotCallBurn() public {
        // Deposit funds
        vm.startPrank(user);
        vm.expectRevert();
        rebaseToken.burn(user, SEND_VALUE);
        vm.stopPrank();
    }

    function testCannotWithdrawMoreThanBalance() public {
        // Deposit funds
        vm.startPrank(user);
        vm.deal(user, SEND_VALUE);
        vault.deposit{value: SEND_VALUE}();
        vm.expectRevert();
        vault.redeem(SEND_VALUE + 1);
        vm.stopPrank();
    }

    function testGetPrincipleAmount() public {
        uint256 amount = 1e5;
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        uint256 principleAmount = rebaseToken.principalBalanceOf(user);
        assertEq(principleAmount, amount);

        // check that the principle amount is the same after some time has passed
        vm.warp(block.timestamp + 1 days);
        uint256 principleAmountAfterWarp = rebaseToken.principalBalanceOf(user);
        assertEq(principleAmountAfterWarp, amount);
    }

    function testGetRebaseTokenAddress() public {
        // Check that the Vault contract has the correct RebaseToken address
        address rebaseTokenAddress = address(vault.getRebaseTokenAddress());
        assertEq(rebaseTokenAddress, address(rebaseToken));
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);
        vm.prank(owner);
        //vm.expectPartialRevert(bytes4(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector));
        vm.expectRevert();
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }
}

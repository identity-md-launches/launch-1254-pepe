// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Pepe} from "../src/Pepe.sol";

/// @dev Complements Pepe.t.sol with approval transitions and failure/retry properties.
/// forge-config: default.fuzz.runs = 1024
contract PepeEdgeTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Pepe private token;
    address private holder;
    address private recipient;
    address private spender;
    address private otherSpender;

    function setUp() public {
        token = new Pepe();
        holder = makeAddr("edge holder");
        recipient = makeAddr("edge recipient");
        spender = makeAddr("edge spender");
        otherSpender = makeAddr("edge other spender");
    }

    function test_HolderUsingTransferFromStillNeedsSelfApproval() public {
        token.transfer(holder, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, holder, 0, 1));
        vm.prank(holder);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.balanceOf(holder), 2);
        assertEq(token.balanceOf(recipient), 0);

        vm.startPrank(holder);
        assertTrue(token.approve(holder, 1));
        assertTrue(token.transferFrom(holder, recipient, 1));
        vm.stopPrank();
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.allowance(holder, holder), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaxMinusOneAllowanceIsFinite() public {
        uint256 approved = type(uint256).max - 1;
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumDelegatedTransferCannotOverdrawAnUnlimitedApproval() public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), recipient, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_UnlimitedApprovalCanBecomeFiniteAndThenBeRevoked() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 1);
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        token.approve(spender, 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), spender), 1);
        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.balanceOf(recipient), 2);
    }

    function test_LoweringPartiallySpentApprovalReplacesItsRemainder() public {
        token.approve(spender, 100);
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 30);
        token.approve(spender, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 10, 11));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 11);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(recipient), 30);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 10));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 40);
        assertEq(token.balanceOf(recipient), 40);
    }

    function test_TwoSpendersCannotConsumeEachOthersAllowance() public {
        token.approve(spender, 10);
        token.approve(otherSpender, 20);
        vm.prank(spender);
        token.transferFrom(address(this), spender, 10);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.allowance(address(this), otherSpender), 20);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 1);
        vm.prank(otherSpender);
        assertTrue(token.transferFrom(address(this), otherSpender, 20));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.allowance(address(this), otherSpender), 0);
        assertEq(token.balanceOf(spender), 10);
        assertEq(token.balanceOf(otherSpender), 20);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 30);
    }

    function test_SelfTransfersCannotBypassBalanceChecks() public {
        token.transfer(holder, 1);
        vm.prank(holder);
        token.approve(spender, 2);
        bytes memory error = abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 1, 2);
        vm.expectRevert(error);
        vm.prank(holder);
        token.transfer(holder, 2);
        vm.expectRevert(error);
        vm.prank(spender);
        token.transferFrom(holder, holder, 2);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.allowance(holder, spender), 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroDelegatedTransferToZeroAddressRevertsWithNoAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), 0);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroDelegatedTransferDoesNotConsumeFiniteOrInfiniteAllowance() public {
        uint256[2] memory approvals = [uint256(1), type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            vm.prank(holder);
            token.approve(spender, approvals[i]);
            vm.prank(spender);
            assertTrue(token.transferFrom(holder, recipient, 0));
            assertEq(token.allowance(holder, spender), approvals[i]);
            assertEq(token.balanceOf(holder), 0);
            assertEq(token.balanceOf(recipient), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_TransferToTokenItselfRemainsPartOfTotalSupply() public {
        assertTrue(token.transfer(address(token), 1));
        token.approve(spender, SUPPLY - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(token), SUPPLY - 1));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InvalidAddressesCannotMutateState(uint256 amount) public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedSpendCanBeRetriedAfterFunding(uint256 balanceSeed, uint256 amountSeed, bool unlimited)
        public
    {
        uint256 held = bound(balanceSeed, 0, SUPPLY - 1);
        uint256 amount = bound(amountSeed, held + 1, SUPPLY);
        uint256 approved = unlimited ? type(uint256).max : amount;
        token.transfer(holder, held);
        vm.prank(holder);
        token.approve(spender, approved);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, held, amount));
        vm.prank(spender);
        token.transferFrom(holder, recipient, amount);
        assertEq(token.balanceOf(holder), held);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - held);
        assertEq(token.allowance(holder, spender), approved);

        token.transfer(holder, amount - held);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, amount));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(holder, spender), unlimited ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ReturningTokensDoesNotRestoreSpentAllowance(uint256 amountSeed) public {
        uint256 amount = bound(amountSeed, 1, SUPPLY);
        token.approve(spender, amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, amount));
        vm.prank(recipient);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(address(this), spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, amount));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, amount);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalReplacementIsIdempotentAndDoesNotMoveTokens(uint256 initial, uint256 replacement) public {
        // A holder may approve more than its current balance or the entire supply.
        vm.startPrank(holder);
        assertTrue(token.approve(spender, initial));
        assertTrue(token.approve(otherSpender, initial));
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(holder, spender), replacement);
        assertTrue(token.approve(spender, replacement));
        vm.stopPrank();
        assertEq(token.allowance(holder, spender), replacement);
        assertEq(token.allowance(holder, otherSpender), initial);
        assertEq(token.allowance(spender, holder), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplittingDelegatedTransferPreservesResult(
        uint256 totalSeed,
        uint256 firstSeed,
        uint256 allowanceSeed
    ) public {
        uint256 total = bound(totalSeed, 1, SUPPLY);
        uint256 first = bound(firstSeed, 0, total);
        uint256 approved = bound(allowanceSeed, total, type(uint256).max);
        Pepe single = new Pepe();
        token.approve(spender, approved);
        single.approve(spender, approved);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), recipient, first));
        assertTrue(token.transferFrom(address(this), recipient, total - first));
        assertTrue(single.transferFrom(address(this), recipient, total));
        vm.stopPrank();

        assertEq(token.balanceOf(recipient), total);
        assertEq(token.balanceOf(address(this)), SUPPLY - total);
        assertEq(token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - total);
        assertEq(token.balanceOf(recipient), single.balanceOf(recipient));
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.allowance(address(this), spender), single.allowance(address(this), spender));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }
}

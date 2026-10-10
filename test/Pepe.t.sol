// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Pepe} from "../src/Pepe.sol";

/// @dev Only a test fixture: verifies that CREATE2 credits the immediate creator, not tx.origin.
contract TokenFactoryFixture {
    function deploy(bytes32 salt) external returns (Pepe) {
        return new Pepe{salt: salt}();
    }

    function distribute(Pepe token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount));
    }
}

/// @dev ERC-20 transfers must not require a recipient callback, even to contracts like this one.
contract RejectingRecipientFixture {
    fallback() external {
        revert("no callbacks accepted");
    }
}

contract PepeTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    Pepe private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new Pepe();
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
    }

    function test_MetadataAndEntireSupplyBelongToDeployer() public view {
        assertEq(token.name(), "pepe");
        assertEq(token.symbol(), "PEPE");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsExactlyOneMintTransfer() public {
        vm.recordLogs();
        Pepe fresh = new Pepe();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_FactoryReceivesAllSupplyAndLaunchTransfersArriveWhole() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        vm.prank(alice, alice);
        Pepe launched = factory.deploy(keccak256("launch fixture"));
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(alice), 0);
        assertEq(launched.balanceOf(address(launched)), 0);

        // Local actors represent the distribution legs; they are not deployed protocol contracts.
        address distributor = makeAddr("distributor fixture");
        address pool = makeAddr("pool fixture");
        address remainder = makeAddr("remainder fixture");
        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY * 88 / 100;
        uint256 remainderShare = SUPPLY * 2 / 100;
        factory.distribute(launched, distributor, swarmShare);
        factory.distribute(launched, pool, poolShare);
        factory.distribute(launched, remainder, remainderShare);

        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarmShare);
        assertEq(launched.balanceOf(pool), poolShare);
        assertEq(launched.balanceOf(remainder), remainderShare);
        vm.prank(distributor);
        assertTrue(launched.transfer(alice, swarmShare));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(alice), swarmShare);
        vm.prank(pool);
        assertTrue(launched.transfer(bob, 1 ether));
        vm.prank(bob);
        assertTrue(launched.transfer(pool, 1 ether));
        assertEq(launched.balanceOf(pool), poolShare);
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_TransferEmitsEventAndDeliversExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 123 ether);
        assertTrue(token.transfer(alice, 123 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.balanceOf(alice), 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferEntireSupply() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToContractDoesNotCallRecipient() public {
        RejectingRecipientFixture recipient = new RejectingRecipientFixture();
        assertTrue(token.transfer(address(recipient), 1));
        assertEq(token.balanceOf(address(recipient)), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_TransferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InsufficientBalanceRevertsWithoutMutation() public {
        token.transfer(alice, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10, 11));
        vm.prank(alice);
        token.transfer(bob, 11);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferRevertsWithInsufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ApprovalEmitsEventAndCanBeReplacedAndRevoked() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 100);
        assertTrue(token.approve(spender, 100));
        assertEq(token.allowance(address(this), spender), 100);
        assertTrue(token.approve(spender, 20));
        assertEq(token.allowance(address(this), spender), 20);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 100);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_ApprovalsAreScopedToCallerAndSpender() public {
        token.approve(spender, 100);
        vm.prank(alice);
        token.approve(spender, 200);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.allowance(alice, spender), 200);
        assertEq(token.allowance(address(this), bob), 0);
    }

    function test_TransferFromSpendsAllowanceAndEmitsTransfer() public {
        token.approve(spender, 100);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 40);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 40));
        assertEq(token.allowance(address(this), spender), 60);
        assertEq(token.balanceOf(address(this)), SUPPLY - 40);
        assertEq(token.balanceOf(alice), 40);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 60));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 100);
    }

    function test_TransferFromWithInfiniteAllowanceDoesNotDecreaseIt() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_TransferFromZeroAmountNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromToSelfSpendsAllowanceButPreservesBalance() public {
        token.approve(spender, 100);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 60));
        assertEq(token.allowance(address(this), spender), 40);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromInsufficientAllowanceRevertsWithoutMutation() public {
        token.approve(spender, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 10, 11));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 11);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_TransferFromWrongSpenderReverts() public {
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevokedAllowanceCannotBeSpent() public {
        token.approve(spender, 100);
        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_TransferFromInsufficientBalanceRollsBackAllowance() public {
        vm.prank(alice);
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 60));
        vm.prank(spender);
        token.transferFrom(alice, bob, 60);
        assertEq(token.allowance(alice, spender), 100);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromZeroRecipientRollsBackAllowance() public {
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 60);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromZeroSourceReverts() public {
        // Zero value passes the allowance comparison but still cannot use the mint address as a source.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_DeployerCannotTakeHolderTokensWithoutApproval() public {
        token.transfer(alice, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 100);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_NoMintBurnPauseSeizeOrUpgradeEntryPoints() public {
        token.transfer(alice, 100);
        bytes[] memory calls = new bytes[](14);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[7] = abi.encodeWithSignature("freeze(address)", alice);
        calls[8] = abi.encodeWithSignature("seize(address)", alice);
        calls[9] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[10] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[11] = abi.encodeWithSignature("initialize(address)", bob);
        calls[12] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[13] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded);
            vm.prank(bob);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 100);
            assertEq(token.balanceOf(bob), 0);
        }
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_RejectsEther() public {
        vm.deal(address(this), 1 ether);
        (bool accepted,) = address(token).call{value: 1 ether}("");
        assertFalse(accepted);
        assertEq(address(token).balance, 0);
    }

    function test_RuntimeFitsDeploymentLimitAndHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4, "DELEGATECALL");
            assertTrue(op != 0xf2, "CALLCODE");
            assertTrue(op != 0xff, "SELFDESTRUCT");
        }
    }

    function testFuzz_TransferConservesSupply(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_AllowanceControlsDelegatedTransfers(uint256 rawAllowance, uint256 rawAmount) public {
        uint256 approved = bound(rawAllowance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, approved);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, amount));
        assertEq(token.allowance(address(this), spender), approved - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ExcessTransfersRevert(uint256 rawBalance, uint256 rawExcess) public {
        uint256 held = bound(rawBalance, 0, SUPPLY);
        uint256 excess = bound(rawExcess, 1, type(uint256).max - held);
        token.transfer(alice, held);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, held + excess)
        );
        vm.prank(alice);
        token.transfer(bob, held + excess);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ExcessAllowanceSpendReverts(uint256 rawAllowance, uint256 rawExcess) public {
        uint256 approved = bound(rawAllowance, 0, SUPPLY - 1);
        uint256 excess = bound(rawExcess, 1, SUPPLY - approved);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + excess
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, approved + excess);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}

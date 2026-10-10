// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Pepe} from "../src/Pepe.sol";

/// @dev A closed set of actors lets the test sum every balance and independently model all allowances.
contract PepeHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Pepe public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Pepe token_) {
        token = token_;
        actors[0] = makeAddr("invariant alice");
        actors[1] = makeAddr("invariant bob");
        actors[2] = makeAddr("invariant carol");
        actors[3] = makeAddr("invariant dave");
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = SUPPLY / actors.length;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowed = expectedAllowance[from][spender];
        uint256 held = expectedBalance[from];
        uint256 amount = bound(amountSeed, 0, allowed < held ? allowed : held);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) {
            expectedAllowance[from][spender] -= amount;
        }
    }

    function rejectOverspend(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 held = expectedBalance[from];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, held + 1));
        vm.prank(from);
        token.transfer(to, held + 1);
    }

    /// @dev Hit revocation and the finite/infinite boundary deliberately, as well as arbitrary approvals above.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 mode) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256[5] memory amounts = [uint256(0), 1, SUPPLY, type(uint256).max - 1, type(uint256).max];
        uint256 amount = amounts[mode % amounts.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    /// @dev Guarantee positive delegated transfers even when random standalone approvals miss a funded holder.
    function approveAndTransferFrom(uint256 fromSeed, uint256 spenderSeed, uint256 amountSeed, bool unlimited)
        external
    {
        uint256 fromIndex = _fundedActorIndex(fromSeed);
        address from = actors[fromIndex];
        address to = actors[(fromIndex + 1) % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = bound(amountSeed, 1, expectedBalance[from]);
        uint256 approved = unlimited ? type(uint256).max : amount;
        vm.prank(from);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[from][spender] = approved;

        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (!unlimited) expectedAllowance[from][spender] = 0;
    }

    function revokeAndRejectSpend(uint256 fromSeed, uint256 spenderSeed) external {
        uint256 fromIndex = _fundedActorIndex(fromSeed);
        address from = actors[fromIndex];
        address to = actors[(fromIndex + 1) % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(from);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[from][spender] = 0;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(from, to, 1);
        // Leave ghosts unchanged: the invariant also checks that rejection preserved unrelated accounts.
    }

    function rejectUnfundedDelegatedSpend(uint256 fromSeed, uint256 spenderSeed, bool unlimited) external {
        uint256 fromIndex = fromSeed % actors.length;
        address from = actors[fromIndex];
        address to = actors[(fromIndex + 1) % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 held = expectedBalance[from];
        uint256 amount = held + 1;
        uint256 approved = unlimited ? type(uint256).max : amount;
        vm.prank(from);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[from][spender] = approved;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        vm.prank(spender);
        token.transferFrom(from, to, amount);
        // In particular, a failed spend must not consume the finite allowance it tentatively checked.
    }

    function rejectZeroAddresses(uint256 fromSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(from);
        token.approve(address(0), amountSeed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(from);
        token.transfer(address(0), amount);

        vm.prank(from);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[from][spender] = amount;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(from, address(0), amount);
    }

    function transferFullBalance(uint256 fromSeed) external {
        uint256 fromIndex = _fundedActorIndex(fromSeed);
        address from = actors[fromIndex];
        address to = actors[(fromIndex + 1) % actors.length];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] = 0;
        expectedBalance[to] += amount;
    }

    /// @dev Liveness and an independent round-trip oracle; does not derive the expectation from token balances.
    function roundTripFullBalance(uint256 fromSeed) external {
        uint256 fromIndex = _fundedActorIndex(fromSeed);
        address from = actors[fromIndex];
        address to = actors[(fromIndex + 1) % actors.length];
        uint256 amount = expectedBalance[from];
        uint256 recipientBefore = expectedBalance[to];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), 0, "holder could not transfer its full balance");
        assertEq(token.balanceOf(to), recipientBefore + amount, "round-trip outward leg arrived short");
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        assertEq(token.balanceOf(from), amount, "round trip changed holder balance");
        assertEq(token.balanceOf(to), recipientBefore, "round trip changed recipient balance");
        // The net transfer is zero, so the balance and allowance models stay unchanged.
    }

    function _fundedActorIndex(uint256 seed) private view returns (uint256) {
        uint256 start = seed % actors.length;
        for (uint256 i; i < actors.length; ++i) {
            uint256 index = (start + i) % actors.length;
            if (expectedBalance[actors[index]] > 0) return index;
        }
        revert("model lost the fixed supply");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract PepeInvariantTest is Test {
    Pepe private token;
    PepeHandler private handler;

    function setUp() public {
        token = new Pepe();
        handler = new PepeHandler(token);
        for (uint256 i; i < 4; ++i) {
            assertTrue(token.transfer(handler.actors(i), 1_000_000_000 * 10 ** 18 / 4));
        }

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = PepeHandler.transfer.selector;
        selectors[1] = PepeHandler.approve.selector;
        selectors[2] = PepeHandler.transferFrom.selector;
        selectors[3] = PepeHandler.rejectOverspend.selector;
        selectors[4] = PepeHandler.approveBoundary.selector;
        selectors[5] = PepeHandler.approveAndTransferFrom.selector;
        selectors[6] = PepeHandler.revokeAndRejectSpend.selector;
        selectors[7] = PepeHandler.rejectUnfundedDelegatedSpend.selector;
        selectors[8] = PepeHandler.rejectZeroAddresses.selector;
        selectors[9] = PepeHandler.transferFullBalance.selector;
        selectors[10] = PepeHandler.roundTripFullBalance.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_BalancesAllowancesAndSupplyMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 held = token.balanceOf(actor);
            assertEq(held, handler.expectedBalance(actor), "balance differs from model");
            assertEq(token.allowance(actor, address(0)), 0, "zero address acquired spending permission");
            sum += held;
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(actor, spender),
                    handler.expectedAllowance(actor, spender),
                    "allowance differs from model"
                );
            }
        }
        assertEq(sum, 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), sum);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.name(), "pepe");
        assertEq(token.symbol(), "PEPE");
        assertEq(token.decimals(), 18);
    }

    /// @dev After every random sequence, holders can still move their entire balance and return it.
    function afterInvariant() public {
        for (uint256 i; i < 4; ++i) {
            handler.roundTripFullBalance(i);
            invariant_BalancesAllowancesAndSupplyMatchModel();
        }
    }
}

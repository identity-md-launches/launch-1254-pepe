// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Pepe} from "../src/Pepe.sol";

/// @dev A closed set of actors lets the test sum every balance and independently model all allowances.
contract PepeHandler is Test {
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
        expectedBalance[actors[0]] = 1_000_000_000 * 10 ** 18;
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
}

contract PepeInvariantTest is Test {
    Pepe private token;
    PepeHandler private handler;

    function setUp() public {
        token = new Pepe();
        handler = new PepeHandler(token);
        token.transfer(handler.actors(0), 1_000_000_000 * 10 ** 18);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = PepeHandler.transfer.selector;
        selectors[1] = PepeHandler.approve.selector;
        selectors[2] = PepeHandler.transferFrom.selector;
        selectors[3] = PepeHandler.rejectOverspend.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_BalancesAllowancesAndSupplyMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 held = token.balanceOf(actor);
            assertEq(held, handler.expectedBalance(actor), "balance differs from model");
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
    }
}

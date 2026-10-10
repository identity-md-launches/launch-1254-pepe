# Security review and verification

## Scope

This is a local implementation review of `src/Pepe.sol` and its vendored ERC-20 dependency,
using the assignment's pinned security reference and protected-check source as review
inputs. It is not an independent security audit or a claim that the external launch
integration suite has run here.

## Findings from the implementation review

- **Supply:** The sole `_mint` call is in the constructor. The fixed amount is `10^27`
  smallest units, corresponding to one billion tokens with 18 decimals. The runtime
  exposes no mint, burn, initialization, or upgrade path.
- **Allocation:** The recipient is `msg.sender`, not `tx.origin`. The constructor takes
  no parameters and calls no external contracts. CREATE2 through a factory is covered
  by a local fixture.
- **Permissions:** There is no administrative role. Transfers debit only the caller;
  delegated transfers require that caller's allowance from the holder. A failed
  delegated transfer rolls back any allowance update.
- **Accounting:** OpenZeppelin checks sender balances and finite allowances before
  subtraction. Its unchecked arithmetic is bounded by those checks and conservation
  of supply. Self-transfers, zero values, full-balance transfers, excessive amounts,
  and unlimited approvals are covered by tests.
- **Interactions:** Token operations make no external calls. There are no recipient
  hooks, oracle inputs, signatures, swaps, randomness, or payable entry points. A
  callback guard, oracle configuration, and access-control machinery are unnecessary
  for this interface.
- **Launch transfers:** No fee, burn, restriction, or special-address branch can short
  the factory, distributor, pool, or holder. The local launch fixture checks exact
  distribution and onward transfers. The production pool and factory are outside this
  repository and require their separate integration checks.
- **Bytecode:** The deployed runtime is tested against the EIP-170 size limit and
  scanned for `DELEGATECALL`, `CALLCODE`, and `SELFDESTRUCT`, skipping PUSH immediate data.
  Build metadata hashing is disabled as required for reproducibility.

No issue requiring an implementation change was identified in this local review. The
standard allowance replacement race, unlimited-approval exposure, and lack of recovery
for misdirected assets remain operational considerations described in the README.

## Local checks

Executed with Foundry 1.8.3 and Solidity 0.8.26:

- `forge build`: passes.
- `forge test`: 33 tests pass, none fail or skip; four fuzz tests run 1,024 cases each.
- `forge fmt --check`: passes.
- Stateful invariant: 128 runs, 8,192 handler calls, zero unexpected reverts. It checks
  supply conservation and compares every tracked balance and allowance with an
  independent model after each action.
- A clean copy containing only the project sources, tests, vendored dependencies, and
  Foundry configuration also passes `forge build --offline`,
  `forge test --offline --threads 4`, and `forge fmt --check` with an empty environment
  except the tool search path. The supplied input documents are absent from that copy.
- Creation bytecode (2,633 bytes) and runtime bytecode (1,752 bytes) are identical across
  the original and clean builds, with no external library link references. All 36
  vendored-file checksums pass.

The delivered tests use no RPC, FFI, filesystem cheatcodes, or environment reads/writes.
Slither and Mythril were not run. An independent contributor should review the token and
the launch integration before release; deployment, explorer verification, and checking
the live distribution are the launch operator's responsibilities.

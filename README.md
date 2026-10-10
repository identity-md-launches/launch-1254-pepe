# pepe (PEPE)

A fixed-supply ERC-20 for the IdentityMD custom token launch. The deployable contract is
[`src/Pepe.sol:Pepe`](src/Pepe.sol).

| Parameter | Value |
| --- | --- |
| Solidity contract identifier | `Pepe` |
| Token name | `pepe` |
| Token symbol | `PEPE` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`; empty ABI encoding) |
| Deployment value | `0` ETH |
| Initial recipient | The immediate deployer, `msg.sender` |

## Behavior and assumptions

The constructor mints the entire supply in one operation and emits the standard
`Transfer(address(0), deployer, supply)` event. In the launch flow, the factory is
the deployer and receives everything. A direct deployment instead credits the account
creating the contract. No recipient, owner, external contract address, or initialization
call needs to be configured.

The token inherits the unmodified OpenZeppelin Contracts v5.0.2 ERC-20 implementation.
Transfers deliver the exact amount requested. There are no taxes, transfer hooks, rebases,
mint or burn entry points, owner roles, pause or blacklist powers, seizure powers, or
upgrades. The deployer has the same transfer and approval permissions as every holder.

Standard ERC-20 behavior applies:

- `transfer`, `approve`, and `transferFrom` return `true` on success and revert on failure.
- Zero-value and self-transfers are allowed. Transfers to the zero address are rejected,
  including zero-value transfers. Approving a zero-address spender is rejected.
- `approve` replaces the caller's allowance for that spender. Zero revokes it.
- `transferFrom` requires allowance even if the spender is the token's deployer or the
  holder itself. Finite allowances decrease; `type(uint256).max` remains unlimited.
- Transfers emit `Transfer`; explicit approvals emit `Approval`. In this OpenZeppelin
  version, spending allowance does not emit a separate `Approval` event. Read `allowance`
  for the current value.
- Transfers make no external calls or recipient callbacks. Native ETH payments revert.

## Build and test

Use Foundry with Solidity **0.8.26** available in its compiler cache. All Solidity
dependencies and their licenses are included as ordinary files in `lib/`; no package
installation, submodule initialization, RPC, wallet, environment variables, or network
access is required once the toolchain is available.

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, the optimizer at 200 runs,
and `bytecode_hash = "none"`. FFI and filesystem permissions are disabled. The compiler
binary is supplied by the build environment and is not part of this repository.

The suite includes deterministic success and failure cases, four fuzz tests with 1,024
cases each, and a stateful invariant with 128 runs of 64 actions. The invariant checks
every modeled balance and allowance after randomized transfers, approvals, delegated
transfers, and rejected overspends. Tests do not read or modify environment variables,
fork a chain, or depend on test order.

The factory fixture verifies CREATE2 deployment and exact 10% / 88% / 2% distribution
legs, onward claims, and transfers both ways with a pool actor. It exercises token
behavior only; it is not an implementation or integration test of Uniswap v4 or the
production launch factory. Those integrations belong to the independent launch checks.

## Deployment parameters and responsibilities

The intended launch chain is Ethereum mainnet (chain ID 1). The token has no chain-specific
addresses and its constructor makes no external calls, so it also deploys on an empty
Cancun-compatible test chain. Only `Pepe` is a production contract; fixtures and the
invariant handler under `test/` must not be deployed as applications.

Build using the checked-in configuration. The creation bytecode and ABI are in
`out/Pepe.sol/Pepe.json`; the following read-only command prints the creation bytecode:

```sh
forge inspect src/Pepe.sol:Pepe bytecode
```

The launch operator supplies that creation bytecode with no constructor arguments and
no ETH value. The factory must perform the creation itself to receive the initial
supply. Deploying through another helper would credit that helper instead. There are no
external library link addresses or post-deployment initialization calls.

The launch system is responsible for producing `launch.json`, deploying the token,
distributing the supply, and creating and funding the pool. None of that logic is in
the token. The task's launch policy allocates 10% to the swarm distributor, 88% to pool
liquidity, and 2% to the requester-specified remainder recipient. The operator must use
the supplied launch policy and economics, including the FWA pair and 1.25% pool fee;
the token does not enforce or configure pool economics. This project does not broadcast
transactions, access signing keys, or produce a launch manifest.

### After launch

No token settings or administrative maintenance are required. The launch operator should
verify the deployed source and bytecode against this build, confirm the exact name,
symbol, decimals, supply, constructor mint recipient, and subsequent distribution, and
publish the deployed token address. An independent adversarial review remains a release
responsibility; local tests are not a security audit.

Holders control their balances and spending approvals. Use limited allowances for trusted
spenders and revoke unused approvals. When replacing an existing allowance, revoke it and
wait for confirmation before granting a new one; a revocation cannot undo spending that
has already happened. There is no administrator who can recover lost keys or misdirected
tokens. PEPE sent to the token contract itself, or to another contract without a withdrawal
path, may be permanently inaccessible; forced ETH and unrelated tokens cannot be rescued.

Dependency provenance is recorded in [DEPENDENCIES.md](DEPENDENCIES.md). Review scope and
verification results are recorded in [SECURITY.md](SECURITY.md).

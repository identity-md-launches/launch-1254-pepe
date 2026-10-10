# Vendored dependencies

The following source snapshots are included as ordinary files, with no submodules or
package-manager downloads at build time. The upstream files have not been modified.

| Dependency | Pinned version | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2) | `v5.0.2` | `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`, `draft-IERC6093.sol` | `lib/openzeppelin-contracts/LICENSE` (MIT) |
| [Forge Standard Library](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | `v1.9.7` | Solidity files from `src/`, for tests | `lib/forge-std/LICENSE-MIT` and `LICENSE-APACHE` |

OpenZeppelin is the token's only production dependency. Forge Standard Library is used
only by local tests. Neither dependency introduces externally linked libraries into
the token bytecode.

The files were obtained from these upstream release archives:

- `https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2`
  — SHA-256 `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a`.
- `https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7`
  — SHA-256 `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`.

Individual vendored-file SHA-256 hashes are in `lib/checksums.sha256`. Verify locally with:

```sh
sha256sum --check lib/checksums.sha256
```

Solidity 0.8.26 and Foundry are build tools supplied by the execution environment, not
vendored dependencies. The token follows the [ERC-20 standard](https://eips.ethereum.org/EIPS/eip-20).

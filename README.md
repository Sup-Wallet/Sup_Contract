# Sup Wallet — Smart Contracts

A set of Sui Move contracts implementing a **programmable-delegation agent wallet**:
turn "who may move my money, and under what conditions" into composable, revocable
on-chain rules, and connect safely to major DeFi protocols through an open adaptor
interface.

> Core idea: a delegate is not an address — it is *whoever or whatever can satisfy
> the rules the wallet owner attaches.*

## What it solves

- **Safe delegation** — funds leave the wallet only at the moment every rule passes
  (a hot-potato flow). A malicious rule can only block; it can never change the
  amount or the recipient.
- **Composable authorization** — stack auth rules (OR) and caveat rules (AND) freely,
  e.g. "this address + a budget cap + a recipient allowlist".
- **One-shot revocation** — bump a version and every outstanding cap and sub-delegation
  dies at once.
- **Open ecosystem** — anyone can add a new rule or protocol adaptor without a PR;
  owners choose whether to opt in.

## Repo layout

| Directory | Contents |
| --- | --- |
| `sup_wallet/` | Wallet core: SIP-58 custody, policy engine, cap / sub-delegation auth, intent flow |
| `official/adaptor_*` | Officially maintained DeFi adaptors (Cetus, NAVI, Scallop, Suilend, Bucket, Haedal, …) |
| `official/policy_rule_*` | Pluggable auth / caveat rules and the rule registry |
| `official/sup_escrow`, `sup_subscription`, `sup_inheritance` | Extensions: escrow / subscription / inheritance |
| `community/` | Third-party community adaptors (not audited by the core team) |

## Quick start

```bash
# inside any package directory
sui move build      # compile
sui move test       # run unit tests
```

## Learn more

- `sup_wallet/ARCHITECTURE.md` — the whole architecture and auth flow on one page
- `sup_wallet/DELEGATION_POLICY.md` — full design, APIs, and roadmap
- `official/MAINNET_ADAPTORS.md` — each DeFi adaptor's functions and mainnet objects
- `community/README.md` — how to write your own adaptor

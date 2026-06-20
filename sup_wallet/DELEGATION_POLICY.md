# Delegation Policy — pluggable, condition-gated fund unlocking

> Status: **increments 1–2 landed.**
> - inc 1 — `SupWallet::policy` core (hot-potato engine + OR-auth / AND-caveat).
> - inc 2 — `SupWallet::cap_auth` (`DelegateCap` object + `CapAuth` rule): the
>   delegate can now be *anything that holds an object* — address, contract, ZK,
>   machine, zkSend link, escrow.
>
> Tested: 22/22 (`policy_tests` 6, `cap_auth_tests` 5, existing `wallet_tests` 11).
> Roadmap layers (sub-delegation / marketplace / 8183 escrow) at the bottom.

## 1. The idea in one paragraph

Today a delegate is **an address** and the spending rules (per-service / per-coin
budgets) are **hard-coded inside `delegate.move`**. This document describes the
generalization: the wallet core stops knowing about budgets and instead emits a
**`SpendRequest` hot potato** that can only be cashed out (`confirm_spend`) once a
set of **pluggable rule modules** have stamped their approval. A "delegate" is no
longer an address — it is *whoever / whatever can satisfy the rules the owner
attached to their wallet*: an address, a `Cap` object, a contract's witness, a ZK
proof, an oracle condition, an 8183-style job assessor, etc.

This is the Sui `TransferPolicy` / kiosk model applied to **fund delegation**:

| Sui Kiosk                         | Here                                            |
| --------------------------------- | ----------------------------------------------- |
| `TransferPolicy<T>` (creator-set) | `DelegationPolicy` (owner-set, DF on `Wallet`)  |
| `TransferRequest<T>` (hot potato) | `SpendRequest` (hot potato, carries the facts)  |
| `Rule` witness + `add_receipt`    | rule module witness + `add_*_receipt`           |
| `confirm_request`                 | `confirm_spend` (releases the coin)             |

It also lines up with three ERCs we already mirror:

```
┌─ ERC-8183  job / escrow / assessor settlement   ← agents doing commerce  (roadmap)
├─ delegation / caveats (this doc, ERC-7710-ish)  ← how an agent is allowed to spend
└─ ERC-8004  identity / discovery / reputation    ← who an agent is  (adaptor_registry)
```

## 2. Why this is strictly more general than EVM delegation

In Move, "an arbitrary contract is the delegate" needs no signatures and no
approvals. A contract proves authority simply by constructing **its own witness
type** (only its defining module can), then stamping the `SpendRequest`. That
contract can gate the stamp on *any* on-chain condition it wants — an oracle
price, a ZK verification, another object's state, a time window, an 8183 job
being marked `Terminal`. The wallet core never needs to learn about any of these:
it only checks "did the witnesses the owner trusts all sign off?".

**Safety invariant:** a rule only ever receives `&SpendRequest` (read amount /
recipient / coin) plus a single stamping entrypoint. It **cannot mutate the
amount or recipient**. A malicious rule can therefore only `abort` (which just
blocks the people who opted into it) — it can never redirect or inflate a
payment. The coin is withdrawn from the wallet **only at `confirm_spend`**, after
all checks pass, so a half-finished flow leaks nothing (the hot potato has no
`drop`, so the tx must reach `confirm_spend` or revert entirely).

## 3. Core types (`SupWallet::policy`)

```move
/// Per-wallet policy. DF on Wallet UID under POLICY_DF_KEY. Owner-configured.
public struct DelegationPolicy has store {
    version: u64,                   // bump = mass-revoke every in-flight authority
    auth_rules: VecSet<TypeName>,   // OR-gated: any one principal proof suffices
    caveat_rules: VecSet<TypeName>, // AND-gated: every caveat must be satisfied
}

/// Hot potato. No abilities — must be consumed by confirm_spend or the tx aborts.
public struct SpendRequest {
    wallet_id: ID,
    coin: TypeName,
    amount: u64,
    recipient: address,
    policy_version: u64,            // snapshot; stale => revoked
    auth_receipts: VecSet<TypeName>,
    caveat_receipts: VecSet<TypeName>,
}
```

### Two kinds of rule

- **Auth rules (`OR`)** — answer *"who is the principal?"*. Examples:
  `AddressAuth` (checks `ctx.sender()`), `CapAuth` (requires presenting a
  `DelegateCap` object → lets the delegate be a contract / machine / zkSend link /
  hashlock escrow), `ZkAuth` (verifies a proof), `ModuleAuth` (another contract's
  witness). Any **one** accepted auth rule stamping is enough.

- **Caveat rules (`AND`)** — answer *"is this spend allowed?"*. Examples:
  `BudgetRule` (port of today's per-coin / per-service allowance), `TimeWindowRule`,
  `RecipientAllowlistRule`, `OraclePriceRule`, `SubDelegateRule`, `InheritanceRule`.
  **Every** caveat the owner attached must stamp.

### Flow

```move
// 1. anyone may start (gated at the end, not the start)
let req = policy::begin_spend<CoinT>(&wallet, amount, recipient);

// 2. a rule module checks its condition and stamps (witness-gated):
my_auth_rule::prove(&cap, &mut req, ctx);          // -> add_auth_receipt<MyAuth>
my_caveat_rule::enforce(&config, &mut req, clock);  // -> add_caveat_receipt<MyCaveat>

// 3. cash out: aborts unless (>=1 auth_rule matched) AND (all caveat_rules matched)
//    AND policy_version still current. Transfers the coin to `recipient`.
policy::confirm_spend<CoinT>(&mut wallet, req, ctx);
```

Owner config surface: `initialize`, `add_auth_rule<R>` / `remove_auth_rule<R>`,
`add_caveat_rule<R>` / `remove_caveat_rule<R>`, `revoke_all` (version bump).

Rule-facing surface: `spend_amount` / `spend_recipient` / `spend_coin` /
`spend_wallet_id` / `spend_policy_version` (reads), and `add_auth_receipt<R>` /
`add_caveat_receipt<R>` (witness-gated stamps).

## 4. Relationship to the existing `delegate.move`

`delegate.move` is **left untouched** for backward compatibility — it remains the
"address + hard-coded budget" fast path the current SDK / UI use. The intended
end-state is for it to become *one preset* of this system: a policy carrying
`AddressAuth + BudgetRule`. New capability (caveats, cap-based principals,
sub-delegation, escrow) is built on `policy.move`, not by extending `delegate.move`.

## 5. Cap-based principal (`SupWallet::cap_auth`) — landed (inc 2)

`DelegateCap` is a `key + store` bearer object. The owner mints one bound to the
current policy `version`; whoever holds it is the principal. Because it has
`store`, the holder can be an address, **a contract** (the cap lives in another
object's field — see `cap_auth_tests::contract_custody_spends`), a machine, a
zkSend link, or a hashlock escrow.

```move
public struct DelegateCap has key, store { id: UID, wallet_id: ID, policy_version: u64 }
public struct CapAuth has drop {}   // the auth-rule witness

// owner:
let cap = cap_auth::mint(&wallet, ctx);          // or mint_and_transfer(&wallet, who, ctx)
policy::add_auth_rule<CapAuth>(&mut wallet, ctx); // accept caps as a principal proof

// holder (or a contract custodying the cap):
let mut req = policy::begin_spend<CoinT>(&wallet, amount, recipient);
cap_auth::prove(&cap, &mut req);                  // stamps CapAuth iff cap valid + current
// ... caveat rules stamp ...
policy::confirm_spend<CoinT>(&mut wallet, req, ctx);
```

The cap carries **no** limits — those stay in the wallet's caveat rules. `prove`
needs no `&Wallet`: it checks `cap.policy_version == req`'s snapshot, and
`confirm_spend` already enforces that snapshot is current, so a stale cap fails
both ways. **Revocation:** `policy::revoke_all` bumps the version, instantly
killing every outstanding cap. Per-cap selective revocation (a revocation set
keyed by cap id) is future work.

## 6. Sub-delegation (`SupWallet::sub_delegate`) — landed (inc 3)

`ScopedCap` binds a per-coin budget to the capability itself (the per-cap caveat
binding that wallet-global caveats couldn't express). A holder `subdelegate`s part
of their budget to a child cap at `depth + 1`; the parent is debited immediately,
so a child can never outspend its grant and no chain can exceed the root — true
object-capability attenuation (ERC-7710 redelegation). On `spend` the cap debits
its own budget and stamps **both** `ScopedAuth` (auth) and `ScopedBudget` (caveat),
so a wallet accepts scoped caps with just those two rules. `max_depth` caps the
tree height; `policy::revoke_all` kills the whole tree via version. Returning a
child's unused budget to its parent and per-cap selective revoke are future work.

## 7. Marketplace + writing your own rule — landed (inc 4)

Two new **separate packages** (not part of `SupWallet`) show the open model:

- **`policy_rule_registry`** — the rule marketplace, sibling of `adaptor_registry`.
  Anyone deploys a rule package and `register`s its witness `rule_type` + package
  id + `kind` (auth / caveat) + off-chain manifest. Permissionless, publisher-gated
  updates, event-only `attest` reputation. On-chain stores only the anchor;
  discovery is by indexing events. It is a directory, **not** a trust authority —
  a listed rule has zero power until a wallet owner opts into it.

- **`policy_rule_recipient_allowlist`** — a reference third-party caveat rule,
  built against `SupWallet`'s **public interface only** (no core changes, no
  package-private access). Proof that anyone — or any contract — can integrate.

### Anatomy of a rule (the whole contract third parties need)

```move
public struct MyRule has drop {}                       // 1. witness only you can build

public fun enforce(/* your config */ req: &mut SpendRequest) {
    // 2. read facts: policy::spend_amount / spend_recipient / spend_coin / spend_wallet_id
    assert!(/* your condition */, EYourError);
    policy::add_caveat_receipt(MyRule {}, req);         // 3. stamp (or add_auth_receipt for auth)
}
```

Owner opts in with `policy::add_caveat_rule<MyRule>(&mut wallet)`; a spender calls
`enforce(.., &mut req)` between `begin_spend` and `confirm_spend`. The rule gets
`&SpendRequest` + the stamp only — it can never alter amount/recipient, only
`abort`. Owner-gating for any config object uses the public `wallet::owner`
accessor. That is the entire integration surface — `SupWallet::policy` +
`SupWallet::wallet` public functions.

## 8. Roadmap (not yet built)

1. **8183 escrow / Job** — a `Job<CoinT>` shared object (states Open → Funded →
   Submitted → Terminal) funded *through* a `SpendRequest`, released to the
   provider when an `assessor` rule stamps. The assessor is just another auth/rule,
   so "who can release escrow" is as pluggable as "who can delegate". A
   `confirm_spend_into` variant that **returns** the coin (instead of transferring
   to `recipient`) is the composition primitive for funding escrow / swaps in-PTB.
2. **Per-cap selective revocation & budget refund** — a revocation set keyed by
   cap id, and returning a child cap's unused budget to its parent.
3. **Rule-authoring skill / scaffold** — an agent skill that generates a rule
   package (witness + `enforce` + tests + manifest) from a plain-language spec and
   registers it, so non-Move builders can ship rules.

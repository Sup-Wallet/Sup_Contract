# `adaptor_aftermath_perp` — agent-operated Aftermath perps, withdraw-locked to the vault

> Status: **DRAFT for review — do NOT deploy yet.** The Aftermath on-chain ABI used
> here is reconstructed from the (commented-out) on-chain tx builders in
> `aftermath-ts-sdk@2.1.0`; the live SDK builds perp PTBs via Aftermath's backend.
> Every Aftermath call below is marked `// VERIFY` and must be checked against the
> real published Aftermath Perpetuals Move package before publish. Mainnet object
> ids (perp package, Registry, ClearingHouses, oracle price feeds) are NOT in the
> SDK and must be sourced at deploy time.

## Goal

Let the Sup **managed agent** open / adjust / close perpetual positions on
Aftermath **on behalf of the user's vault**, and let it **withdraw collateral —
but ONLY back into the vault**, never to an arbitrary address. Both properties
enforced **on-chain**.

## Why a custody wrapper (not the bare Aftermath cap)

An Aftermath perp account is controlled by an owned `AccountCap`. Two problems
for agent automation:

1. **Owned-object access.** A tx signed by the agent can't touch a cap owned by
   the user or by the vault identity (the vault identity has no keypair). So the
   agent can't use the user's cap directly.
2. **Withdraw destination.** Aftermath's `withdraw_collateral(cap, amount)`
   returns the coin to *whoever ran the tx*. If the agent held a cap that can
   withdraw, it could send funds to itself. Aftermath's native *agent* cap fixes
   this (it can trade but **cannot** withdraw) — but then the agent can't return
   funds to the vault at all.

**Solution — mirror `adaptor_os_account`.** We introduce a Sup-custodied shared
object `AfPerpAccount<T>` that:

- **holds** the Aftermath **admin** `AccountCap` (the cap never leaves the
  object — no public function hands out `&AccountCap`),
- is **parented** to the vault (`parent_wallet_identity == wallet::identity`),
- carries a small **permission ACL** (`delegates: VecMap<address, u32>`) with
  two bits: `PERM_TRADE` and `PERM_WITHDRAW`,
- exposes only **gated, purpose-built** entry functions. Crucially,
  `withdraw_to_vault` performs the Aftermath withdraw **and** the deposit-back
  into the vault **in one function**, so the withdrawn coin is *structurally*
  forced to `wallet::receive_from_service(vault, …)` — there is no code path
  that returns the coin to the caller.

This is the same shape as `os_account::account` + `adaptor_os_account` (see
`withdraw` there: permission check → `withdraw_for_protocol` → `receive_from_service`).

## Custody & authorization model

```
        owner (user wallet)
          │  adopt(admin_cap)            ← one-time, owner-signed
          ▼
   AfPerpAccount<T>  (shared, parent = vault identity)
     ├─ admin_cap: Aftermath AccountCap   (locked inside; never handed out)
     └─ delegates: { agentAddr -> PERM_TRADE | PERM_WITHDRAW }
          ▲
          │  grant_delegate(agent, perms) ← owner-signed
          │
   agent (managed key) ── place_market_order / withdraw_to_vault / deposit_collateral
```

- **Deposit collateral** pulls from the vault via the Sup `intent` flow (debits
  the agent's per-service + per-coin allowances on the Wallet, exactly like every
  other adaptor) → `interface::deposit_collateral`.
- **Trade** (`place_market_order`) requires `PERM_TRADE` (or the owner). The cap
  is used internally for `start_session → place_market_order → end_session`.
- **Withdraw** requires `PERM_WITHDRAW` (or the owner). The coin is **always**
  credited back to the vault via `wallet::receive_from_service<AftermathPerpAdaptor,T>`.
  → **"agent can withdraw, but only to the vault" — enforced on-chain.**
- **reclaim** (owner only) returns the admin cap to the owner and deletes the
  wrapper (exit hatch).

## Owner one-time setup (off-chain → 2 signatures)

1. Create an Aftermath perp account the normal way (admin cap lands in your
   wallet). *(Or we add a `create_and_adopt` later once the create_account
   handshake is verified.)*
2. `adopt<T>(wallet, aftermath_account_id, admin_cap)` — wrap + share, parent = vault.
3. `grant_delegate<T>(wallet, self, agentAddr, PERM_TRADE | PERM_WITHDRAW)`.
4. Grant the agent vault allowances for deposits:
   `wallet::grant_service_coin<AftermathPerpAdaptor, USDC>` +
   `delegate::set_service_allowance<AftermathPerpAdaptor>(agent, N)` +
   `delegate::set_coin_allowance<USDC>(agent, N)`.

After that the agent trades + manages collateral autonomously; the user keeps the
admin cap effectively (via `reclaim`) and is the only one who set the perms.

## What's SOLID vs. what needs verification

**Solid (from in-repo precedents — `adaptor_os_account`, `adaptor_navi`, `wallet`/`intent`/`delegate`):**
- the wrapper + parent check (`assert_parent`), the ACL, owner gating via `wallet::owner`,
- the intent pull for deposits (`request_payment` → `validate_and_pay` → `verify_and_clear`),
- crediting back to the vault via `wallet::receive_from_service` (destination-locked).

**VERIFY before deploy (Aftermath ABI — from commented SDK code, may be stale):**
- `interface::deposit_collateral<T>(cap, coin)` — SDK shows args `[cap, coin]` with
  **no** ClearingHouse/Account/Clock. Confirm the real signature (does it need the
  shared `Account<T>` object too?).
- `interface::withdraw_collateral<T>(cap, amount): Coin<T>` — confirm it returns the coin.
- `start_session<T>(ClearingHouse, cap, basePriceFeed, collPriceFeed, Clock): SessionHotPotato<T>`,
  `place_market_order<T>(session, side: bool, size: u64)`, `end_session<T>(session)` —
  confirm the hot-potato lifecycle, the exact return of `end_session`, and whether
  `place_market_order` needs more (price bound / oracle update).
- The cap's real type + abilities (`key + store`?) and whether the admin cap is
  the right cap to custody (vs. a vault/admin cap variant).
- Mainnet ids: perp package `published-at`, `Registry`, per-market `ClearingHouse`
  (+ `initialSharedVersion`), oracle price-feed object ids, collateral coin type.

## Files
- `sources/adaptor.move` — the wrapper + ACL + Sup bridge (one module).
- `../dependencies/aftermath_perp/` — interface stub (struct shapes + `abort 0`
  bodies) so this package type-checks; replace `published-at`/`[addresses]` with
  the real mainnet ids at deploy.
- `Move.toml`.

## TS wiring (after deploy, separate step)
Mirror the Bluefin perp wiring: a `runAftermathPerp` tool (separate module merged
in the chat route), an `aftermathPerp` AgentRun card, and `/api/agent/run` actions
that build PTBs calling these adaptor functions with the agent key. The
`mainAccount`/account id + ClearingHouse/feed ids come from the Aftermath SDK reads.

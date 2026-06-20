# ADR — Settlement leg: `confirm_spend_into`, escrow + assessor, AP2 mapping

> Design record for turning Sup into "the self-custodial wallet for the agent
> economy" (see `Protocols/sup-wallet/POSITIONING.md`). Grounded in the current
> `SupWallet::policy` (read 2026-06-08) and a shipped reference rule
> (`official/policy_rule_oracle_price_guard`, builds + tests green).

## 0. Phase-0 findings (verified, not assumed)

From `sup_wallet/sources/policy.move`:

- `SpendRequest` is a hot potato with `{ wallet_id, coin, amount, recipient,
  policy_version, auth_receipts, caveat_receipts }`.
- `begin_spend<CoinT>(&wallet, amount, recipient) -> SpendRequest` is permissionless
  to *call*; the gate is at the end.
- Rules stamp via witness-gated `add_auth_receipt<R>(R{}, &mut req)` (OR) /
  `add_caveat_receipt<R>(R{}, &mut req)` (AND). A rule reads the request
  (`spend_amount/recipient/coin/wallet_id/policy_version`) but **cannot mutate it**.
- `confirm_spend<CoinT>(&mut wallet, req, ctx)` checks version + auth(OR) + caveat(AND),
  then `let paid = wallet::pay_by_policy<CoinT>(...)` and
  **`transfer::public_transfer(paid, recipient)`**.

**Gap:** `confirm_spend` always *transfers to `recipient`*. There is **no variant
that returns the `Coin`** to the PTB. That return primitive is the single missing
piece for funding escrow (and for composing a policy-bounded spend into a swap).
This matches roadmap item 1 in `DELEGATION_POLICY.md` (`confirm_spend_into`).

The rule pattern itself needs **no core change** — proven by
`policy_rule_oracle_price_guard` (a new condition-gated caveat rule that plugs in
purely through the public interface; "authority is a proof, not a password").

## 1. Decision: add `confirm_spend_into`

Add a sibling to `confirm_spend` that runs the identical gate but **returns** the
coin instead of transferring it, so a PTB can route it anywhere atomically (into a
`Job` escrow, a swap, etc.) while still being bounded by the owner's policy.

```move
/// Same gate as `confirm_spend`, but returns the coin to the caller's PTB
/// instead of paying `recipient`. The PTB is trusted to route it; `recipient`
/// is recorded as the *declared* destination for audit. Use to compose a
/// policy-bounded spend into escrow / a swap within one transaction.
public fun confirm_spend_into<CoinT>(
    wallet: &mut Wallet,
    req: SpendRequest,
    ctx: &mut TxContext,
): Coin<CoinT> {
    let SpendRequest {
        wallet_id, coin, amount, recipient, policy_version, auth_receipts, caveat_receipts,
    } = req;
    assert!(wallet_id == wallet::id(wallet), EWrongWallet);
    assert!(coin == type_name::with_defining_ids<CoinT>(), EWrongCoin);
    let policy = borrow(wallet);
    assert!(policy_version == policy.version, EStaleVersion);
    assert!(any_present(&policy.auth_rules, &auth_receipts), EAuthNotProven);
    assert!(all_present(&policy.caveat_rules, &caveat_receipts), EMissingCaveat);

    event::emit(SpendConfirmed { wallet_id, coin, amount, recipient, policy_version });
    wallet::pay_by_policy<CoinT>(wallet, amount, ctx)   // <-- returned, not transferred
}

/// `confirm_spend` becomes a thin wrapper (no behaviour change).
public fun confirm_spend<CoinT>(wallet: &mut Wallet, req: SpendRequest, ctx: &mut TxContext) {
    let recipient = req.recipient;                       // capture before move
    let paid = confirm_spend_into<CoinT>(wallet, req, ctx);
    transfer::public_transfer(paid, recipient);
}
```

Notes / open question:
- The existing `recipient` field becomes the *declared* destination for the
  `into` path (enforced by composition, not by the core). A stricter variant could
  take the destination object and assert `object::id(dest) == declared`. Decide
  per use case; for escrow, the `Job` id can be carried as `recipient`'s analogue
  or checked by the escrow module.
- `confirm_spend` keeps byte-for-byte behaviour — pure refactor, low risk. Add a
  test that the wrapper still pays `recipient`.

## 2. Decision: escrow `Job<CoinT>` + **the assessor IS a rule**

> **Your question — "8183 的評估部分怎麼搞?用 delegate policy rule?" — yes.**
> The assessor reuses the *exact same witness-stamp pattern* as auth/caveat rules.
> "Who may release escrow" becomes as pluggable as "who may delegate."

There are **two** policy-bounded moments, each gated by the same machinery:

```text
 FUND (out of the wallet, bounded by the owner's caps)
   begin_spend<CoinT>(amount→Job)            ← normal policy spend
     → cap/scoped auth stamps  (who)
     → caveats stamp           (budget / recipient=provider / price / time)
   confirm_spend_into<CoinT>()  →  Coin       ← the new primitive (§1)
   job::fund(&mut job, coin)                   ← coin now escrowed in the Job

 RELEASE (out of the Job, gated by the ASSESSOR)
   job::submit(&mut job, ...)                  ← provider marks work delivered
   assessor stamps the release                 ← *** this is a rule witness ***
   job::release(&mut job, assessor_proof, ...) ← pays the provider; or refund()
```

The escrow lives in a small package (not core), reusing Sui's escrow Move pattern:

```move
module sup_escrow::job {
    public struct Job<phantom CoinT> has key {
        id: UID,
        wallet_id: ID,        // who funded (the owner's vault)
        provider: address,    // who gets paid on success
        amount: u64,
        state: u8,            // 0 Open · 1 Funded · 2 Submitted · 3 Released · 4 Refunded
        funds: Balance<CoinT>,
    }

    /// Funded *through* a policy spend: the caller passes the coin returned by
    /// `policy::confirm_spend_into`, so the escrow amount is bounded by the
    /// owner's allowance — the agent can never escrow more than its cap.
    public fun fund<CoinT>(job: &mut Job<CoinT>, coin: Coin<CoinT>) { /* state→Funded */ }

    /// Release is GATED BY AN ASSESSOR WITNESS — structurally identical to how
    /// `policy` is gated by rule witnesses. `AssessorT` is whatever the owner
    /// trusts to judge delivery; only its defining module can build it.
    public fun release<CoinT, AssessorT: drop>(
        job: &mut Job<CoinT>, _assessor: AssessorT, registry: &AssessorRegistry, ctx: &mut TxContext,
    ) {
        assert!(registry.trusts<AssessorT>(job.id), ENotTrustedAssessor);   // owner opted in
        // pay job.funds → job.provider; state→Released
    }
}
```

The **assessor is just another rule package** — same ladder as auth rules:

| Assessor (who may release) | Rule |
| :--- | :--- |
| the owner themself signs off | a trivial `OwnerAssessor` (assert sender == owner) |
| an oracle / attestation says "delivered" | an oracle-reading assessor (like `oracle_price_guard`) |
| another agent / human reviewer holds a cap | a `CapAssessor` (bearer `AssessorCap`, mirrors `cap_auth`) |
| a ZK proof of completion verifies | a ZK assessor |
| an 8183 `Job` marked `Terminal` elsewhere | an adapter assessor |

So the **owner picks the assessor exactly like they pick auth rules** — opt-in,
permissionless to publish, swappable. The core never learns what "delivered"
means; it only sees "the trusted assessor stamped."

Refund path: if `submit` never happens (timeout) or the assessor rejects,
`job::refund` returns `funds` to the funding wallet — same shape, owner/timeout
gated.

## 3. Phase-2 (parallel, TS-level): AP2 Intent Mandate ⇄ Sup policy

AP2's **Intent Mandate** ("sign once, agent acts later, ≤ $X on category Y until
expiry") maps almost 1:1 onto a Sup scoped delegation. Make a Sup cap *importable
from* an AP2 mandate so Sup agents interoperate instead of siloing:

| AP2 Intent Mandate field | Sup policy construct |
| :--- | :--- |
| principal / agent key | `cap_auth::DelegateCap` or `sub_delegate::ScopedCap` to that key |
| max amount / budget | `ScopedCap` budget + a budget caveat |
| allowed merchant(s) | `policy_rule_recipient_allowlist` (the merchant addresses) |
| category / constraints | a category caveat rule (write per vertical) |
| expiry | a time-window caveat rule |
| price / FX bounds | `policy_rule_oracle_price_guard` (shipped) |

Deliverable: `mandateToPolicy(mandate) -> PTB` (mints the cap + attaches the
equivalent caveats). No core change; pure SDK + a couple of small caveat rules.

The framing this makes literal: **a Sup policy is an on-chain, enforced,
composable AP2 Intent Mandate** — not a signed credential a PSP honours, but a
rule the wallet contract enforces, gated by any condition (ZK / oracle / escrow).

## 4. Sequencing & open questions

1. ✅ **Ship a condition-gated rule** (`policy_rule_oracle_price_guard`) — done,
   builds + tests green. Proves the pattern with zero core change.
2. ✅ **`confirm_spend_into`** (§1) — landed in `policy.move`; `confirm_spend`
   refactored to a thin wrapper; `policy_tests` 8/8 green (incl. 2 new + regression).
3. ✅ **`sup_escrow::job` + `cap_assessor`** (§2) — the settlement leg / 8183.
   Landed in `official/sup_escrow/`; 4/4 tests green, incl. `funded_through_policy_spend`
   (escrow funded via `confirm_spend_into`, bounded by the owner's policy).
4. **AP2 mapping** (§3) — parallel, TS-first. *(next)*
5. **Demo:** "my agent hires another agent inside my wallet — funds into escrow,
   released only on delivery, all within my cap." *(wire the chat tools once §3 lands)*

Open questions to resolve in code:
- How much of conditional escrow does **Sui Payment Kit** cover vs. a standalone
  `lock`/shared-object escrow? (Verify before fixing §2 scope.) Payment Kit at
  minimum records the settlement receipt (Sup already uses it for subscriptions).
- `confirm_spend_into` destination enforcement: trust-the-PTB vs. assert-the-dest.
- Per-cap (not just mass `revoke_all`) revocation — needed once many agents hold caps.

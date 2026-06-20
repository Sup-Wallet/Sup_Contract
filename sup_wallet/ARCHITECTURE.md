# Sup Wallet — Programmable Delegation Architecture

One wallet core, one hot-potato primitive, three open marketplaces. A delegate is
not an address — it is *whoever or whatever can satisfy the rules an owner attaches
to their wallet*. Anyone can ship a new rule or adaptor without a PR.

Legend:  `✅ built & tested`   `🚧 roadmap`

---

## 1. The stack (and the ERCs it mirrors)

```
                         what an agent can DO with money
   ┌───────────────────────────────────────────────────────────────────┐
   │  🚧 ERC-8183  Agentic Commerce  — Job / escrow / assessor settle    │
   │      agents transacting WITH each other (post → fund → deliver →    │
   │      assess → settle). "Who releases escrow" = just another rule.   │
   ├───────────────────────────────────────────────────────────────────┤
   │  ✅ Delegation / Caveats (ERC-7710-ish) — how an agent MAY spend    │
   │      SupWallet::policy · cap_auth · sub_delegate                    │
   ├───────────────────────────────────────────────────────────────────┤
   │  ✅ ERC-8004  Identity / Discovery / Reputation — WHO an agent is   │
   │      adaptor_registry · policy_rule_registry                       │
   └───────────────────────────────────────────────────────────────────┘
                         all settling on  ✅ Sui SIP-58 custody (Wallet)
```

---

## 2. The core: one hot potato gates every delegated spend

```
   delegate / cap holder / contract / ZK / machine / 8183 assessor
                              │
                              │  policy::begin_spend<CoinT>(amount, recipient)
                              ▼
                  ┌────────────────────────┐        no `drop`: this MUST reach
                  │      SpendRequest       │        confirm_spend or the whole
                  │  (hot potato, facts)    │        transaction aborts.
                  │  wallet·coin·amount·    │
                  │  recipient·version      │
                  └───────────┬────────────┘
        rules stamp it │ (witness-gated; read-only on amount/recipient)
   ┌──────────────────┼───────────────────────────────┐
   │ AUTH rules (OR)   │            CAVEAT rules (AND)  │
   │ ≥1 must stamp     │            ALL must stamp      │
   │  AddressAuth      │             BudgetRule         │
   │  CapAuth        ✅ │             RecipientAllowlist ✅
   │  ScopedAuth     ✅ │             ScopedBudget     ✅
   │  ZkAuth        🚧 │             TimeWindow / Oracle 🚧
   └──────────────────┼───────────────────────────────┘
                              ▼
                  policy::confirm_spend<CoinT>()
                  ── checks: version current
                            ∧ ≥1 owner-trusted AUTH stamped
                            ∧ every owner-attached CAVEAT stamped
                  ── then withdraws & pays `recipient`
                              │
                              ▼
                       ✅ SupWallet::wallet  (SIP-58 custody, owner-set policy)
```

Safety: a rule receives `&SpendRequest` + a single stamp entrypoint. It can never
change the amount or recipient — only `abort`. So a malicious rule blocks only the
people who opted into it; it can never redirect or inflate a payment. Funds leave
the wallet **only at `confirm_spend`**, after all checks pass.

---

## 3. "A delegate can be anything" — the principal ladder

```
   address ─────────────▶ AddressAuth          (ctx.sender)
   key / agent / zkSend ─▶ CapAuth         ✅   holds a DelegateCap object
   contract ────────────▶ CapAuth         ✅   cap lives in the contract's field
   sub-delegate chain ──▶ ScopedAuth      ✅   attenuated, budget ≤ parent, depth+1
   ZK proof ────────────▶ ZkAuth          🚧
   another agent / 8183 ▶ AssessorAuth     🚧   escrow released when assessor stamps
```

Every one is the *same* mechanism: a module with a witness type that stamps the
request. Revocation is uniform — `policy::revoke_all` bumps a version and every
outstanding cap / sub-delegation tree dies at once.

---

## 4. Three open marketplaces, one pattern

```
   ┌─ ✅ adaptor_registry ─────────┐  where to spend  (Cetus / NAVI / Bucket / ...)
   ├─ ✅ policy_rule_registry ─────┤  how you may spend (auth + caveat rule blocks)
   └─ 🚧 assessor_registry ────────┘  who settles escrow (8183 Job evaluators)
        same shape: deploy a package → register its witness TypeName + package id +
        off-chain manifest. Permissionless. Reputation is event-derived off-chain.
        The registry is a directory, never a trust authority: nothing touches an
        owner's funds until that owner opts the rule into their own wallet policy.
```

Writing a rule is a ~30-line contract: a witness struct + an `enforce` that checks
a condition and stamps. See `policy_rule_recipient_allowlist` for a complete,
public-interface-only reference. (🚧 a rule-authoring agent skill will scaffold
this from a plain-language spec.)

---

## 5. What runs today

| Module / package | role | tests |
| --- | --- | --- |
| `SupWallet::wallet` | SIP-58 custody, owner policy, `pay_by_policy` | ✅ |
| `SupWallet::policy` | hot-potato engine (OR-auth / AND-caveat), revoke | ✅ 6 |
| `SupWallet::cap_auth` | `DelegateCap` bearer object + `CapAuth` | ✅ 5 |
| `SupWallet::sub_delegate` | `ScopedCap` attenuated sub-delegation | ✅ 7 |
| `SupWallet::delegate` | legacy address+budget path (unchanged) | ✅ 11 |
| `policy_rule_registry` | rule marketplace | ✅ |
| `policy_rule_recipient_allowlist` | reference third-party caveat rule | ✅ 2 |

Backward compatible: the original delegate-to-agent flow (`delegate.move` + the web
page) is untouched — all of its tests still pass. New capability is additive.

See `DELEGATION_POLICY.md` for the full design, APIs, and roadmap.

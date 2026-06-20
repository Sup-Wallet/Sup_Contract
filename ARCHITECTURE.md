# Sup Wallet — Architecture / 架構文件

**Status / 狀態**: SIP-58 migrated (testnet)
**Last update / 最後更新**: 2026-05-21
**Related / 相關文件**: `RFC/SIP58_ADOPTION.md`, `RFC/UNIFIED_MARGIN_ENGINE.md`

---

## 0. TL;DR

Sup Wallet 是 Sui 上的 **shared-object AA Wallet**：user 自己持有一個 shared `Wallet` 物件，wallet 內嵌一個 `Account` (signer) 對外簽發 `AccountRequest`。所有資產（fungible coin）走 SIP-58 address balance，所有對外操作走 witness-gated **intent 4 mode** + delegate dual-budget 雙層授權。Adaptor 是 wrap 外部協議的 Move package，分 official 跟 community 兩層。

Sup Wallet is a **shared-object AA (Account Abstraction) wallet** on Sui: the user owns a shared `Wallet` object that nests an `Account` (signer) capable of issuing `AccountRequest`. All fungible coin custody uses SIP-58 address balance; all service interactions go through the witness-gated **intent 4-mode flow** + delegate dual-budget. Adaptors are Move packages wrapping external protocols, split into official and community tiers.

---

## 1. Layer Overview / 分層

```
                           [USER (EOA / ZK Login)]
                                     │
                                     ▼
                  ┌───────────────────────────────────┐
                  │     Wallet (shared object)        │
                  │                                    │
                  │   owner: address                  │
                  │   signer: Account ───── identity ─┼──→ AccountRequest
                  │   delegate registry  ─── budgets ─┤
                  │   auth (service ↔ coin allowlist) │
                  │   coins → SIP-58 address balance  │
                  │   nfts  → ObjectBag (NFT)         │
                  └────────────────┬──────────────────┘
                                   │
                                   │
                                   ▼
                       ┌──────────────────────────┐
                       │   intent (core)          │
                       │     Mode A: self-pay     │
                       │     Mode B: pull-payer   │
                       │     Mode C: unmetered    │
                       │     Mode D: internal swap│
                       └────────────┬─────────────┘
                                    │ witness + receipt
                  ┌─────────────────┴─────────────────┐
                  ▼                                     ▼
        ┌──────────────────────┐         ┌──────────────────────┐
        │ official/            │         │ community/           │
        │   sup_subscription   │         │   <3rd-party adapter>│
        │   sup_inheritance    │         │                      │
        │   adaptor_mock_swap  │         │                      │
        └──────────────────────┘         └──────────────────────┘
```

---

## 2. Package Map / Package 結構

```
Sup_Contract/
├── sup_wallet/                      ← Core package
│   ├── sources/
│   │   ├── wallet.move              ── Wallet struct + SIP-58 deposit/withdraw + signer
│   │   ├── delegate.move            ── Dual-budget delegate registry + spend
│   │   ├── intent.move              ── 4-mode hot-potato payment/swap intent
│   │   └── adaptor.move             ── Thin convenience layer over intent
│   └── tests/
│
├── official/                        ← Sup core team-maintained services + adaptors
│   ├── sup_subscription/            ── Mode A/B 訂閱付款服務 (subscription service)
│   ├── sup_inheritance/             ── Mode C 繼承自動分配 (inheritance distribution)
│   └── adaptor_mock_swap/           ── Mode D 內部 swap 參考實作 (reference impl)
│
└── community/                       ← Third-party adaptors
    └── README.md                     ── 規範 + checklist
```

**外部依賴 / External dependencies**:
- `zzyzx_framework` — 提供 `account::Account` / `AccountRequest` + SIP-58 wrappers
- `sui-framework` testnet — SIP-58 (`send_funds`, `withdraw_funds_from_object`, `redeem_funds`)
- `usdc` (Circle stablecoin Move pkg) — 測試用

---

## 3. Core Types / 核心型別

### 3.1 `Wallet` (`sup_wallet::wallet`)

```move
public struct Wallet has key {
    id: UID,
    owner: address,              // EOA or upstream wallet address; rotatable
    signer: Account,             // Portable identity (zzyzx_framework::account)
    auth: LinkedTable<TypeName, vector<TypeName>>,
                                 // service ↔ allowed coin types (owner-managed)
    nfts: ObjectBag,             // NFTs only — SIP-58 doesn't apply
}
```

**Wallet 是 shared object**：必須透過 `&mut Wallet` 才能改 state。`owner` 是當前的「主人地址」，可透過 `assert_owner(ctx)` 比對 `ctx.sender()`。注意 wallet 本身沒有 transferable cap — 所有權靠 `owner` 欄位記錄。

The Wallet is a **shared object**: state mutation requires `&mut Wallet`. `owner` records the current EOA controller, asserted via `ctx.sender()`. There is no transferable cap object — ownership lives in the `owner` field.

### 3.2 Signer (`zzyzx_framework::account::Account`)

```move
public struct Account has key, store {
    id: UID,
    alias: Option<String>,       // ≤ 32 chars
}

public struct AccountRequest has drop {
    account: address,            // either ctx.sender() OR signer.id.to_address()
}
```

**Wallet 內嵌一個 `signer: Account`**，wallet 透過 `wallet.sign(ctx)` 簽發 `AccountRequest`（owner-gated）。`AccountRequest.address` = `signer.id.to_address()` = wallet 的「portable identity」，**同時也是 SIP-58 address balance 的 custody 地址**。第三方 `sui::coin::send_funds(coin, wallet.identity())` 就是寄錢給這個 address。

The Wallet nests one `signer: Account`. `wallet.sign(ctx)` (owner-gated) issues an `AccountRequest` whose `.address()` equals `signer.id.to_address()` — the wallet's **portable identity**, *also* the SIP-58 address-balance custody address. Third parties deposit via `sui::coin::send_funds(coin, wallet.identity())`.

### 3.3 Delegate (`sup_wallet::delegate`)

```move
public struct Delegate has store {
    main_owner: address,                          // copied from wallet.owner at init
    entries: Table<address, Entry>,
}

public struct Entry has store {
    by_service: KeyedBigVector,                   // ServiceT → u64 quota
    by_coin: KeyedBigVector,                      // CoinT → u64 quota
}
```

**Delegate registry** 用 DF 掛在 `wallet.id` 上，每個 delegate 有兩條獨立 budget（per-service / per-coin），spend 時 **AND-gated**（兩條都要扣得起）。`main_owner` 永遠 UNLIMITED budget（debit 是 no-op）。

The delegate registry hangs as a DF on `wallet.id`. Each delegate has two independent budgets (per-service / per-coin), both **AND-gated** at spend time. `main_owner` always has UNLIMITED budget (debits no-op out).

```
有效 budget = min(per-service quota, per-coin quota)
effective spend cap = min(per-service, per-coin)
```

### 3.4 Intent Hot Potatoes / Intent 熱馬鈴薯 (`sup_wallet::intent`)

四個 Mode 對應四種「服務支付」模式，每個 mode 都是 `request → validate → receipt → verify` 四步流程（hot potato 強制 single PTB）。

Four modes for four service-payment patterns. Each mode is a 4-step `request → validate → receipt → verify` flow enforced by hot potatoes (must complete in one PTB).

| Mode | 名稱 / Name | Sender | 額度扣 / Allowance debit | Use case |
|---|---|---|---|---|
| A | self-pay / 自付 | delegate or main_owner | service + coin (AND) | one-shot transfer, subscription start |
| B | pull-from-payer / 拉款 | service operator | payer's allowances | recurring subscription charge |
| C | unmetered / 無扣 | anyone | none | inheritance, cap-gated payout |
| D | internal swap / 內部 swap | delegate or main_owner | service + CoinIn (AND) | DEX swap inside wallet |

**Witness signing pattern**：每個 service 模組定義自己的 `ServiceT has drop {}`，只有那個 module 能 construct `ServiceT{}`，所以只有它能 sign request / receipt。

Each service module defines its own `ServiceT has drop {}`. Only the defining module can construct `ServiceT{}`, so only it can sign requests/receipts — type-level authority gate.

### 3.5 Reference Adapter Pattern / 參考 adapter 模式

There is **no** standalone helper module wrapping `intent::*`. Adapter authors
call `intent::*` directly — the 4-step flow is explicit and clear when written
out, and a wrapper layer would only add maintenance / audit cost with no
security benefit (the wrappers can't add gates that intent doesn't already
enforce via typed hot-potatoes).

沒有獨立的 helper module 包 `intent::*`。Adapter 直接 call `intent::*`，4 步流程
寫出來語意清楚；包一層只會增加維護 / audit 成本，沒 security 加值（wrapper
無法加 intent 透過 typed hot-potato 已強制的 gate）。

**Canonical reference** = [`official/adaptor_mock_swap`](official/adaptor_mock_swap)
— heavily commented copy-and-modify template. Replace `swap_external` with a
real protocol call and you have a working adapter.

Skeleton (Mode D):
```move
let sig = intent::request_swap<MyAdapter, CoinIn, CoinOut>(
    MyAdapter{}, amount_in, min_amount_out,
);
let (coin_in, ww) = intent::validate_and_swap_out(wallet, sig, ctx);
let coin_out = external_protocol::swap(coin_in, ctx);
let receipt = intent::create_swap_receipt<MyAdapter, CoinIn, CoinOut>(
    MyAdapter{}, amount_in, coin::value(&coin_out),
);
intent::verify_swap_and_credit(wallet, ww, receipt, coin_out);
```

---

## 4. Authorization Model / 授權模型

每次 service spend 經過 **4 層 gate**：

Every service spend traverses **4 authorization gates**:

```
┌─────────────────────────────────────────────────────────┐
│ Gate 1: Witness construction privacy                    │
│   只有 ServiceT 定義 module 能 construct ServiceT{}     │
│   Only the module defining ServiceT can build it        │
├─────────────────────────────────────────────────────────┤
│ Gate 2: wallet.auth[ServiceT] contains CoinType         │
│   owner 在 wallet 上明確 grant 這 service 能動這 coin    │
│   Owner explicitly granted this service to handle Coin  │
├─────────────────────────────────────────────────────────┤
│ Gate 3: Delegate per-service allowance                  │
│   spender 在這 service 上有夠的額度                      │
│   spender's per-service budget covers amount            │
├─────────────────────────────────────────────────────────┤
│ Gate 4: Delegate per-coin allowance                     │
│   spender 在這 coin 上有夠的額度（與 service 獨立）       │
│   spender's per-coin universal budget covers amount     │
└─────────────────────────────────────────────────────────┘
                  ↓ all 4 pass
             Coin<T> released
```

**main_owner shortcut**：sender == main_owner 時 Gate 3+4 視為 UNLIMITED（debit 是 no-op event）。`main_owner` 在 `delegate::initialize(wallet, ctx)` 時 snapshot 自 `wallet.owner`。

When sender == main_owner, Gates 3+4 short-circuit to UNLIMITED (debit emits a no-op event). `main_owner` is snapshot from `wallet.owner` at `delegate::initialize` time.

**Mode C 特例 / Mode C exception**：unmetered mode 只走 Gate 1+2，跳過 delegate 額度（適合 inheritance 等「cap-based 而非 budget-based」場景）。

Mode C unmetered only runs Gates 1+2, skipping delegate budgets — suited for cap-based authorization (e.g. inheritance).

---

## 5. Asset Storage (SIP-58) / 資產儲存

**Fungible coin** 走 SIP-58 address balance（鎖在 `signer.id.to_address()` 的 accumulator）：

```
Deposit  (anyone):           sui::coin::send_funds(coin, wallet.identity())

Withdraw (owner / service):  withdraw_internal<T>(wallet, amount, ...)
                              ─ 內部 call account::withdraw_funds<T>(&mut wallet.signer, amount)
                              ─ 再 coin::from_balance → Coin<T>

Read balance:                wallet::balance<T>(wallet, &AccumulatorRoot) → u64
                              ─ 需要系統共享物件 0xacc（off-chain 用 suix_getBalance RPC）
```

Fungible coins live on the SIP-58 accumulator at `signer.id.to_address()`. Anyone can deposit via `send_funds`. Withdrawal goes through `withdraw_funds_from_object(&mut signer.id, amt)`, witness-gated by `pay_by_service` (which is `public(package)`, only siblings can call).

**NFT**：仍走 `nfts: ObjectBag<String, T>`，因為 SIP-58 不適用於 `key`-only 物件。

NFTs still use `nfts: ObjectBag<String, T>` — SIP-58 only covers fungibles.

---

## 6. Lifecycle Flows / 生命週期

### 6.1 Wallet creation

```move
wallet::create(ctx)
    → 1. let signer = account::new(option::none(), ctx)
    → 2. let wallet = Wallet { owner: ctx.sender(), signer, ... }
    → 3. transfer::share_object(wallet)
    → 4. emit WalletCreated { wallet_id, owner, signer_address }
```

之後通常會跟 `delegate::initialize(wallet, ctx)` 一起呼叫（初始化 delegate registry，記下 main_owner）。

Usually paired with `delegate::initialize(wallet, ctx)` right after to seed the delegate registry (records `main_owner`).

### 6.2 Authorize a service to spend a coin / 授權服務動指定 coin

```move
// Owner-only
wallet::grant_service_coin<MyService, USDC>(wallet, ctx)
    → 1. assert_owner
    → 2. push USDC into auth[MyService]
    → 3. emit ServiceGranted

// To revoke later:
wallet::revoke_service_coin<MyService, USDC>(wallet, ctx)
wallet::revoke_service<MyService>(wallet, ctx)    // strips MyService entirely
```

### 6.3 Mode A — self-pay flow

```text
[adaptor module]
  // Step 1+2: get the coin out
  let sig = intent::request_payment<MyService, USDC>(MyService{}, 100, recipient);
  let (coin, ww) = intent::validate_and_pay<MyService, USDC>(wallet, sig, ctx);
  // ↑ 3 of 4 gates run inside validate_and_pay (auth + per-service + per-coin)

  // ... do something with `coin` (transfer / route through DEX / etc.) ...

  // Step 3+4: receipt + verify
  let receipt = intent::create_receipt_sig<MyService, USDC>(
      MyService{}, 100, recipient,
  );
  intent::verify_and_clear<MyService, USDC>(ww, receipt);
```

### 6.4 Mode B — pull-from-payer flow

```text
[adaptor (operator-side, e.g. subscription keeper)]
  // operator (ctx.sender) charges on behalf of `payer`.
  let sig = intent::request_payment_for_payer<MyService, USDC>(
      MyService{}, 100, treasury, payer_addr,
  );
  let (coin, ww) = intent::validate_and_pay_for_payer<MyService, USDC>(
      wallet, sig, ctx,
  );

  // ... transfer coin to treasury / deposit pool / etc. ...

  let receipt = intent::create_receipt_sig<MyService, USDC>(
      MyService{}, 100, treasury,
  );
  intent::verify_and_clear<MyService, USDC>(ww, receipt);
```

### 6.5 Mode D — internal swap flow

```text
[adaptor (e.g. cetus_adaptor)]
  // Step 1+2: pull CoinIn out of wallet
  let sig = intent::request_swap<CetusAdaptor, USDC, BTC>(
      CetusAdaptor{}, 1000_000_000, /* min_out */ 50_000,
  );
  let (coin_in, ww) = intent::validate_and_swap_out<CetusAdaptor, USDC, BTC>(
      wallet, sig, ctx,
  );

  // Step 3: external DEX swap
  let coin_out: Coin<BTC> = cetus::swap<USDC, BTC>(pool, coin_in, ctx);

  // Step 4+5: receipt + credit back
  let receipt = intent::create_swap_receipt<CetusAdaptor, USDC, BTC>(
      CetusAdaptor{}, 1000_000_000, coin::value(&coin_out),
  );
  intent::verify_swap_and_credit<CetusAdaptor, USDC, BTC>(
      wallet, ww, receipt, coin_out,
  );
  // ↑ asserts coin_out.value() == receipt amount_out, ≥ min_amount_out;
  //   pushes coin_out back into wallet.signer's address balance
```

完整、加註解的版本見 [`official/adaptor_mock_swap`](official/adaptor_mock_swap)
— **canonical copy-and-modify template**。

Full reference: [`official/adaptor_mock_swap`](official/adaptor_mock_swap).

---

## 7. Official Services & Adaptors / 官方服務與 Adaptor

### 7.1 `official/sup_subscription`

**訂閱付款服務**：service operator 發 subscription，user 主動 subscribe（Mode A），之後 operator 每月 trigger charge_fee（Mode B 從 user delegate 額度拉）。

Subscription service. Operator creates a `Service`; users `subscribe` (Mode A) and authorize delegates with per-service + per-coin allowances. Operator then periodically `charge_fee` (Mode B) pulls from the user's allowances.

**5/5 tests pass**。

### 7.2 `official/sup_inheritance`

**繼承自動分配**：owner 創建 inheritance plan，設定 inactivity 時間 + members + percentages。觸發後 members 用 MemberCap 走 Mode C unmetered 領取自己 percentage 份額。

Inactivity-triggered inheritance. Owner sets `time_left` + members + percentages. After the inactivity window lapses, members withdraw their share via Mode C using `MemberCap`.

⚠ **`member_withdraw` 接 `&AccumulatorRoot`**（讀 SIP-58 balance 算 share）。Production 直接用 `0xacc`。

⚠ `member_withdraw` takes `&AccumulatorRoot` to read SIP-58 balance for share calc. Production passes `0xacc` from PTB inputs.

**3/3 active tests pass**（4 個用 member_withdraw 的 test 被 block-comment，待 Sui 出 AccumulatorRoot test helper）。

3/3 active tests (4 disabled awaiting Sui AccumulatorRoot test helper).

### 7.3 `official/adaptor_mock_swap`

**Mode D 參考實作**：mock 一個 1:N rate external swap，演示 Wallet → adaptor → external DEX → Wallet 的完整 round trip + slippage assertion + auth check。

Reference Mode D adaptor mocking an external DEX swap at fixed `rate_num/rate_den`. Demonstrates the complete `Wallet → adaptor → external → Wallet` round trip plus slippage + auth-failure paths.

**3/3 tests pass**。

---

## 8. Community Adaptors / 社群 Adaptor

`community/` 是第三方 adaptor 的家。每個 adaptor 一個獨立 Move package，命名為 `<protocol>_adaptor/`。

`community/` hosts third-party adaptors. Each adaptor is its own Move package named `<protocol>_adaptor/`.

**規範 / Rules**：
- Adapter witness 只能有 `drop`（不能 `key` / `store`，避免被偷複製）
- 拉錢必須透過 `intent::*` 4 mode 之一（`wallet::pay_by_service` 是 `public(package)`，外部 package 本來就 call 不到）
- 不能改 `community/<your_adapter>/` 之外的檔案
- 測試必須過 `sui move test`
- Move.toml 用 `SupWallet = { local = "../../sup_wallet" }`
- 參考 [`official/adaptor_mock_swap`](official/adaptor_mock_swap) 範本

完整 checklist 見 [`community/README.md`](community/README.md)。

Full checklist in [`community/README.md`](community/README.md). The Sup team does **not** audit community packages — opt-in requires user-side review.

---

## 9. Testing / 測試

| Package | Tests | Notes |
|---|---|---|
| `sup_wallet` | 1/1 | 基本 deposit/withdraw round-trip |
| `official/sup_subscription` | 5/5 | Mode A/B + allowance cap edge cases |
| `official/sup_inheritance` | 3/3 (+4 TODO) | Setup / config only — `member_withdraw` tests deferred |
| `official/adaptor_mock_swap` | 3/3 | Mode D happy path + slippage + unauth |

**SIP-58 test_scenario 限制**：`AccumulatorRoot` (`0xacc`) 是 genesis-only 系統物件，`test_scenario` 沒 helper 可以 mock。任何讀 `wallet::balance<T>(wallet, root)` 或 `inheritance::member_withdraw` 的 test 都因此暫時無法跑 — 等 Sui 出 test helper 再補。

**SIP-58 test_scenario constraint**: `AccumulatorRoot` (`0xacc`) is genesis-only with no test helper. Tests that read `wallet::balance<T>(wallet, root)` or call `inheritance::member_withdraw` are deferred until Sui ships a test helper.

驗證手段：用 `take_from_sender<Coin<T>>` post-tx 拿 Coin object 驗證 amount，或檢查 delegate allowance 扣款數字。

Workaround: assert against post-tx `take_from_sender<Coin<T>>` value, or check delegate allowance debits.

---

## 10. Deployment / 部署

### Publish 順序 / Publish order

```
1. zzyzx_framework            (no internal deps)
2. sup_wallet                 (depends on zzyzx_framework)
3. official/sup_subscription  (depends on sup_wallet)
4. official/sup_inheritance   (depends on sup_wallet)
5. official/adaptor_mock_swap (depends on sup_wallet) [reference only]
6. community/<adaptor>/*      (anyone, depends on sup_wallet)
```

### Per-package commands

```bash
# Build + test core
cd zzyzx_framework         && sui move test
cd Sup_Contract/sup_wallet && sui move test

# Build + test services
cd Sup_Contract/official/sup_subscription && sui move test
cd Sup_Contract/official/sup_inheritance  && sui move test
cd Sup_Contract/official/adaptor_mock_swap && sui move test

# Publish (replace --gas-budget per network)
sui client publish --gas-budget 100000000
```

### AccumulatorRoot 依賴 / AccumulatorRoot dependency

任何 PTB 呼叫 `wallet::balance<T>(wallet, root)` 或 `inheritance::member_withdraw(... root ...)` 必須把 system shared object `0xacc` 加進 inputs。SDK 應該自動處理。

Any PTB calling `wallet::balance<T>(wallet, root)` or `inheritance::member_withdraw(... root ...)` must include the system shared object `0xacc` in its inputs. SDK should resolve this transparently.

---

## 11. Future / 未來

待補 / TBD：

| Item / 項目 | 描述 / Description |
|---|---|
| **AA wallet 整合 Sup → os_account** | Sup Wallet `sign(ctx) → AccountRequest` 直接餵給未來的 `os_account` (RFC `UNIFIED_MARGIN_ENGINE.md`)，wallet 變成 trading account 的 owner |
| **更多 official adaptors** | Cetus / Bucket PSM / Scallop / Navi 等 Mode D / Mode A 包裝 |
| **Sponsor gas adaptor** | 利用 SIP-58 stateless tx + accumulator gas → sponsor pays gas 給 wallet 行動 |
| **Withdraw queue / cooldown** | 防止 delegate / AI agent 大額瞬間 drain (借鏡 Astros epoch cap) |
| **Multi-signer** | 同 wallet 內掛多個 Account（per scope: trading / payment / yield） |
| **AccumulatorRoot test helper** | 等 Sui 上游補完後恢復 4 個 inheritance test + 加 wallet::balance 直接驗 |
| **Indexer schema doc** | 列出所有 events + 推導 wallet state 的 derivation rules |
| **Audit prep** | Formal invariants + threat model + test coverage report |

---

## 12. Decision Log / 決策軌跡

| Date | Decision | Rationale |
|---|---|---|
| 2026-05 | Shared object wallet (not owned by user) | Permissionless 3rd-party deposit / liquidation hooks; AA-native |
| 2026-05 | Owner = `address` field (not transferable cap) | Tracks EOA / ZK Login key directly; rotation via `set_owner` (future) |
| 2026-05 | Nested `signer: Account` for identity | Stable portable identity decoupled from `owner` rotation; same address serves as SIP-58 custody |
| 2026-05 | Delegate dual-budget (per-service AND per-coin) | More precise than single-quota; per-coin caps protect against service-side bug draining a specific token |
| 2026-05 | 4-mode intent (A/B/C/D) | Cover sender-pay / pull-payment / unmetered-cap / internal-swap separately — each has distinct auth semantics |
| 2026-05 | Adaptor as Move package per protocol | Modular upgrade / audit; user opts in per adaptor |
| 2026-05 | SIP-58 direct migration (not Path 1 wait / Path 3 hybrid) | SIP-58 already live; hybrid had 6 pain points; migration cost small |
| 2026-05 | Identity = `signer.id.to_address()` | One address serves identity + SIP-58 custody + AccountRequest |
| 2026-05 | `nfts` keeps ObjectBag | SIP-58 doesn't cover non-fungibles |
| 2026-05 | `member_withdraw` adds `&AccumulatorRoot` (Path A) | Minimal production change; test cost (4 disabled) acceptable |
| 2026-05 | `official/` + `community/` tier split | Q5 (b) — official audited, community user-opt-in |
| 2026-05 | Remove `sup_frame` | Demo redundant with adaptor_mock_swap (Mode D) + sup_subscription (Mode A/B) + sup_inheritance (Mode C) |
| 2026-05 | Drop `reclaim_coin` + `new_total` event field | Both needed cheap balance read; not worth `&AccumulatorRoot` plumbing |

---

## Appendix A — Module API Index / 模組 API 索引

### `sup_wallet::wallet`

```move
// Lifecycle
fun create(ctx)                                       // entry-only

// Owner management
fun assert_owner(wallet, ctx)                         // public(package)
fun owner(wallet): address
fun identity(wallet): address                          // signer-derived address
fun id(wallet): ID
fun uid(wallet): &UID
fun uid_mut(wallet): &mut UID                         // public(package)

// Auth registry (owner-only)
fun grant_service_coin<S, T>(wallet, ctx)
fun revoke_service_coin<S, T>(wallet, ctx)
fun revoke_service<S>(wallet, ctx)
fun is_authorized<S, T>(wallet): bool

// Signer access
fun signer_ref(wallet): &Account
fun sign(wallet, ctx): AccountRequest                 // owner-gated
fun set_signer_alias(wallet, alias, ctx)              // owner-only

// SIP-58 coin entry (owner-direct)
// Deposit uses sui::coin::send_funds(coin, wallet.identity()) directly.
fun take_coin<T>(wallet, amount, ctx)                 // owner-gated; transfers to sender

// SIP-58 coin entry (service-gated)
fun receive_from_service<S: drop, T>(wallet, coin, _witness)  // public
fun receive_from_service_internal<S, T>(wallet, coin)         // public(package)
fun pay_by_service<S, T>(wallet, amount, ctx): Coin<T>        // public(package)

// NFT entry (String-keyed ObjectBag)
fun add_asset<A: key + store>(wallet, asset, name, ctx)
fun reclaim_asset<A: key + store>(wallet, name, ctx)

// Read
fun balance<T>(wallet, &AccumulatorRoot): u64
```

### `sup_wallet::delegate`

```move
fun initialize(wallet, ctx)                           // owner-only, idempotent guarded
fun add(wallet, delegate, ctx)                        // owner-only
fun remove(wallet, delegate, ctx)                     // owner-only

// Per-service allowance (owner-only)
fun set_service_allowance<S>(wallet, delegate, amount, ctx)
fun increase_service_allowance<S>(wallet, delegate, delta, ctx)
fun decrease_service_allowance<S>(wallet, delegate, delta, ctx)

// Per-coin universal allowance (owner-only)
fun set_coin_allowance<T>(wallet, delegate, amount, ctx)
fun increase_coin_allowance<T>(wallet, delegate, delta, ctx)
fun decrease_coin_allowance<T>(wallet, delegate, delta, ctx)

// Spend (caller = main_owner OR registered delegate)
fun spend<S, T>(wallet, amount, recipient, ctx)        // simple shortcut

// Internal debit (public(package), used by intent)
fun debit_service_allowance<S>(wallet, spender, amount)
fun debit_coin_allowance<T>(wallet, spender, amount)

// Read
fun is_initialized(wallet): bool
fun main_owner(wallet): address
fun contains(wallet, delegate): bool
fun service_allowance<S>(wallet, who): u64
fun coin_allowance<T>(wallet, who): u64
```

### `sup_wallet::intent`

```move
// Mode A
fun request_payment<S: drop, T>(_witness, amount, recipient): ServiceSig<S, T>
fun validate_and_pay<S, T>(wallet, sig, ctx): (Coin<T>, WalletWitness<S, T>)

// Mode B
fun request_payment_for_payer<S: drop, T>(_witness, amount, recipient, payer): ServiceSigForPayer<S, T>
fun validate_and_pay_for_payer<S, T>(wallet, sig, ctx): (Coin<T>, WalletWitness<S, T>)

// Mode C
fun request_payment_unmetered<S: drop, T>(_witness, amount, recipient): ServiceSigUnmetered<S, T>
fun validate_and_pay_unmetered<S, T>(wallet, sig, ctx): (Coin<T>, WalletWitness<S, T>)

// Shared receipt (A/B/C)
fun create_receipt_sig<S: drop, T>(_witness, amount, recipient): ServiceReceiptSig<S, T>
fun verify_and_clear<S, T>(wallet_witness, receipt_sig)

// Mode D — internal swap
fun request_swap<S: drop, In, Out>(_witness, amount_in, min_amount_out): SwapSig<S, In, Out>
fun validate_and_swap_out<S, In, Out>(wallet, sig, ctx): (Coin<In>, WalletSwapWitness<S, In, Out>)
fun create_swap_receipt<S: drop, In, Out>(_witness, amount_in, amount_out): ServiceSwapReceipt<S, In, Out>
fun verify_swap_and_credit<S, In, Out>(wallet, wallet_witness, receipt, coin_out)
```

### `zzyzx_framework::account`

```move
// Lifecycle
fun new(alias: Option<String>, ctx): Account
entry fun create(alias: Option<String>, ctx)
fun update_alias(account, alias)

// AccountRequest issuance
fun request(ctx): AccountRequest                       // EOA path
fun request_with_account(&Account): AccountRequest     // Signer path (via use fun: account.request())

// Receive (TTO)
fun receive<T: key + store>(account, receiving): T

// SIP-58 wrappers
fun withdraw_funds<T>(account, amount): Balance<T>
fun send_funds<T>(account, coin)
fun send_balance<T>(account, balance)
fun balance_value<T>(account, &AccumulatorRoot): u64

// Getters
fun account_address(account): address
fun request_address(req): address
fun alias(account): &Option<String>
fun alias_length_limit(): u64
```

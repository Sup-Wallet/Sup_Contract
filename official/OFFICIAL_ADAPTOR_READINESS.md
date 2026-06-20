# Sup Wallet Official Adaptor Readiness

Date: 2026-06-21

This file tracks the pre-mainnet readiness of the official Sup Wallet adaptors.
It is intentionally stricter than "a Move package exists": an adaptor is only
demo-ready when there is also a frontend or agent PTB builder that can execute a
real product flow.

## Readiness Legend

- `Ready`: Move package, runtime mapping, UI/agent builder, and local validation
  evidence exist.
- `Partial`: Move package exists and is mapped, but the real protocol PTB builder
  or mainnet execution path is incomplete.
- `Fallback`: The Sup adaptor path is incomplete, but a user-signed direct SDK
  flow exists so the product can still be demonstrated outside managed-agent
  custody.
- `Blocked by SDK/API`: The protocol path is known, but current public SDK/API
  shape cannot be safely bundled or composed yet.

## Matrix

| Protocol | Official Move adaptor | Runtime/deploy mapping | Agent-managed vault flow | User-signed protocol flow | Status | Remaining work |
|---|---|---|---|---|---|---|
| Swap Aggregator / Cetus route | `adaptor_swap_aggregator`; legacy `adaptor_cetus` kept as fallback | `zzyzx.deploy-plan.json`, `zzyzx.ts` `swapAggregator` / `cetusLegacy` | `buildVaultSwap`, `runAgentSwap`, `runAgentCompose` | N/A | Ready / published | Run a tiny real mainnet swap once production slippage/fee settings are approved. |
| Cetus CLMM liquidity | `adaptor_cetus` managed custody functions added | deploy plan + runtime map; deployed package is still the legacy build | `runManagedClmmLiquidity`, `buildManagedClmmTx` | Legacy `prepareCetusLiquidity` / remove fallback remains | Build-ready, not published | Publish or upgrade `adaptor_cetus`, update deployment state, then run a small mainnet LP lifecycle. |
| Momentum CLMM liquidity | `adaptor_momentum` | deploy plan + runtime map | `runManagedClmmLiquidity`, `buildManagedClmmTx` | N/A | Build-ready, not published | Publish package and run a small mainnet LP lifecycle. |
| Turbos CLMM liquidity | `adaptor_turbos` | deploy plan + runtime map | `runManagedClmmLiquidity`, `buildManagedClmmTx` | N/A | Build-ready, not published | Publish package and run a small mainnet LP lifecycle. |
| Magma CLMM liquidity | `adaptor_magma` | deploy plan + runtime map | `runManagedClmmLiquidity`, `buildManagedClmmTx` | N/A | Build-ready, not published | Publish package and run a small mainnet LP lifecycle. |
| Scallop | `adaptor_scallop` | deploy plan + runtime map | `buildVaultScallop`, `runAgentScallop` | N/A | Ready | Keep Scallop package/version pins current. |
| Bucket | `adaptor_bucket` | deploy plan + runtime map | `buildVaultBucketBorrow`, `buildVaultBucketSavings`, `runBucketBorrow`, `runBucketSavings` | Direct Bucket SDK fallback when no Bucket account object is found | Ready with fallback | Broaden collateral/pool discovery as Bucket adds markets. |
| NAVI | `adaptor_navi` direct protocol-call source using ABI stub deps for NAVI protocol/oracle | deploy plan + runtime map, but no mainnet package id | `buildVaultNavi`, `runNaviSupply` when an owned AccountCap exists | Direct NAVI user-signed fallback when no AccountCap is found | Mainnet publish blocked; fallback demo-ready | ABI-stub source builds, but mainnet publish still fails against NAVI's upgraded package graph. Official-source deps were also tested and failed in the chain VM verifier. Keep direct-safe source; do not ship witness-only deposit because it cannot prove the coin reached NAVI. |
| Suilend | `adaptor_suilend` | deploy plan + runtime map | `buildVaultSuilend`, `runSuilendSupply` | N/A | Ready | Keep reserve parsing and current package id discovery in sync with Suilend upgrades. |
| Haedal | `adaptor_haedal` | deploy plan + runtime map | `buildVaultHaedal`, `runHaedalStake`/unstake run route | Direct Haedal user-signed flow remains available | Ready | Add delayed unstake / withdraw ticket support if needed. |
| Aftermath Perpetuals | `adaptor_aftermath` for vault LP coin custody surfaces | deploy plan + runtime map | Generic vault adaptor not wired into managed-agent run yet | `prepareAftermathPerpAccount`, `prepareAftermathPerpCollateral`, `prepareAftermathPerpOrder`, `prepareAftermathVault` | Ready as owner-signed flow; partial as Sup custody adaptor | Add official Aftermath vault begin/finish PTB builder if LP coin custody should stay inside Sup Wallet. Account withdrawals remain owner-signed/API driven. |
| Typus | `adaptor_typus` | deploy plan + runtime map | Generic begin/finish wrapper only; not used for DOV receipt objects | `prepareTypusDov`, `buildTypusDovDepositTx`, `buildTypusDovWithdrawTx`, `buildTypusDovRefreshTx` | Ready as owner-signed DOV flow; partial as Sup custody adaptor | DOV receipts remain in the user's wallet by design. Add a protocol-linked Sup custody path only if Typus exposes coin-like shares or a stable receipt custody model. |
| Ember | `adaptor_ember` | deploy plan + runtime map | `buildVaultEmberDeposit`, `runEmberVaultDeposit` when manual vault config is supplied | None | Ready for manual-config deposit; partial for redeem/discovery | Ember's public deployment/vault API returned RBAC denied during research, so deposit requires admin-supplied package/protocol-config/vault/receipt types. Redeem is async withdrawal-request flow and must not use `finish_redeem` until a returned asset coin path is available. |
| Current | `adaptor_current_lending` (replaces retired `adaptor_current`) | deploy plan + runtime map | Obligation-cap custody: agent supply/borrow/withdraw/repay + multiply/margin building blocks | `prepareCurrentSupply`, `buildCurrentSupplyTx`, `adaptor_current_lending` | Owner-signed supply ready; agent-signed custody adaptor DRAFT (builds; ABI verified vs live pkg; audit + deploy pending) | Generic `adaptor_current` (share/begin-finish) RETIRED — Current deposits are obligation-based (`ObligationOwnerCap`, no share coin), which that wrapper couldn't represent. `adaptor_current_lending` custodies the cap. (Old `adaptor_current` pkg `0x97fe2aaa…` stays on-chain, unused.) |
| Bluefin | `adaptor_bluefin_margin` (replaces retired `adaptor_bluefin`) | deploy plan + runtime map | Account/position custody: agent perp-margin deposit (Pro) + spot add/remove/collect liquidity (Spot CLMM) | `prepareBluefinProDeposit`, `buildBluefinProDepositTx`, `adaptor_bluefin_margin` | Owner-signed Pro deposit ready; agent-signed custody adaptor DRAFT (builds; ABIs verified vs official repos; audit + deploy pending) | Generic `adaptor_bluefin` (vault/share begin-finish) RETIRED — neither Pro margin (`deposit_to_asset_bank`, no share coin) nor Spot CLMM (Position NFT) returns a fungible share. `adaptor_bluefin_margin` custodies the bound account / CLMM position. (Old `adaptor_bluefin` pkg `0x440ace5e…` stays on-chain, unused.) Withdraw is sequencer-signed/off-chain. |

## Mainnet Package Snapshot

Fresh runtime published on 2026-06-06:

- `sup_wallet`: `0x24434ef7d9e99049d969974717bbd7b920d3453c5628ee344822709ca66d1de0`
- `sup_subscription`: `0x8185975a83503589a12fb1a72f98b077e9d7f55871e90951603735b289a66587`
- `sup_inheritance`: `0x002e2f312ef9147e41f4faf500b7dd6aa0d6a235e38a1d9cb3d6b58172d1f30d`
- `adaptor_os_account`: `0xa83e4f02cc8e79ffef5c84c872c1eb0a104a50c8d6a34e9831bdf47a81c2c3e8`
- `adaptor_scallop`: `0xb11945ed5af1db2f77a72c8ce3a1a496f97083cba005e0bea938fdb1a66dce75`
- `adaptor_bucket`: `0xdf370c2f803d960015d7c2459ec4847bf0ff6853c823ffab3d7271865a639637`
- `adaptor_navi`: `0x276fbfa00e2abac3af0ede75de92a98f86ad7039c813596717775f575671eaad`
- `adaptor_cetus`: `0x685e64a469c0b99d031cb2c65f1ea72c2d55ac8cd0b7ffaba1a5502d96fa2af5`
- `adaptor_swap_aggregator`: `0xe402340a91bfc20d6ec41b0ed2a97aaa8953aee6e077903fd253912e13209c66`
- `adaptor_haedal`: `0xfe25951ca4bd9d76fd2326efc632f2f5a07ba54bc8a0d5656c95d2d0ca4b80b9`
- `adaptor_suilend`: `0x0d4bc41e021c2e1cf5c1d914c340cea3c69339f392ce7964645d383bdebf24ef`
- `adaptor_typus`: `0xee569d70d6def745b346c83698f4c817417ec56a3707ea137ccc9c7f9975a270`
- `adaptor_ember`: `0x2096b8147527730fb49a563bf9827135118b990002f42ad3b6dd998f87926f2e`
- `adaptor_current`: `0x97fe2aaa3f29cea4fa502498e83695beca0a1a869d5a2f46bb90b5b3e6ce255a`
- `adaptor_aftermath`: `0x332e7a359c00de82a9265a4658771b024429d1d30ed902fb00196146f665b980`
- `adaptor_bluefin`: `0x440ace5ee4f914a05c82bf8b9232193737024a34fb039b30999b4997babadd59`

NAVI publish is no longer blocked. The fresh publish used
`adaptor_navi` no-tree-shaking TransactionKind plus explicit NAVI transitive
dependencies in `Protocols/deploy/zzyzx.deploy-plan.json`.

## Current Evidence

Move adaptor packages are present under `official/adaptor_*` for:

- `adaptor_scallop`
- `adaptor_bucket`
- `adaptor_navi`
- `adaptor_cetus`
- `adaptor_momentum`
- `adaptor_turbos`
- `adaptor_magma`
- `adaptor_swap_aggregator`
- `adaptor_haedal`
- `adaptor_suilend`
- `adaptor_typus`
- `adaptor_ember`
- `adaptor_current`
- `adaptor_aftermath`
- `adaptor_bluefin`

Deploy plan coverage is in `Protocols/deploy/zzyzx.deploy-plan.json`, and web
runtime package/service-type resolution is in
`Protocols/sup-wallet/apps/web/src/lib/zzyzx.ts`.

Mainnet deployment state was checked against Sui normalized modules on
2026-06-05. Every published `adaptor_*` package recorded in
`Protocols/deployments/zzyzx.mainnet.json` resolved an `adaptor` module with the
expected exposed functions, including `adaptor_swap_aggregator::begin_swap` /
`finish_swap`, `adaptor_scallop::deposit` / `withdraw`,
`adaptor_bucket::borrow_usdb` / `save_usdb`, and the vault begin/finish wrappers
for Suilend, Typus, Ember, Current, Aftermath, and Bluefin.

Agent-managed vault builders currently exist for:

- `Protocols/sup-wallet/apps/web/src/lib/agent/cetus-swap.ts`
- `Protocols/sup-wallet/apps/web/src/lib/agent/clmm-liquidity.ts`
- `Protocols/sup-wallet/apps/web/src/lib/agent/scallop.ts`
- `Protocols/sup-wallet/apps/web/src/lib/agent/bucket.ts`
- `Protocols/sup-wallet/apps/web/src/lib/agent/navi.ts`
- `Protocols/sup-wallet/apps/web/src/lib/agent/suilend.ts`
- `Protocols/sup-wallet/apps/web/src/lib/agent/haedal.ts`
- `Protocols/sup-wallet/apps/web/src/lib/agent/ember.ts` (manual-config
  deposit only)

Owner-signed protocol builders currently exist for:

- `Protocols/sup-wallet/apps/web/src/lib/mainnet-defi/cetus-liquidity.ts`
- `Protocols/sup-wallet/apps/web/src/lib/mainnet-defi/aftermath-perps.ts`
- `Protocols/sup-wallet/apps/web/src/lib/mainnet-defi/typus-dov.ts`
- `Protocols/sup-wallet/apps/web/src/lib/mainnet-defi/current-lending.ts`
- `Protocols/sup-wallet/apps/web/src/lib/mainnet-defi/bluefin-pro.ts`
- legacy direct NAVI/Bucket/Haedal builders under `mainnet-defi/`

Repeatable owner-signed builder smoke is in
`Protocols/sup-wallet/apps/web/scripts/qa-mainnet-builders.ts`. It builds
transaction kinds without signing or submitting. Current coverage:

- Current SUI supply: full PTB kind build.
- NAVI direct SUI deposit fallback: full PTB kind build.
- Haedal SUI stake fallback: full PTB kind build.
- Aftermath Perpetuals USDC account creation: full PTB kind build.
- Typus DOV SUI deposit: discovers a live SUI `DepositVault` from the Typus DOV
  registry and builds the deposit PTB kind.
- Bluefin Pro USDC deposit: live ABI check for `deposit_to_asset_bank` taking
  `&mut Coin<T>`; full PTB build runs automatically when the QA sender has USDC.
- Cetus CLMM SUI/USDC add-liquidity: pool/quote path is checked and full PTB
  build runs automatically when the QA sender has enough USDC for the non-SUI
  side.
- Managed Sup-vault adaptor builder smoke for Scallop SUI deposit, Suilend SUI
  deposit, and Haedal SUI stake. The script resolves a live Sup Wallet fixture
  from `WalletCreated` events, or uses `SUP_QA_WALLET_ID` when provided. These
  are transaction-kind builds only; they do not prove the fixture wallet has
  coin balances, authorization grants, or delegate allowances.
- Managed Bucket adaptor builder smoke is gated on a real Bucket `Account`
  object. The script auto-detects accounts for the fixture owner with Bucket SDK
  `getUserAccounts({ address })`, or accepts `SUP_QA_BUCKET_ACCOUNT_ID` plus
  `SUP_QA_BUCKET_EXPECTED_ACCOUNT`. If the fixture owner has no Bucket account,
  it warns instead of constructing an invalid PTB.

## Security Boundaries

- A protocol is not agent-executable just because it has a generic begin/finish
  adaptor. The external protocol call must return a concrete output coin that
  is passed into `finish_*`, or the adaptor cannot prove funds reached the
  intended protocol/product.
- Account-based products must bind the external account id to the Sup Wallet, or
  require the owner as signer. Delegate-signed calls must not be able to route
  vault funds into a delegate-owned external account.
- Sponsored transaction wrappers are not compatible with Sup begin/finish PTB
  composition unless they expose a normal appendable `Transaction` and returned
  output coin object.

## Validation Snapshot

The following local commands passed on 2026-06-21:

- `sui move test` in `sup_wallet`: 31/31.
- `sui move build` in `adaptor_cetus`, `adaptor_momentum`,
  `adaptor_turbos`, and `adaptor_magma`.
- `bun run typecheck` in `Protocols/sup-wallet/apps/web`.
- `bunx tsc --noEmit` in `Protocols/sup-wallet/apps/mobile`.
- Targeted `git diff --check` for the new custody, adaptor, web, mobile, and
  deployment files. Vendored Cetus upstream sources retain upstream CRLF line
  endings and are excluded from the whitespace-only check.

Managed CLMM positions use a service-scoped ObjectBag key in Sup Wallet.
Open/add/remove/collect/close take and return the Position NFT atomically in the
same PTB. No separate user signature is required to transfer the Position NFT;
the only owner signature is the normal one-time adapter/coin allowance grant.

The following local commands passed on 2026-06-05:

- `sui move test` in `adaptor_swap_aggregator`: 3/3
- `sui move test` in `adaptor_typus`: 4/4
- `sui move test` in `adaptor_ember`: 3/3
- `sui move test` in `adaptor_current`: 3/3
- `sui move test` in `adaptor_aftermath`: 4/4
- `sui move test` in `adaptor_bluefin`: 4/4
- `sui move test` in `adaptor_suilend`: 3/3
- `sui move test` in `adaptor_haedal`: build passed, 0 tests
- `sui move test` in `adaptor_scallop`: build passed, 0 tests
- `sui move test` in `adaptor_bucket`: build passed, 0 tests
- `sui move build --silence-warnings --allow-dirty --build-env mainnet` in
  `adaptor_navi`: passed against NAVI ABI stub dependencies. Native publish
  still fails against NAVI's upgraded package linkage; the official-source
  publish attempt also failed with `VMVerificationOrDeserializationError`.
- `sui move test` in `adaptor_cetus`: build passed, 0 tests
- `bun run typecheck` in `Protocols/sup-wallet/apps/web`: passed after adding
  Current and Bluefin owner-signed builders
- `bunx tsc --noEmit` in `Protocols/sup-wallet/apps/mobile`: passed after
  adding Current and Bluefin user-tx cards
- `bun run build` in `Protocols/sup-wallet/apps/web`: passed after adding
  Current and Bluefin owner-signed builders
- `git diff --check`: passed
- `bun run qa:mainnet-adaptors` from `Protocols`: passed via Node-backed
  `scripts/qa-mainnet-adaptors.mjs`; every published adaptor package resolved
  the expected normalized `adaptor` module functions. `adaptor_navi` remains a
  not-published warning.
- `bun run qa:swap-aggregators` in `Protocols/sup-wallet/apps/web`: passed for
  Cetus Aggregator V3, Aftermath Router, and 7K / Bluefin7K SUI -> USDC
  quote/build transaction-kind smoke tests
- `npm run check` and `npm run providers:check` in
  `Protocols/sup-wallet/sidecars/swap-aggregators`: passed. FlowX SDK isolated
  imports expose `AggregatorQuoter` / `TradeBuilder`; Astros CJS isolated import
  exposes `getQuoteInternal` / `buildSwapPTBFromQuote`. Local sidecar `/health`
  smoke returned providers `flowx` and `astros`.
- Sup Wallet web `buildVaultSwap` now supports sidecar providers behind
  `SUP_SWAP_SIDECAR_URL` and `SUP_SWAP_PROVIDERS=...,flowx,astros`. The default
  provider order remains `cetus,aftermath,sevenk`.
- `npm run qa:append-swap` in
  `Protocols/sup-wallet/sidecars/swap-aggregators`: passed for FlowX and Astros.
  It builds no-sign Sup Wallet `begin_swap -> sidecar route -> finish_swap`
  transaction kinds for SUI -> USDC without submitting.
- `bun run qa:swap-settlement-preflight` in `Protocols/sup-wallet/apps/web`:
  passed as a read-only mainnet preflight. It resolved the latest live Sup
  Wallet fixture
  `0xab11d4cc3f6988c582f5fc87f9d4ad6b87552b98ef00bda031123c2127f6c734`,
  owner
  `0xfda6e13618acc15c496ae0a65b887055b7d27ab868e2024ed73d307f3fc0fdf0`,
  and SIP-58 custody identity
  `0xb271f7676b16bfbb10e65b5741262a339b5e133d3f6b495c097f00c91f2a72c4`.
  The preflight correctly warned that this fixture currently has zero vault SUI,
  no `SwapAggregatorAdaptor` grant for SUI, and no service / coin allowance for
  the default QA spender. A real signed Sup-vault swap therefore still needs
  vault funding plus owner authorization before settlement will pass.
- `bun run qa:swap-settlement-setup` in `Protocols/sup-wallet/apps/web`: passed
  as a no-submit transaction-kind build for the missing owner setup. It builds
  the PTB that funds the wallet identity with `0.01` SUI, initializes delegate
  state, adds the default QA spender as delegate, grants `SwapAggregatorAdaptor`
  on SUI, and sets both required allowances to `0.01` SUI. The latest setup kind
  length was `854` bytes.
- `bun run qa:swap-settlement-smoke` in `Protocols/sup-wallet/apps/web`: passed
  as a no-submit managed-agent smoke build. It resolves the same wallet fixture,
  performs the preflight read, quotes a live SUI -> USDC aggregator route, and
  builds the complete `begin_swap -> route -> finish_swap` transaction kind.
  Latest no-submit build used a Cetus Aggregator route over
  `CETUS+METASTABLE+AFTERMATH` with `kindBytes=2133`. With
  `SUP_SWAP_SMOKE_DRY_RUN=1`, it correctly skipped dry-run because preflight is
  still not ready.
- `bun run qa:mainnet-builders` from `Protocols`: passed for Current SUI
  supply, NAVI direct SUI deposit, Haedal SUI stake, Aftermath Perpetuals USDC
  account creation, and Typus DOV SUI deposit transaction-kind smoke tests.
  The Typus smoke discovered live index `126` (`SUI-10 Minutely-Call`) from the
  DOV registry. It also built managed Sup-vault adaptor PTBs for Scallop SUI
  deposit, Suilend SUI deposit, and Haedal SUI stake using the latest discovered
  Sup Wallet fixture `0xab11d4cc...`. The managed Bucket check warned because
  that fixture owner currently has no Bucket `Account`; set
  `SUP_QA_BUCKET_ACCOUNT_ID` / `SUP_QA_BUCKET_EXPECTED_ACCOUNT` to build Bucket
  borrow and saving PTBs against a real account fixture. Bluefin Pro deposit ABI
  check passed; Bluefin USDC deposit and Cetus SUI/USDC add-liquidity PTB builds
  were skipped with warnings because the QA sender only held SUI.

## Next Implementation Queue

1. Resolve NAVI publish linkage with NAVI/Mysten guidance or replace the Move
   direct adaptor with an officially supported AccountCap integration surface.
2. Execute one tiny mainnet Sup-vault swap through the published
   `adaptor_swap_aggregator` once production slippage/fee settings are approved
   and the owner setup PTB from `bun run qa:swap-settlement-setup` has been
   signed. Then require `bun run qa:swap-settlement-preflight -- --strict` to
   pass for the funded, authorized QA wallet, run
   `SUP_SWAP_SMOKE_DRY_RUN=1 bun run qa:swap-settlement-smoke`, then execute the
   smoke swap with explicit submit env vars and record the digest.
3. Execute tiny signed sidecar-route Sup-vault swaps once the QA wallet has
   required vault balances, service grants, and delegate allowance.
4. Decide whether Typus DOV receipt custody should remain user-owned
   owner-signed flow, or whether Sup Wallet needs a new receipt-object custody
   model. Do not force DOV receipt objects through the generic coin-share
   adaptor.
5. Add a stable Ember vault discovery source or admin config UI, then implement
   async withdrawal-request handling separately from `finish_redeem`.
6. Extend Current beyond owner-signed supply only after a dedicated
   account-bound adaptor or official SDK path can prove the destination
   obligation/account. Do not route Current market deposit through the generic
   coin-share `finish_deposit`.
7. Extend Bluefin beyond owner-signed margin deposit only after the Pro
   account/API signature lifecycle is modelled in Sup, or a dedicated
   account-bound adaptor proves the destination account for delegate-signed
   custody.

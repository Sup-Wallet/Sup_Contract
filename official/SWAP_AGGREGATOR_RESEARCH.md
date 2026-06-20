# Sup Wallet Swap Aggregator Research

Date: 2026-06-06

## Problem

The legacy `adaptor_cetus` path is a direct Cetus CLMM pool swap. It is useful as
a fallback, but it loses the main advantage of modern Sui swap aggregators:
multi-hop, split routing, and cross-DEX liquidity.

## Architecture Decision

Use one generic on-chain Sup adaptor and keep provider-specific routing in the
PTB builder:

1. `begin_swap<CoinIn, CoinOut>` debits `CoinIn` from the Sup Wallet and returns
   the coin plus a `WalletSwapWitness`.
2. The TypeScript builder inserts official aggregator SDK route commands.
3. `finish_swap<CoinIn, CoinOut>` consumes the witness, verifies `amount_out >=
   min_out`, and credits `CoinOut` back to the Sup Wallet.

This keeps wallet authorization and slippage enforcement on-chain, while avoiding
hard-coding every aggregator's package graph in Move.

## Implemented Baseline

Package: `official/adaptor_swap_aggregator`

- `SwapAggregatorAdaptor` service witness.
- `begin_swap` / `finish_swap` hot-potato flow.
- Unit coverage for happy path, slippage abort, and missing authorization abort.
- Sup Wallet runtime maps adapter key `cetus` to this package once deployed.
- Existing `adaptor_cetus` remains as `cetusLegacy` fallback before deployment.

## Cetus Aggregator

Sources:
- Docs: https://cetus-1.gitbook.io/cetus-developer-docs/developer/cetus-aggregator/getting-started
- GitHub: https://github.com/CetusProtocol/aggregator

Findings:
- Cetus recommends Aggregator V3 for builders.
- V3 route endpoint is `https://api-sui.cetus.zone/router_v3/find_routes`.
- The SDK exposes `findRouters` and `routerSwap`; `routerSwap` can accept an
  input coin object and return the target coin object for further PTB use.
- Cetus Aggregator already routes across many Sui liquidity sources, including
  FlowX, Aftermath, Bluefin, DeepBook v3, Scallop, Suilend, Haedal, and 7K in
  newer versions.
- Cetus docs list Aggregator V3 package metadata separately from the SDK. The
  current docs show `AggregatorV3` package
  `0x33ec64e9bb369bf045ddc198c81adbf2acab424da37465d95296ee02045d2b17`
  published-at
  `0xde5d696a79714ca5cb910b9aed99d41f67353abb00715ceaeb0663d57ee39640`,
  plus router packages for Cetus, Aftermath, FlowX, SevenK, DeepBookV3, and
  others. The frontend should still rely on SDK-provided package config unless
  we have a controlled reason to override it.
- Docs currently show SDK `1.4.8`, but npm reports
  `@cetusprotocol/aggregator-sdk@1.5.7` as of 2026-06-06. Keep npm pinned and
  periodically compare docs/package metadata before mainnet deploys.
- Cetus says mainnet is fully supported, while testnet coverage is limited to
  Cetus and DeepBook providers. Sup production swap routing should therefore be
  treated as mainnet-only.

Status:
- Integrated as the default provider behind `adaptor_swap_aggregator`.
- `runAgentSwap` now uses true aggregator routes after deployment.
- The web app uses a provider interface so additional aggregators can be added
  without changing the Move adaptor.
- Current production providers: Cetus Aggregator V3, Aftermath Router, and
  7K / Bluefin7K Aggregator. The default quote order is
  `cetus,aftermath,sevenk`; the best `amountOut` wins.
- Web dependency updated to `@cetusprotocol/aggregator-sdk@1.5.7` after checking
  the current npm release on 2026-06-05.
- Repeatable QA script:
  `Protocols/sup-wallet/apps/web/scripts/qa-swap-aggregators.ts`. It quotes
  SUI -> USDC and appends each provider route into a PTB transaction kind
  without signing or submitting.

## 7K

Sources:
- Docs: https://docs.7k.ag/7k-aggregator/integration
- SDK: https://github.com/7k-ag/7k-sdk-ts

Findings:
- 7K explicitly asks integrators not to modify the 7K aggregator smart contract.
- The SDK is mainnet-oriented and supports swaps, price feeds, limit orders, DCA,
  and a Meta Aggregator path.
- Its MetaAg layer can compare providers such as Bluefin7K, FlowX, and Cetus.
- Current README notes optional dependencies for FlowX/Cetus providers and a
  transport caveat for some Cetus/Pyth/DeepBook routes.
- 7K's public developer page now points at `@7kprotocol/sdk-ts`. npm reports
  `@7kprotocol/sdk-ts@4.0.0`, while the GitHub README has already moved toward
  newer `@mysten/sui` peer guidance. This needs dependency isolation before
  importing into the Next.js app directly.
- Our current implementation uses
  `@bluefin-exchange/bluefin7k-aggregator-sdk@7.3.0`, which still gives us
  appendable `getQuote` / `buildTx` behavior. Treat it as a production route
  provider for now, then spike official `@7kprotocol/sdk-ts` in the sidecar.

Status:
- Integrated as a production provider behind the same Sup `begin/finish` adaptor.
- The selected SDK version is
  `@bluefin-exchange/bluefin7k-aggregator-sdk@7.3.0`.
- `getQuote` is used for live route discovery, and `buildTx` is called with
  `extendTx: { tx, coinIn }`, so the route is appended between
  `begin_swap` and `finish_swap`.
- The provider checks that `swapAmountWithDecimal` equals the exact amount pulled
  from the vault, preventing any residual input coin from being routed outside
  the Sup wallet flow.
- BluefinX sponsored sources are filtered out. They return a sponsored
  transaction wrapper instead of a normal appendable `Transaction`, so they do
  not fit the Sup PTB composition path.
- Optional env:
  `SUP_7K_API_KEY`, `SUP_BLUEFIN_AGGREGATOR_API_KEY`,
  `SUP_7K_ENDPOINT_PROVIDER`, `SUP_7K_SOURCES`,
  `SUP_7K_COMMISSION_PARTNER`, and `SUP_7K_COMMISSION_BPS`.
- Next migration target: add a sidecar provider for official
  `@7kprotocol/sdk-ts` and compare its quote/build output against the current
  Bluefin7K provider before replacing the default.

## FlowX

Sources:
- Swap Aggregator docs: https://docs.flowx.finance/developer/flowx-sdk/swap-aggregator
- Meta SDK docs: https://docs.flowx.finance/developer/additional-documents/meta-sdk
- GitHub: https://github.com/FlowX-Finance/sdk

Findings:
- FlowX has an aggregator quote/build flow and a Meta SDK for Sui-based DEX
  aggregators.
- The published root bundle exposes `AggregatorQuoter` and `TradeBuilder`; the
  documented `MetaAgQuoter` currently appears in `.d.ts` but is not root-exported
  by the 2.1.0 package bundle, so the production integration uses the universal
  router path instead.
- `Trade.swap({ tx, coinIn, client })` accepts a caller-provided input coin and
  returns the output coin object, which is compatible with Sup
  `begin_swap`/`finish_swap`.
- FlowX supports custom exchange selection and slippage configuration.
- The FlowX SDK 2.1.0 dependency tree imports old `@mysten/sui.js@0.54.1` at
  bundle top level. In the Sup Wallet workspace this conflicts with the existing
  `@mysten/bcs@2.0.3` override and breaks `next build` before runtime.

Status:
- Not enabled in the default production web provider order yet.
- A dependency-isolated sidecar now exists at
  `Protocols/sup-wallet/sidecars/swap-aggregators`. It uses FlowX
  `AggregatorQuoter` + `TradeBuilder` and appends routes to a serialized Sup
  `begin_swap` transaction before adding `finish_swap`.
- The web provider can opt into this path with `SUP_SWAP_SIDECAR_URL` and
  `SUP_SWAP_PROVIDERS=...,flowx`.
- The sidecar keeps FlowX's old `@mysten/sui.js` and older transitive peers out
  of the Next.js bundle.
- Slippage should be passed as basis points to `TradeBuilder.slippage()`,
  matching the SDK implementation (`new Percent(slippage, BPS)`).

## Aftermath

Sources:
- SDK docs: https://docs.aftermath.finance/for-developers/typescript-sdk
- Router docs: https://docs.aftermath.finance/for-developers/typescript-sdk/products/router
- SOR docs: https://docs.aftermath.finance/trade/smart-order-router

Findings:
- Aftermath's SOR supports multi-DEX and split-route execution.
- The TypeScript SDK exposes `Router()`, route discovery, and transaction builders.
- Router docs include `addTransactionForCompleteTradeRoute`, which is the right
  direction for composing into an existing PTB.
- Current package typings also expose `coinInId?: TransactionObjectArgument` for
  appending a route to a serialized transaction, which looks compatible with the
  Sup-returned input coin.
- SDK 2.1.0 has a clean dependency graph for this app: peer `@mysten/sui >=2 <3`
  and dependency `date-fns`.
- Aftermath docs note not every protocol is on testnet, but protocols are on
  mainnet.

Status:
- Integrated as the second production provider.
- `buildVaultSwap` lets a provider return an updated `Transaction`; this supports
  Aftermath's serialized-PTB append API while preserving Sup's `swapWitness`.
- Compose flow now adopts each returned `plan.tx`, so Aftermath routes can still
  be followed by later Sup adaptor steps in the same PTB.

## Astros

Sources:
- App/site: https://astros.ag/
- Docs / UI SDK: https://naviprotocol.gitbook.io/astros/astros-dex-aggregator/images-and-media
- npm: `@naviprotocol/astros-aggregator-sdk@1.14.2`

Findings:
- Astros now has a NAVI-maintained aggregator package:
  `@naviprotocol/astros-aggregator-sdk`.
- The package exposes `getQuote` plus `buildSwapPTBFromQuote`, which accepts an
  existing `Transaction` and caller-provided input coin result. That is
  compatible with Sup's `begin_swap` output shape in principle.
- The README says Astros supports order splitting, multi-hop routing, and
  currently lists Aftermath, Bluefin, Cetus, DeepBook V3, Magma, Momentum, and
  Turbos; FlowX is listed as upcoming.
- The package peer range is `@mysten/sui >=1.25.0` and includes dependencies
  such as `axios`, `bignumber.js`, `crypto-js`, `dotenv`, and `shio-sdk`.

Status:
- Spiked in the Sup Wallet web workspace on 2026-06-05 with
  `@naviprotocol/astros-aggregator-sdk@1.14.2`.
- Not enabled in the default production web provider order yet. The package ESM
  root imports named `SuiClient` from `@mysten/sui/client`; this workspace uses
  `@mysten/sui@2.16.3`, where that v1/v1.38 client export is not available. A
  direct ESM runtime import fails before any quote call can run.
- The package's submodules are not exported as usable package subpaths, and the
  JavaScript bundle is root-bundled, so the app cannot safely import only
  `getQuote` / `buildSwapPTBFromQuote` to bypass the incompatible top-level
  export.
- The dependency-isolated sidecar loads the Astros CJS bundle with
  `createRequire`, which successfully exposes `getQuoteInternal` and
  `buildSwapPTBFromQuote` without putting the package in the web bundle.
- The web provider can opt into this path with `SUP_SWAP_SIDECAR_URL` and
  `SUP_SWAP_PROVIDERS=...,astros`.

## Security Notes

- The Sup Move adaptor enforces source-coin authorization and `min_out`.
- The hot-potato `WalletSwapWitness` prevents a PTB from debiting the vault
  without returning a valid swap receipt.
- The provider builder must pass the returned output coin to `finish_swap`; do not
  add arbitrary `transferObjects` or fee side effects unless those are explicitly
  surfaced to the user and bounded.
- Aggregator SDKs should be treated as routing builders, not custody logic. Sup
  owns custody policy.

## Next Provider Work

1. Execute one tiny signed Sup-vault swap through each sidecar route once the QA
   wallet has the required Sup Wallet balance/grants and production slippage
   settings are approved.
2. Keep legacy `adaptor_cetus` as fallback only; all new routing should use
   `adaptor_swap_aggregator`.
3. Before calling the swap path production-complete, execute one tiny mainnet
   Sup-vault swap through Cetus Aggregator and one quote/build through either
   Aftermath or 7K, then record the digest / provider route summary here.

## QA Snapshot

Commands run on 2026-06-06:

```bash
sui move test --silence-warnings --allow-dirty
bun run qa:swap-aggregators
cd Protocols/sup-wallet/sidecars/swap-aggregators
npm run check
npm run providers:check
npm run qa:append-swap
```

Result:

- `adaptor_swap_aggregator` Move tests: 3/3 passed.
- Cetus Aggregator V3: quote/build ok for SUI -> USDC, 3 route paths.
- Aftermath Router: quote/build ok for SUI -> USDC, 1 route.
- 7K / Bluefin7K: quote/build ok for SUI -> USDC, 2 routes.
- FlowX SDK root import ok with `AggregatorQuoter` and `TradeBuilder`.
- Astros SDK CJS import ok with `getQuoteInternal` and
  `buildSwapPTBFromQuote`.
- `npm run qa:append-swap` builds no-sign Sup Wallet
  `begin_swap -> sidecar route -> finish_swap` transaction kinds:
  FlowX latest sample `FlowX MetaAg: FERRA_DLMM+STEAMM - 1 route`,
  `kindBytes=5978`; Astros latest sample `Astros Aggregator: route - 1 route`,
  `kindBytes=1547`.

Open production gap:

- These QA checks build transaction kinds and verify provider composition, but
  they do not submit a signed mainnet Sup-vault swap. The final readiness gate
  is one tiny signed swap through the deployed generic adaptor, then record the
  digest and provider route summary.

Previous settlement fixture notes from 2026-06-05:

- Local `/health` smoke returned providers `flowx` and `astros`.
- Local `/quote` smoke for SUI -> USDC returned FlowX amountOut around `7082`
  atomic USDC and Astros amountOut around `7039` atomic USDC for 0.01 SUI. These
  are live quotes and will vary over time.
- `bun run qa:swap-settlement-preflight` performs a read-only mainnet settlement
  readiness check for the active Sup Wallet fixture. It resolved wallet
  `0xab11d4cc3f6988c582f5fc87f9d4ad6b87552b98ef00bda031123c2127f6c734`
  and identity
  `0xb271f7676b16bfbb10e65b5741262a339b5e133d3f6b495c097f00c91f2a72c4`,
  then warned that the fixture currently has no vault SUI, no
  `SwapAggregatorAdaptor` SUI grant, and no default-spender service / coin
  allowance. This means quote/build is ready, but signed settlement still needs
  a funded and authorized QA wallet.
- `bun run qa:swap-settlement-setup` builds the missing owner-signed setup PTB
  for that fixture without submitting it. The current build plan is:
  fund wallet identity with `10000000` SUI atomic, initialize delegate registry,
  add delegate
  `0x5ecc10b19d081efbcb7118cc96dee2c54a356ff07fb991b390674acb69a8a262`,
  grant `SwapAggregatorAdaptor` on SUI, and set both service and SUI coin
  allowances to `10000000`. It built a transaction kind of `854` bytes.
- `bun run qa:swap-settlement-smoke` builds the managed-agent smoke swap after
  the same preflight read. In no-submit mode it built a full Sup Wallet SUI ->
  USDC aggregator transaction kind. Latest live route sample:
  `Cetus Aggregator: CETUS+METASTABLE+AFTERMATH - 3 legs`, `kindBytes=2133`.
  Because preflight is not ready yet, `SUP_SWAP_SMOKE_DRY_RUN=1` correctly skips
  dry-run instead of simulating a transaction that would abort.

The web QA proves Cetus, Aftermath, and 7K can build appendable transaction
kinds. The sidecar QA proves FlowX and Astros SDKs can be isolated, loaded, and
appended to a Sup Wallet swap PTB. The preflight proves whether the selected
Sup Wallet has the balance, service grant, and delegate allowances required for
settlement; the smoke script then gives the signed-execution harness, gated
behind explicit submit env vars.

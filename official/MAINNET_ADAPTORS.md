# Sup Wallet Mainnet DeFi Adaptors

These packages are on-chain Sup Wallet adaptor contracts. They intentionally call the
protocol-level public functions that return coins/balances or record positions against an
explicit account object. Do not replace them with protocol entry functions that write to
`ctx.sender()` unless the wallet identity model is changed.

## Scallop

Package: `official/adaptor_scallop`

Functions:
- `adaptor_scallop::adaptor::deposit<Underlying, SCoin>`
- `adaptor_scallop::adaptor::withdraw<SCoin, Underlying>`

Mainnet objects:
- Scallop `Version`: `0x07871c4b3c847a0f674510d4978d5cf6f960452795e8ff6f189fd2088a3f6ac7`
- Scallop `Market`: `0xa757975255146dc9686aa823b7838b507f315d704f428cbadad2f4ea061939d9`
- `SCoinTreasury<SCoin, Underlying>`: use Scallop's per-asset sCoin treasury object.

Wallet grant:
- Deposit grants `ScallopAdaptor` on `Underlying`.
- Withdraw grants `ScallopAdaptor` on `SCoin`.

## Bucket

Package: `official/adaptor_bucket`

Functions:
- `borrow_usdb<Collateral>`
- `borrow_usdb_from_position<Collateral>`
- `save_usdb<LP>`
- `save_usdb_with_incentive<LP, Reward>`
- `withdraw_saving<LP>`
- `withdraw_saving_with_incentive<LP, Reward>`

Mainnet objects:
- Bucket package config: `0x03e79aa64ac007d200aefdcb445e31e24f460279bab6c73babfb031b7464072e`
- USDB `Treasury`: `0x4de1c29a89d6888ebf8f7ae20364571dce4e1e42b9c9221f7df924ad6f9e617d`
- Saving incentive `GlobalConfig`: `0x50ffe3535b157841e9ff0470fff722192c90b86b4dee521de0b27b03b44b20f5`
- Pass the concrete Bucket `Account` object and `expected_account = account::account_address(&Account)`.
- Pass the market-specific `Vault<Collateral>`, `SavingPool<LP>`, `RewardManager<LP>`, and oracle `Option<PriceResult<Collateral>>` from Bucket's SDK/config flow.

Wallet grant:
- Borrow with new collateral grants `BucketAdaptor` on `Collateral`.
- Saving deposit grants `BucketAdaptor` on `USDB`.
- Withdraw/borrow from existing Bucket position does not spend a Sup Wallet coin, but still requires the Bucket account object/capability in the PTB.

Frontend / agent notes:
- The official Sup Bucket path requires an owned Bucket `Account` object. The
  agent auto-detects it with Bucket SDK `getUserAccounts({ address })`; if none
  exists, the UI falls back to the legacy direct Bucket SDK PTB where the user
  signs with their own wallet.
- Owner authorization can batch `bind_external_account<BucketAdaptor>(account)`,
  `grant_service_coin<BucketAdaptor, CoinT>` when an input coin is pulled from
  the Sup vault, and managed-agent caps.
- Borrow with fresh collateral pulls `Collateral` from the Sup vault and credits
  borrowed `USDB` back to the vault. Borrow-from-existing-position and saving
  withdraw require only the external account binding, not a coin grant.
- Saving deposit grants `USDB`; saving withdraw credits returned `USDB` back to
  the Sup vault.

## NAVI

Package: `official/adaptor_navi`

Functions:
- `adaptor_navi::adaptor::deposit<CoinT>`
- `adaptor_navi::adaptor::withdraw<CoinT>`

Mainnet publish status:
- Source builds and keeps the safe direct NAVI protocol-call path.
- The current worktree uses narrow ABI stub dependencies for NAVI protocol and
  oracle modules. This keeps the adaptor source direct and auditable while
  avoiding a large vendored dependency tree in the package.
- Mainnet publish is currently blocked by NAVI's upgraded package linkage. Native
  `sui client publish` with the ABI stubs fails with
  `PublishUpgradeMissingDependency`; adding discovered type-origin package ids
  fails with `InvalidLinkage`.
  Latest current-stub dry-run evidence:
  `5GQcfijBxvYdDu691mRWZwMMqFLjCanFMcmdZeBY5MNs` (epoch 1149).
- A separate publish attempt using NAVI official `lending_core` / `oracle`
  sources also failed on chain with
  `VMVerificationOrDeserializationError`
  (`13dsB9JSDgyMYt82urQV8ju8LW343tGBMGeqrwifj6yy`).
- Do not import `@naviprotocol/lending@1.4.6` directly in the Sup Wallet web
  bundle. A runtime spike on 2026-06-05 showed that package imports
  `getFullnodeUrl` from `@mysten/sui/client`, which is incompatible with this
  workspace's `@mysten/sui@2.16.3`. Keep the direct user-signed fallback on the
  API-config + hand-built PTB path unless NAVI publishes a v2-compatible SDK or
  the SDK is isolated in a sidecar.
- Do not replace this with a witness-only deposit adaptor: without the direct
  NAVI call inside Move, the adaptor cannot prove the released coin was
  deposited into NAVI.

Mainnet objects:
- Storage: `0xbb4e2f4b6205c2e2a2db47aeb4f830796ec7c005f88537ee775986639bc442fe`
- PriceOracle: `0x1568865ed9a0b5ec414220e8f79b3d04c77acc82358f6e5ae4635687392ffbef`
- IncentiveV2: `0xf87a8acb8b81d14307894d12595541a73f19933f88e1326d5be349c7a6f7559c`
- IncentiveV3: `0x62982dad27fb10bb314b3384d5de8d2ac2d72ab2dbeae5d801dbdb9efa816c80`
- Sui system state: `0x5`
- Pass the pool-specific `Pool<CoinT>`, NAVI `asset_id`, and the user's `AccountCap`.
- `expected_account_owner` must equal `account::account_owner(&AccountCap)`.

Wallet grant:
- Deposit grants `NaviAdaptor` on `CoinT`.
- Withdraw does not spend a Sup Wallet coin.

Frontend / agent notes:
- NAVI's own docs require an `AccountCap` for external-contract integrations;
  the Sup agent therefore auto-detects an owned `::account::AccountCap` when
  possible, or accepts an explicit `accountCapId`.
- Deposit authorization batches three owner actions when needed:
  `bind_external_account<NaviAdaptor>(owner)`, `grant_service_coin<NaviAdaptor,
  CoinT>`, and the managed-agent cap grants.
- If no AccountCap is found, the UI falls back to the legacy direct NAVI PTB
  where the user signs with their own wallet and the result belongs to the user
  wallet rather than the Sup vault.
- Source references: NAVI's "Integration with Account Cap" developer page and
  live `https://open-api.naviprotocol.io/api/navi/config?...` / `pools?...`
  endpoints.

## Suilend

Package: `official/adaptor_suilend`

Functions:
- `adaptor_suilend::adaptor::begin_deposit<Underlying, CToken>`
- `adaptor_suilend::adaptor::finish_deposit<Underlying, CToken>`
- `adaptor_suilend::adaptor::begin_withdraw<CToken, Underlying>`
- `adaptor_suilend::adaptor::finish_withdraw<CToken, Underlying>`

Scope:
- PTB-native official wrapper for Suilend lending. It intentionally does not
  link to Suilend's frequently-upgraded protocol packages.
- Deposit PTB shape:
  `begin_deposit` debits `Underlying` from Sup Wallet and returns a hot-potato
  witness; Suilend SDK inserts `depositLiquidityAndGetCTokens`; `finish_deposit`
  verifies `min_ctoken_out` and credits `CToken` back to Sup Wallet.
- Withdraw PTB shape:
  `begin_withdraw` debits `CToken`; Suilend SDK inserts redeem/withdraw
  commands; `finish_withdraw` verifies `min_amount_out` and credits
  `Underlying` back to Sup Wallet.

Wallet grant:
- Deposit grants `SuilendAdaptor` on `Underlying`.
- Withdraw grants `SuilendAdaptor` on the Suilend `CToken`.

Frontend / agent notes:
- The web/mobile agent now builds the Suilend PTB directly from the official
  SDK call shape without importing the full SDK bundle. It reads the mainnet
  `LendingMarket` object for reserve indexes / mint decimals and reads the
  Suilend `UpgradeCap` for the current published package id.
- Deposit route:
  `begin_deposit` -> `lending_market::deposit_liquidity_and_mint_ctokens` ->
  `finish_deposit`.
- Withdraw route:
  `begin_withdraw` -> `option::none<RateLimiterExemption>` ->
  `lending_market::redeem_ctokens_and_withdraw_liquidity_request` ->
  optional `unstake_sui_from_staker` for SUI -> `fulfill_liquidity_request` ->
  `finish_withdraw`.
- The active run path remains deployment-gated by `adaptor_suilend` in
  `zzyzx.mainnet.json`.

## Haedal

Package: `official/adaptor_haedal`

Functions:
- `adaptor_haedal::adaptor::stake`
- `adaptor_haedal::adaptor::unstake_instant`

Mainnet objects:
- Haedal latest package used for dependency linkage: `0x126e4cfb051cad744706df590ec399e8c02b6feae195c35b8b496280d5442a62`
- Haedal original/type-origin package: `0xbde4ba4c2e274a60ce15c1cfff9e5c42e41654ac8b6d906a57efa4bd3c29f47d`
- Staking shared object: `0x47b224762220393057ebf4f70501b6e657c3e56684737568439a04f80849b2ca`
- haSUI coin type: `0xbde4ba4c2e274a60ce15c1cfff9e5c42e41654ac8b6d906a57efa4bd3c29f47d::hasui::HASUI`
- Sui system state: `0x5`

Scope:
- `stake` pulls SUI from the Sup Wallet, calls Haedal
  `staking::request_stake_coin`, verifies `min_hasui_out`, and credits haSUI
  back to the Sup Wallet.
- `unstake_instant` pulls haSUI from the Sup Wallet, calls Haedal
  `staking::request_unstake_instant_coin`, verifies `min_sui_out`, and credits
  SUI back to the Sup Wallet.
- Use Haedal's `0x0` validator address for auto-routing, or pass a concrete
  validator address for manual staking.

Wallet grant:
- Stake grants `HaedalAdaptor` on SUI.
- Instant unstake grants `HaedalAdaptor` on haSUI.

## Cetus

Package: `official/adaptor_cetus`

Functions:
- `adaptor_cetus::adaptor::swap_a_to_b<CoinTypeA, CoinTypeB>`
- `adaptor_cetus::adaptor::swap_b_to_a<CoinTypeA, CoinTypeB>`
- `adaptor_cetus::adaptor::open_position_from_vault<CoinTypeA, CoinTypeB>`
- `adaptor_cetus::adaptor::add_liquidity_from_vault<CoinTypeA, CoinTypeB>`
- `adaptor_cetus::adaptor::remove_liquidity_to_vault<CoinTypeA, CoinTypeB>`
- `adaptor_cetus::adaptor::collect_fees_to_vault<CoinTypeA, CoinTypeB>`
- `adaptor_cetus::adaptor::collect_reward_to_vault<CoinTypeA, CoinTypeB, Reward>`
- `adaptor_cetus::adaptor::close_empty_position<CoinTypeA, CoinTypeB>`

Mainnet objects:
- GlobalConfig: `0xdaa46292632c3c4d8f31f23ea0f9b36a28ff3677e9684980e4438403a67a3d8f`
- Pass the concrete Cetus CLMM `Pool<CoinTypeA, CoinTypeB>`.
- `sqrt_price_limit` should come from the Cetus SDK quote path for the chosen direction.

Scope:
- This adaptor is direct single-pool CLMM swap via `pool::flash_swap` + `repay_flash_swap`.
- It is not the Cetus aggregator and does not do multi-hop routing.

Wallet grant:
- `swap_a_to_b` grants `CetusAdaptor` on `CoinTypeA`.
- `swap_b_to_a` grants `CetusAdaptor` on `CoinTypeB`.

LP / position management:
- `runManagedClmmLiquidity` opens and operates the position with the managed
  agent key.
- The Position NFT is stored directly in Sup Wallet ObjectBag under a
  service-scoped string key. Opening the position, adding liquidity, and storing
  the NFT happen in one PTB; there is no user-signed NFT transfer.
- Remove, fee/reward collection, and close temporarily take the NFT from
  storage, call Cetus, then put it back or destroy it atomically. All coin output
  is credited to the Sup Wallet.
- Pool discovery first tries the Cetus CLMM SDK stats endpoint and falls back to
  Cetus Aggregator direct-CETUS route discovery when the stats response shape is
  unavailable.

## Momentum / Turbos / Magma CLMM

Packages:
- `official/adaptor_momentum`
- `official/adaptor_turbos`
- `official/adaptor_magma`

Each package exposes:
- `open_position_from_vault`
- `add_liquidity_from_vault`
- `remove_liquidity_to_vault`
- `collect_fees_to_vault`
- `collect_reward_to_vault`
- `close_empty_position`

They use the same Sup Wallet custody model as Cetus: `positionName` is a
service-scoped ObjectBag key, the managed agent signs the PTB, and the Position
NFT never needs to be transferred to the user.

## Aftermath Perpetuals / Vault UX

Frontend package: `Protocols/sup-wallet/apps/web/src/lib/mainnet-defi/aftermath-perps.ts`

Scope:
- Owner-signed Aftermath Perpetuals flows built with `aftermath-ts-sdk@2.1.0`.
- `prepareAftermathPerpAccount` creates a user-owned Aftermath perp account for
  a collateral coin.
- `prepareAftermathPerpCollateral` deposits or withdraws collateral against the
  user's owned `AccountCap`.
- `prepareAftermathPerpOrder` builds a market order against a discovered
  Aftermath market and the user's current account snapshot.
- `prepareAftermathVault` supports Aftermath Perpetuals vault deposit and
  withdraw-request flows.

Design notes:
- These are deliberately user-signed, not managed-agent-signed. The relevant
  permissions are Aftermath `AccountCap`, vault LP coins, and account snapshots,
  which are owned by the user's wallet rather than by the Sup agent key.
- Deposit-style flows can optionally fund from the Sup vault in the same
  owner-signed PTB by prepending `wallet::withdraw_coin` and passing the returned
  coin object into the Aftermath SDK builder.
- Market order size currently uses a P0 9-decimal base-size conversion in the
  transaction card. A production trading ticket should read each market's
  `lotSize` / `scalingFactor` and enforce exact stepper increments before
  signing.
- Mainnet dry SDK query on 2026-06-05 returned 21 USDC-collateral markets and 21
  vaults, confirming the SDK/API discovery path is live.

## Typus DOV UX

Frontend package: `Protocols/sup-wallet/apps/web/src/lib/mainnet-defi/typus-dov.ts`

Scope:
- Owner-signed Typus DOV v2 receipt flows built from the current
  `@typus/typus-sdk` call shape and live Typus config at
  `Typus-Lab/typus-config`.
- `prepareTypusDov` creates user-signed cards for:
  deposit, withdraw/reduce, and receipt snapshot refresh.
- Deposit can optionally fund from the Sup vault by prepending owner-gated
  `wallet::withdraw_coin`, converting the coin into a `Balance`, then calling
  `tds_user_entry::public_raise_fund`.
- Withdraw/reduce calls `tds_user_entry::public_reduce_fund` with the user's
  owned `TypusDepositReceipt` object(s) and transfers returned balances to the
  connected wallet.
- Refresh calls `tds_user_entry::public_refresh_deposit_snapshot` and transfers
  the refreshed `TypusDepositReceipt` back to the connected wallet.

Design notes:
- Typus DOV positions are represented by `TypusDepositReceipt` objects, not a
  normal fungible share coin. The safe demo path is therefore user-signed:
  the receipt stays in the user's wallet.
- `adaptor_typus` remains useful for Typus products that return concrete
  share/receipt coins that can be passed to `finish_deposit` or `finish_redeem`.
  Do not force DOV receipt-object flows through the generic coin-share adaptor.
- Withdraw share amounts are raw Typus share integers (`reduceFromWarmup` /
  `reduceFromActive`); production UI should query receipt/vault data and render
  a safer amount picker before signing.

## Ember Vault Deposit

Frontend package: `Protocols/sup-wallet/apps/web/src/lib/agent/ember.ts`

Scope:
- Managed-agent, Sup-custody deposit into an Ember Sui vault.
- The builder does not import the full `@ember-finance/sdk` bundle. It uses the
  current SDK's Move call shape directly:
  `begin_deposit` -> `0x2::coin::into_balance` ->
  `ember::vault::deposit_asset_v2` -> `finish_deposit`.
- `runEmberVaultDeposit` requires admin/user supplied Ember config:
  `emberPackageId`, `protocolConfigId`, `vaultId`, `depositCoinType`, and
  `receiptCoinType`. Ember's public vault deployment API returned RBAC denied
  during research, so Sup must not auto-guess these ids.

Wallet grant:
- Deposit grants `EmberAdaptor` on the deposit asset coin.
- The Ember receipt/share coin is credited back into the Sup Wallet by
  `finish_deposit`, subject to `minSharesOut`.

Known boundary:
- Ember redeem is an asynchronous withdrawal-request flow
  (`gateway::redeem_shares`) and does not return an asset coin in the same PTB.
  Do not wire it through generic `begin_redeem` / `finish_redeem` unless a
  later Ember API exposes a concrete returned asset coin or a separate
  withdrawal-credit flow.
- Production should add an admin config surface for approved Ember vault ids and
  a quote path for `minSharesOut`; the current managed path is intentionally
  manual-config for pre-mainnet demo use.

## Current Finance Supply

Frontend package: `Protocols/sup-wallet/apps/web/src/lib/mainnet-defi/current-lending.ts`

Scope:
- Owner-signed Current Finance supply/deposit demo flow.
- The builder is hand-built from Current's current app bundle ABI because no
  public SDK/GitHub package was found during research.
- PTB shape:
  1. Optional `wallet::withdraw_coin` if the user checks "Fund from Sup vault".
  2. `enter_market::enter_market_return<Market>` creates an
     `ObligationOwnerCap`.
  3. `deposit::deposit<Market, Asset>` supplies the input coin.
  4. The `ObligationOwnerCap` is transferred to the user's wallet.

Tracked mainnet ids:
- Protocol package:
  `0xfe1d8929d13b00aaecd7642dec1c6d41cab82882a1b139efa46bf61dfd6380bf`
- Protocol app:
  `0xd4395f77a48f6d64af2008280c8dc06ee0fe69953a141e683935f6086d849177`
- Markets: `MainMarket`, `AltCoinMarket`, `EmberMarket` as hard-coded in the
  frontend builder.

Design boundary:
- Current market deposit is account/obligation based and does not return a
  fungible share coin in the same PTB. The generic share-style `adaptor_current`
  (begin/finish_deposit) was therefore RETIRED — there is no `Coin<Share>` to
  prove and credit back into Sup Wallet.
- Owner-signed supply (`prepareCurrentSupply`) is the live path. Managed-agent
  Current custody is now `adaptor_current_lending`, which custodies the
  `ObligationOwnerCap` (vault-parented + ACL) and exposes agent supply/borrow/
  withdraw/repay + multiply/margin building blocks (DRAFT — audit + deploy pending).
- Borrow and withdraw are not wired yet. Current's app bundle shows they require
  oracle refresh / `x_oracle` arguments and a user-owned `ObligationOwnerCap`.

## Bluefin Pro Deposit

Frontend package: `Protocols/sup-wallet/apps/web/src/lib/mainnet-defi/bluefin-pro.ts`

Scope:
- Owner-signed Bluefin Pro margin funding flow.
- `prepareBluefinProDeposit` fetches the live Bluefin Pro exchange-info API at
  `https://api.sui-prod.bluefin.io/v1/exchange/info`.
- The builder uses the returned `currentContractAddress`, `edsId`, and margin
  asset metadata. Current mainnet exchange-info lists `USDC` with 6 decimals.
- PTB shape:
  1. Optional `wallet::withdraw_coin<USDC>` if the user checks "Fund from Sup
     vault".
  2. `exchange::deposit_to_asset_bank<USDC>(eds, "USDC", account, amount_6d,
     coin)`.
  3. The zero/remaining deposit coin object is transferred back to the user,
     matching Bluefin's own `library-sui` builder pattern.

Design boundary:
- Bluefin Pro deposit creates a pending external-bank deposit that Bluefin's
  sequencer later syncs into the internal account. It does not return a share
  coin, LP coin, or receipt coin.
- The generic share-style `adaptor_bluefin` (begin/finish_vault_deposit) was
  therefore RETIRED — there is no returned coin to prove and credit into Sup Wallet.
  Agent-signed margin deposit + Spot CLMM liquidity is now `adaptor_bluefin_margin`
  (custodies the bound deposit account / CLMM Position; DRAFT — audit + deploy pending).
- Orders, account authorization, isolated-margin changes, and withdrawals are
  Bluefin Pro API/signature flows. Sup should model those as owner-signed
  account actions or add a dedicated account-bound adaptor before allowing
  delegate-signed managed custody.

## Swap Aggregator

Package: `official/adaptor_swap_aggregator`

Research notes: `official/SWAP_AGGREGATOR_RESEARCH.md`

Functions:
- `adaptor_swap_aggregator::adaptor::begin_swap<CoinIn, CoinOut>`
- `adaptor_swap_aggregator::adaptor::finish_swap<CoinIn, CoinOut>`

Scope:
- Generic PTB-native swap adaptor for Cetus Aggregator, 7k, FlowX, Aftermath,
  Astros, and other SDK-driven routers.
- `begin_swap` debits `CoinIn` from Sup Wallet and returns both the coin and a
  `WalletSwapWitness`.
- The frontend/agent inserts the aggregator SDK route commands in the same PTB.
- `finish_swap` consumes the witness, verifies the actual `CoinOut` amount is
  greater than or equal to `min_out`, and credits the coin back into Sup Wallet.
- This package intentionally does not encode provider-specific route logic in
  Move. The route is produced by the official aggregator SDK and executed
  atomically between `begin_swap` and `finish_swap`.
- Current Sup Wallet web wiring quotes Cetus Aggregator V3, Aftermath Router,
  and 7K / Bluefin7K Aggregator, then uses the route with the highest `amountOut`. Override provider order with
  `SUP_SWAP_PROVIDERS` / `NEXT_PUBLIC_SUP_SWAP_PROVIDERS` (comma-separated,
  default `cetus,aftermath,sevenk`).
- Cetus is integrated through `findRouters` and `routerSwap`. Aftermath is
  integrated through `getCompleteTradeRouteGivenAmountIn` and
  `addTransactionForCompleteTradeRoute` with the Sup-returned `coinInId`.
- 7K is integrated through `getQuote` and `buildTx` with `extendTx: { tx,
  coinIn }`. BluefinX sponsored routes are filtered out because Sup needs a
  normal appendable `Transaction` between `begin_swap` and `finish_swap`.
- FlowX was researched and is compatible with the begin/finish shape, but SDK
  2.1.0 is not bundled into the web app because its top-level deprecated
  `@mysten/sui.js` import conflicts with this workspace's dependency graph.
  A dependency-isolated sidecar now exists at
  `Protocols/sup-wallet/sidecars/swap-aggregators` and exposes FlowX through
  `AggregatorQuoter` + `TradeBuilder`. Enable it with
  `SUP_SWAP_SIDECAR_URL` and `SUP_SWAP_PROVIDERS=...,flowx`.
- Astros was spiked with `@naviprotocol/astros-aggregator-sdk@1.14.2`; its
  ESM root bundle imports the old `SuiClient` named export from
  `@mysten/sui/client`, which is incompatible with this workspace's
  `@mysten/sui@2.16.3`. The sidecar loads Astros through its CJS bundle and
  verifies `getQuoteInternal` / `buildSwapPTBFromQuote` exports. Do not enable
  Astros in the web bundle directly; enable it through the sidecar with
  `SUP_SWAP_PROVIDERS=...,astros`.

Wallet grant:
- The active swap service type is `SwapAggregatorAdaptor` once deployed.
- Grants are required only for the source coin actually pulled from the vault.
- Legacy `CetusAdaptor` grants remain valid only for the old single-pool package.

## Repeatable QA

Commands:
- `bun run qa:mainnet-adaptors` from `Protocols`: checks every published
  mainnet adaptor package id in `deployments/zzyzx.mainnet.json` and verifies
  the expected normalized `adaptor` module functions.
- `bun run qa:mainnet-builders` from `Protocols`: runs the owner-signed
  protocol builder smoke suite in the Sup Wallet web app.
- `bun run qa:swap-aggregators` from `Protocols/sup-wallet/apps/web`: checks
  Cetus Aggregator V3, Aftermath Router, and 7K / Bluefin7K quote/build paths.
- `bun run qa:swap-settlement-preflight` from
  `Protocols/sup-wallet/apps/web`: read-only mainnet check for the selected Sup
  Wallet fixture's swap settlement prerequisites. It resolves wallet identity,
  vault source-coin balance, `SwapAggregatorAdaptor` service grant, service
  allowance, and coin allowance. Add `-- --strict` to fail on missing balance or
  authorization before running a signed smoke swap.
- `bun run qa:swap-settlement-setup` from `Protocols/sup-wallet/apps/web`:
  builds, but does not sign or submit, the owner-signed setup PTB needed before
  the first SUI vault swap. The default PTB funds the wallet identity with
  `0.01` SUI from owner gas, initializes the delegate registry when needed,
  adds the managed agent delegate, grants `SwapAggregatorAdaptor` on SUI, and
  sets service / SUI coin allowances. Override with
  `SUP_SWAP_SETUP_WALLET_ID`, `SUP_SWAP_SETUP_DELEGATE`,
  `SUP_SWAP_SETUP_FUND_SUI_ATOMIC`, and `SUP_SWAP_SETUP_ALLOWANCE_ATOMIC`.
- `bun run qa:swap-settlement-smoke` from `Protocols/sup-wallet/apps/web`:
  builds the managed-agent Sup-vault smoke swap PTB. It always performs a
  preflight read first, then quotes/builds the full
  `begin_swap -> aggregator route -> finish_swap` transaction. It does not
  submit unless `SUP_SWAP_SMOKE_SUBMIT=1` and a matching
  `SUP_SWAP_SMOKE_PRIVATE_KEY` / `SUP_AGENT_PRIVATE_KEY` are provided. Set
  `SUP_SWAP_SMOKE_DRY_RUN=1` to dry-run only after preflight is ready.

`qa:mainnet-builders` is intentionally no-sign / no-submit. It currently builds
transaction kinds for:
- Current SUI supply.
- NAVI direct SUI deposit fallback.
- Haedal SUI stake fallback.
- Aftermath Perpetuals USDC account creation.
- Typus DOV SUI deposit, with the SUI `DepositVault` discovered from the live
  Typus DOV registry instead of hard-coding a stale index.
- Managed Sup-vault Scallop SUI deposit, Suilend SUI deposit, and Haedal SUI
  stake builders. The script discovers a live Sup Wallet object from
  `WalletCreated` events or accepts `SUP_QA_WALLET_ID`.
- Managed Bucket borrow and saving-deposit builders when a real Bucket
  `Account` fixture is available. The script discovers accounts for the fixture
  owner through Bucket SDK, or accepts `SUP_QA_BUCKET_ACCOUNT_ID` and
  `SUP_QA_BUCKET_EXPECTED_ACCOUNT`.

It also checks Bluefin Pro's live mainnet ABI and confirms
`exchange::deposit_to_asset_bank` still accepts `&mut Coin<T>`, which is why the
builder can return the remaining coin to the user after deposit. Bluefin USDC
deposit and Cetus SUI/USDC add-liquidity full PTB builds are conditional: they
run automatically once `SUP_BUILDER_QA_SENDER` has enough USDC. With the current
deployer-only SUI balance, they emit warnings instead of false failures.

Important: the managed Sup-vault checks are build-only. They prove live package
ids, object ids, type arguments, and PTB composition are coherent. They do not
prove execution because the discovered fixture wallet may not have SUI/haSUI,
USDB, service authorization, external account binding, or delegate allowance.
Use a funded, authorized wallet id via `SUP_QA_WALLET_ID`, `SUP_QA_WALLET_OWNER`,
and for Bucket a bound `SUP_QA_BUCKET_ACCOUNT_ID`. For swap settlement, run
`qa:swap-settlement-setup` to build the owner setup PTB, have the wallet owner
sign it, re-run `qa:swap-settlement-preflight -- --strict`, then run
`qa:swap-settlement-smoke` with dry-run and finally explicit submit before
claiming settlement readiness.

## PTB-Native Vault / Share Adaptors

Packages:
- `official/adaptor_typus`
- `official/adaptor_ember`
- `official/adaptor_current`
- `official/adaptor_aftermath`
- `official/adaptor_bluefin`

Functions on Typus / Ember / Current:
- `begin_deposit<Asset, Share>`
- `finish_deposit<Asset, Share>`
- `begin_redeem<Share, Asset>`
- `finish_redeem<Share, Asset>`

Functions on Aftermath / Bluefin:
- `begin_vault_deposit<Collateral, Lp>` / `begin_vault_deposit<Asset, Share>`
- `finish_vault_deposit<Collateral, Lp>` / `finish_vault_deposit<Asset, Share>`
- `begin_vault_redeem<Lp, Collateral>` / `begin_vault_redeem<Share, Asset>`
- `finish_vault_redeem<Lp, Collateral>` / `finish_vault_redeem<Share, Asset>`

Scope:
- These packages provide protocol-specific service witnesses and Sup custody
  accounting for SDK-driven vault/share products.
- The PTB shape is:
  1. `begin_deposit` / `begin_redeem` debits the granted source coin from the
     Sup Wallet and returns a hot-potato `WalletSwapWitness`.
  2. The protocol SDK or hand-built PTB executes Typus / Ember / Current live
     protocol calls.
  3. `finish_deposit` / `finish_redeem` consumes the witness, verifies actual
     output is at least `min_*_out`, and credits the result coin back to the Sup
     Wallet.
- They intentionally do not expose a generic "pay and mark done" function. If a
  protocol action consumes a coin and only updates an external account without a
  returned coin/receipt object, that action needs a protocol-linked adaptor or a
  bound external account path. A generic finish-without-output would not prove
  that the external protocol received the funds.
- Aftermath account-collateral deposits and Bluefin Pro cross-margin deposits
  are therefore not exposed as generic adaptor calls yet. They should be enabled
  only through official ABI-backed builders that bind the external account to
  the Sup Wallet and can prove the requested account is the destination.

Wallet grant:
- Deposit grants the protocol adaptor on the asset coin.
- Redeem grants the protocol adaptor on the share / receipt coin.
- Account withdrawals are not exposed through these generic coin-share
  adaptors. Use owner-signed protocol/API flows until a dedicated account-bound
  adaptor can prove the external account destination.

Current status:
- Move packages and unit tests are ready.
- Typus DOV and Aftermath have owner-signed protocol builders for demo use.
- Ember has a managed-agent deposit builder when exact vault config is supplied.
- Current has an owner-signed supply builder for live market deposits; it is not
  a managed-agent custody path because Current returns an obligation owner cap,
  not a share coin.
- Bluefin Pro has an owner-signed USDC margin deposit builder; it is not a
  managed-agent custody path because `deposit_to_asset_bank` returns no share
  coin and relies on Bluefin's external-bank sync.
- Mainnet managed-agent custody execution still requires protocol-specific
  TypeScript builders that insert live Typus / Current / Aftermath /
  Bluefin SDK calls between begin and finish, and only for products that return
  concrete output coins or custody-compatible receipt objects.

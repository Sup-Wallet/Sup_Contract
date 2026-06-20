# Community Adaptors

This folder hosts **third-party** Sup Wallet adaptor packages. Official adaptors
(maintained by the Sup core team) live in `Sup_Contract/official/adaptor_*`;
community contributions live here.

## What counts as an adaptor?

An adaptor is a Move package that wraps an external protocol (DEX, lending,
staking, …) so a Sup Wallet can interact with it under the intent / delegate
auth model.

### Required (security boundary)

These are enforced by `sup_wallet`'s API visibility — you can't do otherwise:

1. **Declare your own witness type**, e.g. `public struct MyAdaptor has drop {}`.
   `has drop` only — no `key` / `store`, otherwise other modules could
   construct an instance and impersonate your adaptor.
2. **Pull funds only through `SupWallet::intent` (Mode A / B / C / D)**.
   `wallet::pay_by_service` is `public(package)` — external packages have no
   other path to withdraw. The intent flow enforces the 4-gate auth model
   (witness privacy + `wallet.auth` allowlist + delegate per-service +
   delegate per-coin) automatically.
3. **Push funds back via one of**:
   - `sui::coin::send_funds(coin, wallet.identity())` — permissionless, no
     service tag in events
   - `wallet::receive_from_service<MyAdaptor, T>(wallet, coin, MyAdaptor{})` —
     witness-gated, emits `CoinDeposited { service: Some(MyAdaptor), … }`

### Recommended (DX, not required)

4. **Emit your own protocol-level events** in addition to the intent events
   the wallet already emits (`PaymentValidated`, `SwapValidated`, etc.).
5. **Match the structure of [`Sup_Contract/official/adaptor_mock_swap`](../official/adaptor_mock_swap)**
   — that's the canonical reference, heavily commented. Copy the file as a
   starting point and replace the `swap_external` stub with your real DEX
   call. The 4-step intent flow is explicit:

```move
// Step 1+2 — pull CoinIn out
let sig = intent::request_swap<MyAdapter, USDC, BTC>(MyAdapter{}, 100, 50);
let (coin_in, ww) = intent::validate_and_swap_out(wallet, sig, ctx);

// Step 3 — external swap (your protocol)
let coin_out = external_dex::swap(coin_in, ctx);

// Step 4+5 — receipt + credit back
let receipt = intent::create_swap_receipt<MyAdapter, USDC, BTC>(
    MyAdapter{}, 100, coin::value(&coin_out),
);
intent::verify_swap_and_credit(wallet, ww, receipt, coin_out);
```

## Folder conventions

```
community/
├── <protocol_name>_adaptor/
│   ├── Move.toml          # depends on local ../../sup_wallet
│   ├── sources/
│   │   └── <protocol_name>_adaptor.move
│   └── tests/
└── README.md              # this file
```

Each community adaptor is its own published package. The Sup team does **not**
audit community packages — users opting in must run their own review.

## Contribution checklist

Before opening a PR:

- [ ] Package builds against the latest `sup_wallet` published version
- [ ] Tests pass (`sui move test`)
- [ ] Move.toml uses `SupWallet = { local = "../../sup_wallet" }` (two-up path
      from `community/<your_adaptor>/`)
- [ ] Does NOT modify any file outside its own folder
- [ ] Adaptor witness has `drop` only (no `key` / `store` — must not be
      transferable, otherwise other modules could spoof your adaptor)
- [ ] Withdraws go through `intent::*` (the only available path —
      `wallet::pay_by_service` is `public(package)`, unreachable from
      external packages)
- [ ] README documents which `grant_service_coin` invocations the user must
      run before the adaptor can pull funds

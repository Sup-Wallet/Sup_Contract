// Copyright (c) ZZYZX Labs
// SPDX-License-Identifier: BUSL-1.1

// INTERFACE STUB for Bluefin Pro's cross-margin DEX `exchange` + `data_store`
// modules — type shapes + signatures only, bodies abort. Signatures are taken from
// the OFFICIAL contracts (github.com/fireflyprotocol/bluefin-pro-contracts-public,
// sources/exchange.move), and the mainnet package id is set in Move.toml
// (bluefin_exchange = 0xe744…85b7, published-at 0xe238…50a0; real package name
// `bluefin_cross_margin_dex`). Only `deposit_to_asset_bank` is reproduced — it's the
// agent-callable margin deposit. Withdraw is intentionally absent: the on-chain
// `withdraw_from_bank` is a non-public `entry` gated by a sequencer-signed
// "Bluefin Pro Withdrawal" payload, so withdraws stay off-chain / owner-driven.

module bluefin_exchange::data_store {
    /// The shared external data store (the `eds` object). VERIFY exact fields/abilities.
    public struct ExternalDataStore has key { id: UID }
}

module bluefin_exchange::exchange {
    use std::string::String;
    use sui::coin::Coin;
    use bluefin_exchange::data_store::ExternalDataStore;

    /// `deposit_to_asset_bank<T>(eds, asset_symbol, account, coin_base_amount, coin, ctx)`.
    /// Credits `coin_base_amount` of `T` to the Bluefin Pro account `account` (an
    /// off-chain ledger entry, no share coin). Borrows the coin `&mut` and deducts
    /// the amount. `public entry` — also callable from another module.
    public entry fun deposit_to_asset_bank<T>(
        _eds: &mut ExternalDataStore,
        _asset_symbol: String,
        _account: address,
        _coin_base_amount: u64,
        _coin: &mut Coin<T>,
        _ctx: &mut TxContext,
    ) { abort 0 }
}

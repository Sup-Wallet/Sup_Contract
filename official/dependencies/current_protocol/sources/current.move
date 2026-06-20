// Copyright (c) ZZYZX Labs
// SPDX-License-Identifier: BUSL-1.1

// INTERFACE STUB for Current Finance's on-chain lending package — type shapes +
// signatures only, every body aborts. Signatures were read from the LIVE mainnet
// package (sui_getNormalizedMoveModulesByPackage on
// 0xfe1d8929d13b00aaecd7642dec1c6d41cab82882a1b139efa46bf61dfd6380bf), so they are
// accurate as of authoring — but VERIFY before deploy and set published-at +
// [addresses].
//
// NOTE: `x_oracle::XOracle` is NOT part of the Current package on-chain (it's a
// shared oracle package, same family as scallop_x_oracle). It is stubbed here for
// compilation; at deploy, point the adaptor at the real oracle package's type.
// `coin_decimals_registry` IS a Current module, so its path is already correct.

module current_protocol::app {
    public struct ProtocolApp has key { id: UID }
    /// Permission cap Current grants to whitelisted integrators — required by
    /// flash loans and eMode entry. VERIFY: real abilities + how Sup obtains one.
    public struct PackageCallerCap has key, store { id: UID }
}

module current_protocol::market_type {
    public struct MainMarket has drop {}
    public struct AltCoinMarket has drop {}
    public struct EmberMarket has drop {}
}

module current_protocol::market {
    public struct Market<phantom MarketT> has key { id: UID }
    /// Flash-loan hot potato — no abilities, must be consumed by repay_flash_loan
    /// in the same transaction.
    public struct FlashLoan<phantom MarketT, phantom CoinT> { amount: u64 }
}

module current_protocol::obligation {
    /// The owned capability that controls an obligation (a bearer cap — possession
    /// grants supply/withdraw/borrow/repay authority over that obligation).
    public struct ObligationOwnerCap has key, store { id: UID }
}

module current_protocol::coin_decimals_registry {
    public struct CoinDecimalsRegistry has key { id: UID }
}

module current_protocol::enter_market {
    use current_protocol::app::ProtocolApp;
    use current_protocol::market::Market;
    use current_protocol::obligation::ObligationOwnerCap;

    public fun enter_market_return<MarketT>(
        _app: &ProtocolApp,
        _market: &mut Market<MarketT>,
        _ctx: &mut TxContext,
    ): ObligationOwnerCap { abort 0 }
}

module current_protocol::deposit {
    use sui::coin::Coin;
    use sui::clock::Clock;
    use current_protocol::app::ProtocolApp;
    use current_protocol::market::Market;
    use current_protocol::obligation::ObligationOwnerCap;

    /// deposit<MarketT, CoinT>(app, market, &cap, coin, clock, ctx) — consumes coin.
    public fun deposit<MarketT, CoinT>(
        _app: &ProtocolApp,
        _market: &mut Market<MarketT>,
        _cap: &ObligationOwnerCap,
        _coin: Coin<CoinT>,
        _clock: &Clock,
        _ctx: &TxContext,
    ) { abort 0 }
}

module current_protocol::withdraw {
    use sui::coin::Coin;
    use sui::clock::Clock;
    use current_protocol::app::ProtocolApp;
    use current_protocol::market::Market;
    use current_protocol::obligation::ObligationOwnerCap;
    use current_protocol::coin_decimals_registry::CoinDecimalsRegistry;
    use current_x_oracle::x_oracle::XOracle;

    /// withdraw_as_coin<MarketT, CoinT>(...) -> Coin<CoinT>.
    public fun withdraw_as_coin<MarketT, CoinT>(
        _app: &ProtocolApp,
        _market: &mut Market<MarketT>,
        _cap: &ObligationOwnerCap,
        _registry: &CoinDecimalsRegistry,
        _amount: u64,
        _oracle: &XOracle,
        _clock: &Clock,
        _ctx: &mut TxContext,
    ): Coin<CoinT> { abort 0 }
}

module current_protocol::borrow {
    use sui::coin::Coin;
    use sui::clock::Clock;
    use current_protocol::app::ProtocolApp;
    use current_protocol::market::Market;
    use current_protocol::obligation::ObligationOwnerCap;
    use current_protocol::coin_decimals_registry::CoinDecimalsRegistry;
    use current_x_oracle::x_oracle::XOracle;

    /// borrow<MarketT, CoinT>(...) -> Coin<CoinT>. Aborts in-protocol if the
    /// obligation would become unsafe (this is Current's own risk guard).
    public fun borrow<MarketT, CoinT>(
        _app: &ProtocolApp,
        _cap: &ObligationOwnerCap,
        _market: &mut Market<MarketT>,
        _registry: &CoinDecimalsRegistry,
        _amount: u64,
        _oracle: &XOracle,
        _clock: &Clock,
        _ctx: &mut TxContext,
    ): Coin<CoinT> { abort 0 }
}

module current_protocol::repay {
    use sui::coin::Coin;
    use sui::clock::Clock;
    use current_protocol::app::ProtocolApp;
    use current_protocol::market::Market;
    use current_protocol::obligation::ObligationOwnerCap;

    /// repay<MarketT, CoinT>(app, &cap, market, coin, clock, ctx) — consumes coin.
    public fun repay<MarketT, CoinT>(
        _app: &ProtocolApp,
        _cap: &ObligationOwnerCap,
        _market: &mut Market<MarketT>,
        _coin: Coin<CoinT>,
        _clock: &Clock,
        _ctx: &mut TxContext,
    ) { abort 0 }
}

module current_protocol::flash_loan {
    use sui::coin::Coin;
    use current_protocol::app::{ProtocolApp, PackageCallerCap};
    use current_protocol::market::{Market, FlashLoan};

    /// borrow_flash_loan<MarketT, CoinT>(app, &caller_cap, market, asset_index, amount, ctx)
    /// -> (Coin<CoinT>, FlashLoan<MarketT, CoinT>). Requires a Current-granted caller cap.
    public fun borrow_flash_loan<MarketT, CoinT>(
        _app: &ProtocolApp,
        _caller_cap: &PackageCallerCap,
        _market: &mut Market<MarketT>,
        _asset_index: u8,
        _amount: u64,
        _ctx: &mut TxContext,
    ): (Coin<CoinT>, FlashLoan<MarketT, CoinT>) { abort 0 }

    public fun repay_flash_loan<MarketT, CoinT>(
        _app: &mut ProtocolApp,
        _market: &mut Market<MarketT>,
        _coin: Coin<CoinT>,
        _loan: FlashLoan<MarketT, CoinT>,
        _ctx: &mut TxContext,
    ) { abort 0 }
}

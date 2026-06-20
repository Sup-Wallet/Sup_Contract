// INTERFACE STUB for Aftermath Perpetuals — type shapes only, every body aborts.
// Mirrors the on-chain ABI reconstructed from aftermath-ts-sdk@2.1.0's
// (commented-out) tx builders. Replace `published-at` + [addresses] in Move.toml
// with the real mainnet ids at deploy, and VERIFY these signatures against the
// live Aftermath Perpetuals Move package — the SDK's live path is its backend,
// so this ABI may be stale.
module aftermath_perp::account {
    /// The perp account (a shared object on-chain). `T` = collateral coin type.
    public struct Account<phantom T> has key {
        id: UID,
    }

    /// The owned capability that controls an account. VERIFY abilities + exact
    /// type (SDK exposes a `PerpetualsAccountCap` with admin/agent variants).
    public struct AccountCap has key, store {
        id: UID,
    }

    /// Per-market shared object (the orderbook + risk engine).
    public struct ClearingHouse<phantom T> has key {
        id: UID,
    }

    /// Global shared registry used to create accounts.
    public struct Registry has key {
        id: UID,
    }

    /// An oracle price-feed object (base + collateral feeds are passed to sessions).
    public struct PriceFeed has key {
        id: UID,
    }

    /// Hot potato returned by `start_session`, consumed by `end_session`. No
    /// abilities → must be consumed in the same PTB.
    public struct SessionHotPotato<phantom T> {
        dummy: bool,
    }

    public fun cap_account_id(_cap: &AccountCap): ID { abort 0 }
}

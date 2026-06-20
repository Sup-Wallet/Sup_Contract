// INTERFACE STUB for Aftermath Perpetuals `interface` module — bodies abort.
// Arg order + targets reconstructed from aftermath-ts-sdk@2.1.0. VERIFY before
// deploy (see ../account.move + the adaptor DESIGN.md).
module aftermath_perp::interface {
    use sui::coin::Coin;
    use sui::clock::Clock;
    use aftermath_perp::account::{Account, AccountCap, ClearingHouse, Registry, PriceFeed, SessionHotPotato};

    /// create_account<T>(registry) -> (Account<T>, AccountCap)
    /// VERIFY: real return shape (SDK has a deferred create/share + admin/agent caps).
    public fun create_account<T>(_registry: &mut Registry, _ctx: &mut TxContext): (Account<T>, AccountCap) {
        abort 0
    }

    /// deposit_collateral<T>(cap, coin). SDK args: [accountCap, coin] (no CH/Clock).
    public fun deposit_collateral<T>(_cap: &AccountCap, _coin: Coin<T>) {
        abort 0
    }

    /// withdraw_collateral<T>(cap, amount) -> Coin<T>. SDK args: [accountCap, u64].
    public fun withdraw_collateral<T>(_cap: &AccountCap, _amount: u64, _ctx: &mut TxContext): Coin<T> {
        abort 0
    }

    /// start_session<T>(clearing_house, cap, base_feed, collateral_feed, clock) -> SessionHotPotato<T>.
    public fun start_session<T>(
        _clearing_house: &mut ClearingHouse<T>,
        _cap: &AccountCap,
        _base_price_feed: &PriceFeed,
        _collateral_price_feed: &PriceFeed,
        _clock: &Clock,
    ): SessionHotPotato<T> {
        abort 0
    }

    /// place_market_order<T>(session, side, size). side: false=bid/long, true=ask/short (VERIFY).
    public fun place_market_order<T>(_session: &mut SessionHotPotato<T>, _side: bool, _size: u64) {
        abort 0
    }

    /// end_session<T>(session) — consumes the hot potato.
    public fun end_session<T>(_session: SessionHotPotato<T>) {
        abort 0
    }

    /// Native Aftermath agent grant (trade-only; cannot withdraw). Optional path
    /// if we later prefer Aftermath's own agent cap over the custody wrapper.
    public fun grant_agent_wallet<T>(_cap: &AccountCap, _recipient: address, _ctx: &mut TxContext) {
        abort 0
    }
}

/// # Oracle price-guard caveat rule — a reference third-party rule package
///
/// A worked example of a **condition-gated** delegation-policy rule: a spend is
/// only allowed *while the coin's oracle price sits inside an owner-set band*.
/// It demonstrates the headline of Sup's delegation model — **authority is a
/// proof, not a password**: the funds don't unlock because someone holds a key,
/// they unlock because a condition (here, a price) is *provably true on-chain*.
///
/// Like `policy_rule_recipient_allowlist`, this package is **not** part of
/// `SupWallet`. It plugs in using only the public `SupWallet::policy` interface —
/// no core changes, no special permission. The same shape works for any
/// oracle-readable condition (TWAP, volatility, a ZK verification, an 8183 job).
///
/// A caveat rule is two things:
///   1. a **witness type** (`OraclePriceGuard`) only this module can build;
///   2. an **enforce** entrypoint that checks the condition against the request
///      and, if it holds, stamps the witness via `policy::add_caveat_receipt`.
///
/// Integration (all owner-driven, all on the public API):
///   - owner deploys this package (optionally lists it in `policy_rule_registry`);
///   - owner creates a `PriceGuard` bound to their wallet + a trusted feed + band;
///   - owner calls `policy::add_caveat_rule<OraclePriceGuard>(&mut wallet)`;
///   - a spender, between `policy::begin_spend` and `policy::confirm_spend`, calls
///     `rule::enforce(&guard, &feed, &mut req)`.
///
/// ## Production note — swapping in a real oracle
/// The `PriceFeed` object here is a **minimal reference price source** so the
/// package compiles and tests stand-alone. In production you bind `PriceGuard`
/// to a real oracle object id (e.g. a Pyth `PriceInfoObject`) and read the price
/// through that oracle's getter inside `enforce` instead of `feed.price`. The
/// rule logic (band check + stamp) is identical; only the price *read* changes.
module policy_rule_oracle_price_guard::rule {
    use sui::{
        clock::Clock,
        object::{Self, ID, UID},
        tx_context::{Self, TxContext},
        transfer,
        event,
    };
    use SupWallet::wallet::{Self, Wallet};
    use SupWallet::policy::{Self, SpendRequest};

    /// Oracle price is outside the owner-set band.
    const EOutOfBand: u64 = 1;
    /// This guard config is bound to a different wallet than the request.
    const EWrongWallet: u64 = 2;
    /// Caller is not the wallet owner.
    const ENotOwner: u64 = 3;
    /// The feed presented is not the one this guard trusts.
    const EWrongFeed: u64 = 4;
    /// Caller is not the feed's reporter.
    const ENotReporter: u64 = 5;
    /// Band is invalid (min > max).
    const EBadBand: u64 = 6;

    /// Caveat-rule witness. Only this module can construct it.
    public struct OraclePriceGuard has drop {}

    /// Owner-managed config: allow a delegated spend only while the trusted
    /// feed's price is within `[min_price, max_price]`. Shared so any spender can
    /// reference it inside their PTB. Prices are raw integers in whatever unit
    /// the feed reports (e.g. micro-USD); `min`/`max` use the same unit.
    public struct PriceGuard has key, store {
        id: UID,
        wallet_id: ID,
        owner: address,
        /// The object id of the trusted price source. `enforce` rejects any
        /// other feed, so a spender can't substitute a favourable one.
        feed_id: ID,
        min_price: u64,
        max_price: u64,
    }

    /// Minimal reference price source (the integration point — replace with a
    /// real oracle object in production). Updated by a designated `reporter`.
    public struct PriceFeed has key, store {
        id: UID,
        price: u64,
        updated_at_ms: u64,
        reporter: address,
    }

    public struct PriceGuardCreated has copy, drop { guard_id: ID, wallet_id: ID, feed_id: ID }
    public struct PriceGuardBandChanged has copy, drop { guard_id: ID, min_price: u64, max_price: u64 }
    public struct PriceFeedUpdated has copy, drop { feed_id: ID, price: u64, updated_at_ms: u64 }

    /// ===== owner: guard config lifecycle =====

    public fun create(
        wallet: &Wallet,
        feed_id: ID,
        min_price: u64,
        max_price: u64,
        ctx: &mut TxContext,
    ): PriceGuard {
        assert!(tx_context::sender(ctx) == wallet::owner(wallet), ENotOwner);
        assert!(min_price <= max_price, EBadBand);
        let guard = PriceGuard {
            id: object::new(ctx),
            wallet_id: wallet::id(wallet),
            owner: wallet::owner(wallet),
            feed_id,
            min_price,
            max_price,
        };
        event::emit(PriceGuardCreated {
            guard_id: object::id(&guard),
            wallet_id: guard.wallet_id,
            feed_id,
        });
        guard
    }

    #[allow(lint(share_owned))]
    public fun create_and_share(
        wallet: &Wallet,
        feed_id: ID,
        min_price: u64,
        max_price: u64,
        ctx: &mut TxContext,
    ) {
        transfer::share_object(create(wallet, feed_id, min_price, max_price, ctx));
    }

    public fun set_band(guard: &mut PriceGuard, min_price: u64, max_price: u64, ctx: &TxContext) {
        assert!(tx_context::sender(ctx) == guard.owner, ENotOwner);
        assert!(min_price <= max_price, EBadBand);
        guard.min_price = min_price;
        guard.max_price = max_price;
        event::emit(PriceGuardBandChanged { guard_id: object::id(guard), min_price, max_price });
    }

    /// ===== reference feed lifecycle (replace with a real oracle in prod) =====

    public fun new_feed(price: u64, clock: &Clock, ctx: &mut TxContext): PriceFeed {
        PriceFeed {
            id: object::new(ctx),
            price,
            updated_at_ms: clock.timestamp_ms(),
            reporter: tx_context::sender(ctx),
        }
    }

    #[allow(lint(share_owned))]
    public fun new_feed_and_share(price: u64, clock: &Clock, ctx: &mut TxContext) {
        transfer::share_object(new_feed(price, clock, ctx));
    }

    public fun update_price(feed: &mut PriceFeed, price: u64, clock: &Clock, ctx: &TxContext) {
        assert!(tx_context::sender(ctx) == feed.reporter, ENotReporter);
        feed.price = price;
        feed.updated_at_ms = clock.timestamp_ms();
        event::emit(PriceFeedUpdated { feed_id: object::id(feed), price, updated_at_ms: feed.updated_at_ms });
    }

    /// ===== rule: enforce =====

    /// Stamp `OraclePriceGuard` onto the request iff (a) the guard is for this
    /// wallet, (b) the presented feed is the trusted one, and (c) its price is
    /// within the band. Read-only on the request apart from the stamp.
    public fun enforce(guard: &PriceGuard, feed: &PriceFeed, req: &mut SpendRequest) {
        assert!(guard.wallet_id == policy::spend_wallet_id(req), EWrongWallet);
        assert!(object::id(feed) == guard.feed_id, EWrongFeed);
        let p = feed.price;
        assert!(p >= guard.min_price && p <= guard.max_price, EOutOfBand);
        policy::add_caveat_receipt(OraclePriceGuard {}, req);
    }

    /// ===== reads =====

    public fun is_in_band(guard: &PriceGuard, price: u64): bool {
        price >= guard.min_price && price <= guard.max_price
    }

    public fun wallet_id(guard: &PriceGuard): ID { guard.wallet_id }
    public fun feed_id(guard: &PriceGuard): ID { guard.feed_id }
    public fun band(guard: &PriceGuard): (u64, u64) { (guard.min_price, guard.max_price) }
    public fun price(feed: &PriceFeed): u64 { feed.price }
}

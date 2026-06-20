// Copyright (c) ZZYZX Labs
// SPDX-License-Identifier: BUSL-1.1

/// Bluefin Spot CLMM liquidity — the SAME Bluefin adaptor package, second surface.
///
/// `adaptor::*` covers Bluefin Pro (perp margin). This module covers Bluefin Spot
/// (the concentrated-liquidity AMM): the managed agent can add / remove liquidity
/// and collect fees on a custodied CLMM position WITHOUT a per-action signature,
/// bounded by caps + an ACL, with every output locked back to the vault.
///
/// Custody model: the CLMM `Position` NFT is held inside a Sup-custodied, vault-
/// parented `BluefinSpotPosition` (never handed out except via owner `reclaim`).
/// Adds are funded from the vault via the Sup intent (per-coin caps enforced);
/// removed liquidity + collected fees are credited back to the vault via
/// `receive_from_service`. No path returns funds to the caller.
///
/// Its own `BluefinSpotAdaptor` witness (distinct from the perp-margin
/// `BluefinMarginAdaptor`) so LP token-pair allowances are scoped separately from
/// perp USDC margin — one Bluefin adaptor package, two service scopes.
///
/// ⚠ DRAFT — `bluefin_spot::*` is a Cetus-family CLMM ABI stub (bodies abort; the
/// real add-liquidity uses a receipt/repay hot-potato — see the stub's VERIFY note).
/// Not compiled against the real package. VERIFY + AUDIT before mainnet.
module adaptor_bluefin_margin::liquidity {
    use sui::balance::{Self, Balance};
    use sui::clock::Clock;
    use sui::coin;
    use sui::vec_map::{Self, VecMap};
    use SupWallet::intent;
    use SupWallet::wallet::{Self, Wallet};
    use bluefin_spot::config::GlobalConfig;
    use bluefin_spot::pool::{Self, Pool};
    use bluefin_spot::position::Position;

    /// Service witness for Bluefin Spot LP funding (separate cap scope from margin).
    public struct BluefinSpotAdaptor has drop {}

    /// Sup-custodied CLMM position, parented to one vault.
    public struct BluefinSpotPosition has key {
        id: UID,
        parent_wallet_identity: address,
        position: Position,
        delegates: VecMap<address, u32>,
    }

    const PERM_ADD: u32 = 1;
    const PERM_REMOVE: u32 = 2;

    const ENotOwner: u64 = 0;
    const EWrongParent: u64 = 1;
    const ENoPerm: u64 = 2;
    const EZeroAmount: u64 = 3;

    public fun perm_add(): u32 { PERM_ADD }
    public fun perm_remove(): u32 { PERM_REMOVE }
    public fun perm_add_and_remove(): u32 { PERM_ADD | PERM_REMOVE }

    // ===== owner setup (owner-signed) =====

    /// Open a CLMM position over [tick_lower, tick_upper] and custody it. One-time,
    /// owner-signed (the range is a strategy choice). Returns the wrapper id.
    public fun adopt<A, B>(
        sup_wallet: &Wallet,
        config: &GlobalConfig,
        pool: &mut Pool<A, B>,
        tick_lower: u32,
        tick_upper: u32,
        ctx: &mut TxContext,
    ): ID {
        assert!(ctx.sender() == wallet::owner(sup_wallet), ENotOwner);
        let position = pool::open_position<A, B>(config, pool, tick_lower, tick_upper, ctx);
        let self = BluefinSpotPosition {
            id: object::new(ctx),
            parent_wallet_identity: wallet::identity(sup_wallet),
            position,
            delegates: vec_map::empty(),
        };
        let id = object::id(&self);
        transfer::share_object(self);
        id
    }

    public fun grant_delegate(
        sup_wallet: &Wallet,
        self: &mut BluefinSpotPosition,
        delegate: address,
        perms: u32,
        ctx: &TxContext,
    ) {
        assert!(ctx.sender() == wallet::owner(sup_wallet), ENotOwner);
        assert_parent(sup_wallet, self);
        if (vec_map::contains(&self.delegates, &delegate)) {
            let (_, _) = vec_map::remove(&mut self.delegates, &delegate);
        };
        vec_map::insert(&mut self.delegates, delegate, perms);
    }

    public fun revoke_delegate(
        sup_wallet: &Wallet,
        self: &mut BluefinSpotPosition,
        delegate: address,
        ctx: &TxContext,
    ) {
        assert!(ctx.sender() == wallet::owner(sup_wallet), ENotOwner);
        if (vec_map::contains(&self.delegates, &delegate)) {
            let (_, _) = vec_map::remove(&mut self.delegates, &delegate);
        };
    }

    /// Exit hatch: owner pulls the CLMM position back out and deletes the wrapper.
    #[allow(lint(self_transfer))]
    public fun reclaim(sup_wallet: &Wallet, self: BluefinSpotPosition, ctx: &TxContext) {
        assert!(ctx.sender() == wallet::owner(sup_wallet), ENotOwner);
        assert_parent(sup_wallet, &self);
        let BluefinSpotPosition { id, parent_wallet_identity: _, position, delegates: _ } = self;
        object::delete(id);
        transfer::public_transfer(position, ctx.sender());
    }

    // ===== agent ops =====

    /// Add liquidity to the custodied position, funding BOTH coins from the vault
    /// via the Sup intent (per-coin caps enforced). Unused remainder is credited
    /// back to the vault. Requires PERM_ADD.
    public fun add_from_vault<A, B>(
        sup_wallet: &mut Wallet,
        self: &mut BluefinSpotPosition,
        config: &GlobalConfig,
        pool: &mut Pool<A, B>,
        max_amount_a: u64,
        max_amount_b: u64,
        fixed_amount: u64,
        is_fixed_a: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(max_amount_a > 0 && max_amount_b > 0, EZeroAmount);
        assert_parent(sup_wallet, self);
        assert_perm(sup_wallet, self, PERM_ADD, ctx);
        let tag = self.parent_wallet_identity;
        // Pull the max we're willing to provide from the vault (a slippage buffer);
        // the pool returns the unused remainder of each, which we refund to the vault.
        let bal_a = pull_from_vault<A>(sup_wallet, max_amount_a, tag, ctx);
        let bal_b = pull_from_vault<B>(sup_wallet, max_amount_b, tag, ctx);
        let (_used_a, _used_b, res_a, res_b) = pool::add_liquidity_with_fixed_amount<A, B>(
            clock, config, pool, &mut self.position, bal_a, bal_b, fixed_amount, is_fixed_a,
        );
        credit_or_destroy<A>(sup_wallet, res_a, ctx);
        credit_or_destroy<B>(sup_wallet, res_b, ctx);
    }

    /// Remove `delta_liquidity` from the position; both coins go back to the vault.
    /// Requires PERM_REMOVE.
    public fun remove_to_vault<A, B>(
        sup_wallet: &mut Wallet,
        self: &mut BluefinSpotPosition,
        config: &GlobalConfig,
        pool: &mut Pool<A, B>,
        delta_liquidity: u128,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(delta_liquidity > 0, EZeroAmount);
        assert_parent(sup_wallet, self);
        assert_perm(sup_wallet, self, PERM_REMOVE, ctx);
        let (_amt_a, _amt_b, bal_a, bal_b) = pool::remove_liquidity<A, B>(config, pool, &mut self.position, delta_liquidity, clock);
        credit_or_destroy<A>(sup_wallet, bal_a, ctx);
        credit_or_destroy<B>(sup_wallet, bal_b, ctx);
    }

    /// Collect accrued fees to the vault. Pure benefit (funds only move into the
    /// vault), so it needs no PERM bit — just the parent lock.
    public fun collect_fees_to_vault<A, B>(
        sup_wallet: &mut Wallet,
        self: &mut BluefinSpotPosition,
        config: &GlobalConfig,
        pool: &mut Pool<A, B>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert_parent(sup_wallet, self);
        let (_fee_a, _fee_b, bal_a, bal_b) = pool::collect_fee<A, B>(clock, config, pool, &mut self.position);
        credit_or_destroy<A>(sup_wallet, bal_a, ctx);
        credit_or_destroy<B>(sup_wallet, bal_b, ctx);
    }

    // ===== internal =====

    /// Pull `amount` of `CoinT` from the vault through the Sup intent (caps enforced)
    /// and return it as a Balance to hand to the pool.
    fun pull_from_vault<CoinT>(
        wallet: &mut Wallet,
        amount: u64,
        tag: address,
        ctx: &mut TxContext,
    ): Balance<CoinT> {
        let sig = intent::request_payment<BluefinSpotAdaptor, CoinT>(BluefinSpotAdaptor {}, amount, tag);
        let (coin_in, ww) = intent::validate_and_pay<BluefinSpotAdaptor, CoinT>(wallet, sig, ctx);
        let receipt = intent::create_receipt_sig<BluefinSpotAdaptor, CoinT>(BluefinSpotAdaptor {}, amount, tag);
        intent::verify_and_clear<BluefinSpotAdaptor, CoinT>(ww, receipt);
        coin::into_balance(coin_in)
    }

    /// Credit a balance back into the vault (or drop it if empty).
    fun credit_or_destroy<CoinT>(wallet: &Wallet, bal: Balance<CoinT>, ctx: &mut TxContext) {
        if (balance::value(&bal) == 0) {
            balance::destroy_zero(bal);
        } else {
            let coin_out = coin::from_balance(bal, ctx);
            wallet::receive_from_service<BluefinSpotAdaptor, CoinT>(wallet, coin_out, BluefinSpotAdaptor {});
        }
    }

    // ===== reads =====

    public fun parent_identity(self: &BluefinSpotPosition): address { self.parent_wallet_identity }

    public fun has_permission(self: &BluefinSpotPosition, who: address, perm: u32): bool {
        if (!vec_map::contains(&self.delegates, &who)) return false;
        let bits = *vec_map::get(&self.delegates, &who);
        bits & perm == perm
    }

    public fun assert_parent(sup_wallet: &Wallet, self: &BluefinSpotPosition) {
        assert!(self.parent_wallet_identity == wallet::identity(sup_wallet), EWrongParent);
    }

    fun assert_perm(sup_wallet: &Wallet, self: &BluefinSpotPosition, perm: u32, ctx: &TxContext) {
        let sender = ctx.sender();
        if (sender == wallet::owner(sup_wallet)) return;
        assert!(has_permission(self, sender, perm), ENoPerm);
    }

    #[test_only]
    public fun not_owner_error(): u64 { ENotOwner }
    #[test_only]
    public fun no_perm_error(): u64 { ENoPerm }
}

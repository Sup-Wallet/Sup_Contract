// Copyright (c) ZZYZX Labs
// SPDX-License-Identifier: BUSL-1.1

/// Sup Wallet adaptor for Aftermath Perpetuals — lets the managed agent open /
/// adjust / close positions on behalf of the vault, and withdraw collateral
/// ONLY back into the vault. See DESIGN.md.
///
/// Custody model (mirrors `adaptor_os_account`): a Sup-custodied shared
/// `AfPerpAccount<T>` holds the Aftermath admin `AccountCap` (the cap is never
/// handed out), is parented to the vault identity, and carries a 2-bit
/// permission ACL (PERM_TRADE / PERM_WITHDRAW). `withdraw_to_vault` performs the
/// Aftermath withdraw AND credits the coin back to the vault in one function, so
/// there is no code path that returns funds to the caller.
///
/// ⚠ DRAFT — the Aftermath `interface::*` calls use an ABI reconstructed from the
/// SDK (see DESIGN.md "VERIFY"). Not yet Move-compiled against the real package.
module adaptor_aftermath_perp::adaptor {
    use sui::clock::Clock;
    use sui::vec_map::{Self, VecMap};
    use SupWallet::intent;
    use SupWallet::wallet::{Self, Wallet};
    use aftermath_perp::account::{AccountCap, ClearingHouse, PriceFeed};
    use aftermath_perp::interface;

    /// Service witness. The owner grants this service per coin type on the vault
    /// (for deposits) exactly like every other adaptor.
    public struct AftermathPerpAdaptor has drop {}

    /// Sup-custodied Aftermath perp account, parented to a vault.
    public struct AfPerpAccount<phantom T> has key {
        id: UID,
        /// `wallet::identity(vault)` — the only vault allowed to drive this.
        parent_wallet_identity: address,
        /// The Aftermath `Account<T>` shared object this cap controls (for reads).
        aftermath_account_id: ID,
        /// Aftermath admin cap — locked inside; only `reclaim` releases it.
        admin_cap: AccountCap,
        /// delegate address -> permission bitmask.
        delegates: VecMap<address, u32>,
    }

    const PERM_TRADE: u32 = 1;
    const PERM_WITHDRAW: u32 = 2;

    const ENotOwner: u64 = 0;
    const EWrongParent: u64 = 1;
    const ENoTradePerm: u64 = 2;
    const ENoWithdrawPerm: u64 = 3;
    const EZeroAmount: u64 = 4;

    public fun perm_trade(): u32 { PERM_TRADE }
    public fun perm_withdraw(): u32 { PERM_WITHDRAW }
    public fun perm_trade_and_withdraw(): u32 { PERM_TRADE | PERM_WITHDRAW }

    // ===== owner setup (owner-signed) =====

    /// Wrap an existing Aftermath admin cap into a Sup-custodied, vault-parented
    /// account and share it. One-time, owner-signed. Returns the wrapper id.
    public fun adopt<T>(
        sup_wallet: &Wallet,
        aftermath_account_id: ID,
        admin_cap: AccountCap,
        ctx: &mut TxContext,
    ): ID {
        assert!(ctx.sender() == wallet::owner(sup_wallet), ENotOwner);
        let self = AfPerpAccount<T> {
            id: object::new(ctx),
            parent_wallet_identity: wallet::identity(sup_wallet),
            aftermath_account_id,
            admin_cap,
            delegates: vec_map::empty(),
        };
        let id = object::id(&self);
        transfer::share_object(self);
        id
    }

    /// Exit hatch: owner pulls the admin cap back out and deletes the wrapper.
    public fun reclaim<T>(sup_wallet: &Wallet, self: AfPerpAccount<T>, ctx: &mut TxContext) {
        assert!(ctx.sender() == wallet::owner(sup_wallet), ENotOwner);
        assert_parent(sup_wallet, &self);
        let AfPerpAccount {
            id,
            parent_wallet_identity: _,
            aftermath_account_id: _,
            admin_cap,
            delegates: _,
        } = self;
        object::delete(id);
        transfer::public_transfer(admin_cap, ctx.sender());
    }

    /// Grant (or replace) a delegate's permission bits. Owner-signed.
    /// `perms` = PERM_TRADE | PERM_WITHDRAW (use the getters above).
    public fun grant_delegate<T>(
        sup_wallet: &Wallet,
        self: &mut AfPerpAccount<T>,
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

    /// Revoke a delegate. Owner-signed.
    public fun revoke_delegate<T>(
        sup_wallet: &Wallet,
        self: &mut AfPerpAccount<T>,
        delegate: address,
        ctx: &TxContext,
    ) {
        assert!(ctx.sender() == wallet::owner(sup_wallet), ENotOwner);
        if (vec_map::contains(&self.delegates, &delegate)) {
            let (_, _) = vec_map::remove(&mut self.delegates, &delegate);
        };
    }

    // ===== agent ops =====

    /// Deposit collateral FROM the vault into the Aftermath account. Funds are
    /// pulled via the Sup intent flow, which enforces the caller's per-service +
    /// per-coin allowances on the vault — so the agent can only move what the
    /// owner authorized.
    public fun deposit_collateral<T>(
        sup_wallet: &mut Wallet,
        self: &mut AfPerpAccount<T>,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        assert!(amount > 0, EZeroAmount);
        assert_parent(sup_wallet, self);
        let tag = self.parent_wallet_identity;
        let sig = intent::request_payment<AftermathPerpAdaptor, T>(AftermathPerpAdaptor {}, amount, tag);
        let (coin, ww) = intent::validate_and_pay<AftermathPerpAdaptor, T>(sup_wallet, sig, ctx);
        // VERIFY: real Aftermath deposit_collateral signature (SDK: cap + coin).
        interface::deposit_collateral<T>(&self.admin_cap, coin);
        let receipt = intent::create_receipt_sig<AftermathPerpAdaptor, T>(AftermathPerpAdaptor {}, amount, tag);
        intent::verify_and_clear<AftermathPerpAdaptor, T>(ww, receipt);
    }

    /// Open / adjust / close a position via a market order. Requires PERM_TRADE
    /// (or the owner). The admin cap is used internally and never leaves.
    /// `side`: false = long/bid, true = short/ask (VERIFY mapping).
    public fun place_market_order<T>(
        sup_wallet: &Wallet,
        self: &mut AfPerpAccount<T>,
        clearing_house: &mut ClearingHouse<T>,
        base_price_feed: &PriceFeed,
        collateral_price_feed: &PriceFeed,
        clock: &Clock,
        side: bool,
        size: u64,
        ctx: &TxContext,
    ) {
        assert!(size > 0, EZeroAmount);
        assert_parent(sup_wallet, self);
        assert_perm(sup_wallet, self, PERM_TRADE, ENoTradePerm, ctx);
        // VERIFY: session lifecycle + arg order against the live Aftermath ABI.
        let mut session = interface::start_session<T>(
            clearing_house,
            &self.admin_cap,
            base_price_feed,
            collateral_price_feed,
            clock,
        );
        interface::place_market_order<T>(&mut session, side, size);
        interface::end_session<T>(session);
    }

    /// Withdraw collateral — ALWAYS back into the vault. Requires PERM_WITHDRAW
    /// (or the owner). The withdrawn coin is credited to the vault via
    /// `wallet::receive_from_service`; there is no path that returns it to the
    /// caller, so the agent can withdraw but only to the vault.
    public fun withdraw_to_vault<T>(
        sup_wallet: &mut Wallet,
        self: &mut AfPerpAccount<T>,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        assert!(amount > 0, EZeroAmount);
        assert_parent(sup_wallet, self);
        assert_perm(sup_wallet, self, PERM_WITHDRAW, ENoWithdrawPerm, ctx);
        // VERIFY: withdraw_collateral returns Coin<T>.
        let coin = interface::withdraw_collateral<T>(&self.admin_cap, amount, ctx);
        wallet::receive_from_service<AftermathPerpAdaptor, T>(sup_wallet, coin, AftermathPerpAdaptor {});
    }

    // ===== reads / internal =====

    public fun aftermath_account_id<T>(self: &AfPerpAccount<T>): ID { self.aftermath_account_id }
    public fun parent_identity<T>(self: &AfPerpAccount<T>): address { self.parent_wallet_identity }

    public fun has_permission<T>(self: &AfPerpAccount<T>, who: address, perm: u32): bool {
        if (!vec_map::contains(&self.delegates, &who)) return false;
        let bits = *vec_map::get(&self.delegates, &who);
        bits & perm == perm
    }

    public fun assert_parent<T>(sup_wallet: &Wallet, self: &AfPerpAccount<T>) {
        assert!(self.parent_wallet_identity == wallet::identity(sup_wallet), EWrongParent);
    }

    /// Owner always passes; otherwise the sender must be a delegate holding `perm`.
    fun assert_perm<T>(sup_wallet: &Wallet, self: &AfPerpAccount<T>, perm: u32, err: u64, ctx: &TxContext) {
        let sender = ctx.sender();
        if (sender == wallet::owner(sup_wallet)) return;
        assert!(has_permission(self, sender, perm), err);
    }

    #[test_only]
    public fun wrong_parent_error(): u64 { EWrongParent }
}

// Copyright (c) ZZYZX Labs
// SPDX-License-Identifier: BUSL-1.1

/// Sup Wallet "delegated trading budget" adaptor — for venues Sup can't custody
/// safely (e.g. ZO Finance, whose positions key on tx-sender with a key-only,
/// non-delegatable cap — see docs/zo-budget-adapter.md).
///
/// Instead of trying to split trade-vs-withdraw on one venue account (impossible on
/// ZO), this ISOLATES the risk: the owner binds an external trading account address
/// once and grants a capped allowance; the managed agent can then move funds from
/// the vault into ONLY that bound account, ONLY up to the allowance. The agent
/// trades that account freely (off-Sup, with the account's own key); the vault is
/// never exposed beyond the funded budget.
///
/// Guarantee: bounded blast radius — a compromised/aggressive agent can lose at most
/// the granted allowance (the budget), never the rest of the vault. This is weaker
/// than the "agent never withdraws" custody adaptors (Aftermath / Current / Bluefin
/// margin) and is the right tool only when the venue offers no trade-only delegation.
///
/// No external protocol dependency — Sup's on-chain part is purely the capped,
/// destination-locked transfer. The funding is witness-gated via the Sup intent, so
/// the agent cannot redirect the budget anywhere but the owner-bound account.
module adaptor_zo_budget::adaptor {
    use SupWallet::intent;
    use SupWallet::wallet::{Self, Wallet};

    /// Service witness — owner grants this per coin type on the vault (the budget).
    public struct ZoBudgetAdaptor has drop {}

    /// Sup-custodied binding: which external trading account this vault's agent may
    /// fund. Parented to one vault. Holds no funds — it only pins the destination.
    public struct ZoTradingBudget has key {
        id: UID,
        /// `wallet::identity(vault)` — the only vault allowed to drive this.
        parent_wallet_identity: address,
        /// The owner-bound external trading account (the destination LOCK).
        trading_account: address,
    }

    const ENotOwner: u64 = 0;
    const EWrongParent: u64 = 1;
    const EZeroAmount: u64 = 2;

    // ===== owner setup (owner-signed) =====

    /// Bind an external trading account to this vault and share the binding.
    /// Owner-signed. The owner separately grants the per-service + per-coin allowance
    /// (the budget) and funds the agent's gas.
    public fun adopt(sup_wallet: &Wallet, trading_account: address, ctx: &mut TxContext): ID {
        assert!(ctx.sender() == wallet::owner(sup_wallet), ENotOwner);
        let self = ZoTradingBudget {
            id: object::new(ctx),
            parent_wallet_identity: wallet::identity(sup_wallet),
            trading_account,
        };
        let id = object::id(&self);
        transfer::share_object(self);
        id
    }

    /// Re-point the bound trading account. Owner-signed.
    public fun set_account(
        sup_wallet: &Wallet,
        self: &mut ZoTradingBudget,
        trading_account: address,
        ctx: &TxContext,
    ) {
        assert!(ctx.sender() == wallet::owner(sup_wallet), ENotOwner);
        assert_parent(sup_wallet, self);
        self.trading_account = trading_account;
    }

    /// Delete the binding. Owner-signed. (The allowance is revoked separately via
    /// `delegate` / `wallet::revoke_service`.)
    public fun reclaim(sup_wallet: &Wallet, self: ZoTradingBudget, ctx: &TxContext) {
        assert!(ctx.sender() == wallet::owner(sup_wallet), ENotOwner);
        assert_parent(sup_wallet, &self);
        let ZoTradingBudget { id, parent_wallet_identity: _, trading_account: _ } = self;
        object::delete(id);
    }

    // ===== agent op: fund the budget (NO per-action owner signature) =====

    /// Move `amount` of `CoinT` from the vault to the bound trading account, within
    /// the owner's per-service + per-coin allowance (the budget). Funding is pulled
    /// via the Sup intent (witness-gated, caps enforced) and sent ONLY to
    /// `self.trading_account` — the agent cannot redirect it.
    public fun fund<CoinT>(
        sup_wallet: &mut Wallet,
        self: &ZoTradingBudget,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        assert!(amount > 0, EZeroAmount);
        assert_parent(sup_wallet, self);
        // Use the bound account as the intent's recipient tag so the on-chain
        // PaymentValidated event records the real destination of the funds.
        let tag = self.trading_account;
        let sig = intent::request_payment<ZoBudgetAdaptor, CoinT>(ZoBudgetAdaptor {}, amount, tag);
        let (coin, ww) = intent::validate_and_pay<ZoBudgetAdaptor, CoinT>(sup_wallet, sig, ctx);
        transfer::public_transfer(coin, self.trading_account);
        let receipt = intent::create_receipt_sig<ZoBudgetAdaptor, CoinT>(ZoBudgetAdaptor {}, amount, tag);
        intent::verify_and_clear<ZoBudgetAdaptor, CoinT>(ww, receipt);
    }

    // ===== reads / internal =====

    public fun trading_account(self: &ZoTradingBudget): address { self.trading_account }
    public fun parent_identity(self: &ZoTradingBudget): address { self.parent_wallet_identity }

    public fun assert_parent(sup_wallet: &Wallet, self: &ZoTradingBudget) {
        assert!(self.parent_wallet_identity == wallet::identity(sup_wallet), EWrongParent);
    }

    #[test_only]
    public fun not_owner_error(): u64 { ENotOwner }
    #[test_only]
    public fun wrong_parent_error(): u64 { EWrongParent }
    #[test_only]
    public fun zero_amount_error(): u64 { EZeroAmount }
}

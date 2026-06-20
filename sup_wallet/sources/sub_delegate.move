/// # Sub-delegation — attenuated, budget-carrying capabilities (ERC-7710-style)
///
/// `cap_auth::DelegateCap` is an *unbudgeted* bearer cap: it proves "who" and
/// leans on the wallet's global caveat rules for "how much". That can't express
/// **attenuation** — a child delegate with strictly less authority than its
/// parent — because the caveats are wallet-global, not per-cap.
///
/// `ScopedCap` fixes that by binding the budget to the capability itself. Each
/// cap is scoped to one coin type and carries a `remaining` budget. A holder can
/// `subdelegate` part of their budget to a child cap (`depth + 1`, budget moved
/// from parent to child), so the child can never spend more than it was granted,
/// and the chain can never exceed the root. This is object-capability attenuation:
/// authority lives in the object and only ever shrinks as it is passed down.
///
/// A `ScopedCap` is self-contained: on `spend` it stamps **both** an auth receipt
/// (`ScopedAuth`) and a caveat receipt (`ScopedBudget`), so a wallet that wants to
/// accept scoped caps simply does:
/// ```move
/// policy::add_auth_rule<ScopedAuth>(&mut wallet, ctx);
/// policy::add_caveat_rule<ScopedBudget>(&mut wallet, ctx);
/// ```
///
/// Revocation: caps bind to the policy `version`, so `policy::revoke_all` kills an
/// entire delegation tree at once. Returning a child's unused budget to its parent
/// (and per-cap selective revocation) is future work.
module SupWallet::sub_delegate {
    use std::{
        type_name::{Self, TypeName},
    };
    use sui::{
        event,
    };
    use SupWallet::wallet::{Self, Wallet};
    use SupWallet::policy::{Self, SpendRequest};

    /// Cap presented against a different wallet than it was minted for.
    const EWrongWallet: u64 = 1;
    /// Cap's policy version is stale — owner revoked (bumped version) since mint.
    const ECapRevoked: u64 = 2;
    /// Request coin type does not match the cap's scoped coin.
    const EWrongCoin: u64 = 3;
    /// Spend (or subdelegation) exceeds the cap's remaining budget.
    const EInsufficientBudget: u64 = 4;
    /// Subdelegation would exceed the tree's `max_depth`.
    const EMaxDepthExceeded: u64 = 5;

    /// Budget-carrying, attenuable capability. Scoped to one coin type.
    public struct ScopedCap has key, store {
        id: UID,
        wallet_id: ID,
        policy_version: u64,
        /// The coin type this cap may spend.
        coin: TypeName,
        /// Remaining budget in `coin`. Debited on spend; moved on subdelegate.
        remaining: u64,
        /// 0 for a root cap; +1 per subdelegation level.
        depth: u8,
        /// Deepest `depth` any descendant may reach. Copied down unchanged.
        max_depth: u8,
        /// `None` for a root cap; the parent cap's id otherwise.
        parent: Option<ID>,
    }

    /// Auth-rule witness (the "who"). Stamped by `spend`.
    public struct ScopedAuth has drop {}

    /// Caveat-rule witness (the "how much"). Stamped by `spend` after debit.
    public struct ScopedBudget has drop {}

    public struct ScopedCapMinted has copy, drop {
        wallet_id: ID,
        cap_id: ID,
        coin: TypeName,
        budget: u64,
        depth: u8,
        max_depth: u8,
        parent: Option<ID>,
    }

    public struct ScopedSpent has copy, drop {
        wallet_id: ID,
        cap_id: ID,
        coin: TypeName,
        amount: u64,
        remaining: u64,
    }

    /// ===== owner: mint a root cap =====

    /// Owner mints a root cap scoped to `CoinT` with `budget`, allowing up to
    /// `max_depth` levels of subdelegation beneath it. Returns it for routing.
    public fun mint_root<CoinT>(
        wallet: &Wallet,
        budget: u64,
        max_depth: u8,
        ctx: &mut TxContext,
    ): ScopedCap {
        wallet::assert_owner(wallet, ctx);
        let coin = type_name::with_defining_ids<CoinT>();
        let cap = ScopedCap {
            id: object::new(ctx),
            wallet_id: wallet::id(wallet),
            policy_version: policy::version(wallet),
            coin,
            remaining: budget,
            depth: 0,
            max_depth,
            parent: option::none(),
        };
        emit_minted(&cap);
        cap
    }

    public fun mint_root_and_transfer<CoinT>(
        wallet: &Wallet,
        budget: u64,
        max_depth: u8,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        transfer::public_transfer(mint_root<CoinT>(wallet, budget, max_depth, ctx), recipient);
    }

    /// ===== holder: attenuated subdelegation =====

    /// Carve `amount` out of `parent`'s remaining budget into a fresh child cap
    /// at `depth + 1`. The child can never outspend `amount`, and `parent` is
    /// debited immediately so the chain's total is conserved.
    public fun subdelegate(parent: &mut ScopedCap, amount: u64, ctx: &mut TxContext): ScopedCap {
        assert!(parent.depth < parent.max_depth, EMaxDepthExceeded);
        assert!(parent.remaining >= amount, EInsufficientBudget);
        parent.remaining = parent.remaining - amount;
        let child = ScopedCap {
            id: object::new(ctx),
            wallet_id: parent.wallet_id,
            policy_version: parent.policy_version,
            coin: parent.coin,
            remaining: amount,
            depth: parent.depth + 1,
            max_depth: parent.max_depth,
            parent: option::some(object::id(parent)),
        };
        emit_minted(&child);
        child
    }

    public fun subdelegate_and_transfer(
        parent: &mut ScopedCap,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        transfer::public_transfer(subdelegate(parent, amount, ctx), recipient);
    }

    /// ===== rule: spend =====

    /// Debit the cap's budget for the request and stamp both the auth and the
    /// budget receipts. Aborts if the cap is for another wallet, stale, scoped to
    /// a different coin, or out of budget. Self-contained: a wallet that accepts
    /// `ScopedAuth` + `ScopedBudget` needs no other rule for scoped caps.
    public fun spend(cap: &mut ScopedCap, req: &mut SpendRequest) {
        assert!(cap.wallet_id == policy::spend_wallet_id(req), EWrongWallet);
        assert!(cap.policy_version == policy::spend_policy_version(req), ECapRevoked);
        assert!(cap.coin == policy::spend_coin(req), EWrongCoin);
        let amount = policy::spend_amount(req);
        assert!(cap.remaining >= amount, EInsufficientBudget);
        cap.remaining = cap.remaining - amount;

        policy::add_auth_receipt(ScopedAuth {}, req);
        policy::add_caveat_receipt(ScopedBudget {}, req);

        event::emit(ScopedSpent {
            wallet_id: cap.wallet_id,
            cap_id: object::id(cap),
            coin: cap.coin,
            amount,
            remaining: cap.remaining,
        });
    }

    /// Holder discards their cap. Unused budget is NOT refunded to the parent in
    /// this version.
    public fun burn(cap: ScopedCap) {
        let ScopedCap { id, wallet_id: _, policy_version: _, coin: _, remaining: _, depth: _, max_depth: _, parent: _ } = cap;
        id.delete();
    }

    /// ===== reads =====

    public fun remaining(cap: &ScopedCap): u64 { cap.remaining }
    public fun coin(cap: &ScopedCap): TypeName { cap.coin }
    public fun depth(cap: &ScopedCap): u8 { cap.depth }
    public fun max_depth(cap: &ScopedCap): u8 { cap.max_depth }
    public fun wallet_id(cap: &ScopedCap): ID { cap.wallet_id }
    public fun policy_version(cap: &ScopedCap): u64 { cap.policy_version }
    public fun parent(cap: &ScopedCap): Option<ID> { cap.parent }

    /// ===== internal =====

    fun emit_minted(cap: &ScopedCap) {
        event::emit(ScopedCapMinted {
            wallet_id: cap.wallet_id,
            cap_id: object::id(cap),
            coin: cap.coin,
            budget: cap.remaining,
            depth: cap.depth,
            max_depth: cap.max_depth,
            parent: cap.parent,
        });
    }
}

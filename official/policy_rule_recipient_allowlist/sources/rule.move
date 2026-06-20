/// # Recipient-allowlist caveat rule — a reference third-party rule package
///
/// This package is **not** part of `SupWallet`. It is a worked example of how
/// *anyone* writes a delegation-policy rule and plugs it into a wallet using only
/// `SupWallet`'s public interface — no changes to, and no special permission
/// from, the core. The same shape works for any condition: time windows, oracle
/// prices, KYC attestations, an 8183 job being settled, etc.
///
/// A caveat rule is two things:
///   1. a **witness type** (`RecipientAllowlist`) that only this module can build;
///   2. an **enforce** entrypoint that checks a condition against the request and,
///      if it holds, stamps the witness via `policy::add_caveat_receipt`.
///
/// Integration (all owner-driven, all on the public API):
///   - owner deploys this package (and optionally lists it in `policy_rule_registry`);
///   - owner creates an `Allowlist` config bound to their wallet and shares it;
///   - owner calls `policy::add_caveat_rule<RecipientAllowlist>(&mut wallet)`;
///   - a spender, between `policy::begin_spend` and `policy::confirm_spend`, calls
///     `rule::enforce(&allowlist, &mut req)`.
///
/// Owner-gating here uses the public `wallet::owner` accessor (the core's
/// `assert_owner` is package-private, but third parties don't need it — reading
/// the owner address and comparing to the sender is enough).
module policy_rule_recipient_allowlist::rule {
    use sui::{
        object::{Self, ID, UID},
        tx_context::{Self, TxContext},
        transfer,
        vec_set::{Self, VecSet},
        event,
    };
    use SupWallet::wallet::{Self, Wallet};
    use SupWallet::policy::{Self, SpendRequest};

    /// Recipient is not on the allowlist.
    const ENotAllowed: u64 = 1;
    /// This allowlist config is bound to a different wallet than the request.
    const EWrongWallet: u64 = 2;
    /// Caller is not the wallet owner.
    const ENotOwner: u64 = 3;

    /// Caveat-rule witness. Only this module can construct it.
    public struct RecipientAllowlist has drop {}

    /// Owner-managed config object listing the recipients a delegated spend may
    /// pay. Shared so any spender can reference it inside their PTB.
    public struct Allowlist has key, store {
        id: UID,
        wallet_id: ID,
        owner: address,
        allowed: VecSet<address>,
    }

    public struct AllowlistCreated has copy, drop { allowlist_id: ID, wallet_id: ID }
    public struct AllowlistChanged has copy, drop { allowlist_id: ID, recipient: address, allowed: bool }

    /// ===== owner: config lifecycle =====

    public fun create(wallet: &Wallet, ctx: &mut TxContext): Allowlist {
        let owner = wallet::owner(wallet);
        assert!(tx_context::sender(ctx) == owner, ENotOwner);
        let list = Allowlist {
            id: object::new(ctx),
            wallet_id: wallet::id(wallet),
            owner,
            allowed: vec_set::empty<address>(),
        };
        event::emit(AllowlistCreated { allowlist_id: object::id(&list), wallet_id: list.wallet_id });
        list
    }

    public fun create_and_share(wallet: &Wallet, ctx: &mut TxContext) {
        transfer::share_object(create(wallet, ctx));
    }

    public fun allow(list: &mut Allowlist, recipient: address, ctx: &TxContext) {
        assert!(tx_context::sender(ctx) == list.owner, ENotOwner);
        if (!list.allowed.contains(&recipient)) {
            list.allowed.insert(recipient);
        };
        event::emit(AllowlistChanged { allowlist_id: object::id(list), recipient, allowed: true });
    }

    public fun disallow(list: &mut Allowlist, recipient: address, ctx: &TxContext) {
        assert!(tx_context::sender(ctx) == list.owner, ENotOwner);
        if (list.allowed.contains(&recipient)) {
            list.allowed.remove(&recipient);
        };
        event::emit(AllowlistChanged { allowlist_id: object::id(list), recipient, allowed: false });
    }

    /// ===== rule: enforce =====

    /// Stamp `RecipientAllowlist` onto the request iff the config is for this
    /// wallet and the request's recipient is allowed. Read-only on the request
    /// apart from the stamp — cannot touch amount/recipient.
    public fun enforce(list: &Allowlist, req: &mut SpendRequest) {
        assert!(list.wallet_id == policy::spend_wallet_id(req), EWrongWallet);
        assert!(list.allowed.contains(&policy::spend_recipient(req)), ENotAllowed);
        policy::add_caveat_receipt(RecipientAllowlist {}, req);
    }

    /// ===== reads =====

    public fun is_allowed(list: &Allowlist, recipient: address): bool {
        list.allowed.contains(&recipient)
    }

    public fun wallet_id(list: &Allowlist): ID { list.wallet_id }
}

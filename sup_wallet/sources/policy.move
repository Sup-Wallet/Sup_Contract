/// # Delegation Policy — pluggable, condition-gated fund unlocking
///
/// Generalizes `delegate.move`: instead of "a delegate is an address with a
/// hard-coded budget", the wallet owner attaches a set of **pluggable rule
/// witnesses** to their wallet, and any spend must be approved by those rules
/// before funds are released. A "delegate" becomes *whoever / whatever can
/// satisfy the rules* — an address, a `Cap` object, a contract's witness, a ZK
/// proof, an oracle condition, an 8183 job assessor, ...
///
/// This is the Sui `TransferPolicy` / kiosk model applied to fund delegation:
///   - `DelegationPolicy` (owner-set, DF on `Wallet`)  ~ `TransferPolicy<T>`
///   - `SpendRequest`     (hot potato, carries facts)  ~ `TransferRequest<T>`
///   - rule witness + `add_*_receipt`                  ~ `Rule` + `add_receipt`
///   - `confirm_spend`    (releases the coin)          ~ `confirm_request`
///
/// Flow:
///   1. `begin_spend<CoinT>(&wallet, amount, recipient)` -> `SpendRequest`
///      (permissionless to *start*; gated at the end, not the start)
///   2. rule modules stamp it (witness-gated):
///        - auth rules  (OR-gated): `add_auth_receipt<R>(R{}, &mut req)`
///        - caveat rules (AND-gated): `add_caveat_receipt<R>(R{}, &mut req)`
///      A rule reads `spend_amount` / `spend_recipient` / `spend_coin` but
///      CANNOT mutate them — it can only stamp or `abort`.
///   3. `confirm_spend<CoinT>(&mut wallet, req, ctx)` aborts unless at least one
///      owner-trusted auth rule matched AND every owner-attached caveat rule
///      matched AND the policy version is still current; then withdraws and
///      transfers the coin to `recipient`. (`confirm_spend_into` runs the SAME
///      gate but RETURNS the coin to the PTB — the composition primitive for
///      funding escrow / a swap within one atomic transaction.)
///
/// `delegate.move` is left intact as the backward-compatible "address + budget"
/// preset; new capability is built here.
module SupWallet::policy {
    use std::type_name::{Self, TypeName};
    use sui::{
        coin::Coin,
        dynamic_field as df,
        vec_set::{Self, VecSet},
        event,
    };
    use SupWallet::wallet::{Self, Wallet};

    const POLICY_DF_KEY: vector<u8> = b"delegation_policy";

    const ENotInitialized: u64 = 1;
    const EAlreadyInitialized: u64 = 2;
    /// `confirm_spend` saw no auth rule that the policy trusts.
    const EAuthNotProven: u64 = 3;
    /// `confirm_spend` is missing at least one required caveat receipt.
    const EMissingCaveat: u64 = 4;
    /// The policy was revoked (version bumped) after this request began.
    const EStaleVersion: u64 = 5;
    /// Request was started against a different wallet than the one confirming.
    const EWrongWallet: u64 = 6;
    /// Request coin type does not match the `CoinT` confirm was called with.
    const EWrongCoin: u64 = 7;

    /// Per-wallet policy. Lives as a DF on `Wallet.id` under `POLICY_DF_KEY`.
    public struct DelegationPolicy has store {
        /// Bumped by `revoke_all` to invalidate every in-flight `SpendRequest`.
        version: u64,
        /// OR-gated principal proofs. Any one match authorizes the spender.
        auth_rules: VecSet<TypeName>,
        /// AND-gated conditions. Every one must be satisfied.
        caveat_rules: VecSet<TypeName>,
    }

    /// Hot potato. No abilities: a `SpendRequest` must reach `confirm_spend` or
    /// the whole transaction aborts. Carries the immutable facts of the spend so
    /// rules can inspect them; rules can only append to the receipt sets.
    public struct SpendRequest {
        wallet_id: ID,
        coin: TypeName,
        amount: u64,
        recipient: address,
        policy_version: u64,
        auth_receipts: VecSet<TypeName>,
        caveat_receipts: VecSet<TypeName>,
    }

    /// ===== events =====

    public struct PolicyInitialized has copy, drop {
        wallet_id: ID,
        version: u64,
    }

    public struct AuthRuleChanged has copy, drop {
        wallet_id: ID,
        rule: TypeName,
        added: bool,
    }

    public struct CaveatRuleChanged has copy, drop {
        wallet_id: ID,
        rule: TypeName,
        added: bool,
    }

    public struct PolicyRevoked has copy, drop {
        wallet_id: ID,
        new_version: u64,
    }

    public struct SpendConfirmed has copy, drop {
        wallet_id: ID,
        coin: TypeName,
        amount: u64,
        recipient: address,
        policy_version: u64,
    }

    /// ===== owner: policy lifecycle =====

    public fun initialize(wallet: &mut Wallet, ctx: &TxContext) {
        wallet::assert_owner(wallet, ctx);
        let wallet_id = wallet::id(wallet);
        let uid_mut = wallet::uid_mut(wallet);
        assert!(!df::exists(uid_mut, POLICY_DF_KEY), EAlreadyInitialized);
        df::add(uid_mut, POLICY_DF_KEY, DelegationPolicy {
            version: 1,
            auth_rules: vec_set::empty<TypeName>(),
            caveat_rules: vec_set::empty<TypeName>(),
        });
        event::emit(PolicyInitialized { wallet_id, version: 1 });
    }

    public fun add_auth_rule<RuleT>(wallet: &mut Wallet, ctx: &TxContext) {
        wallet::assert_owner(wallet, ctx);
        let wallet_id = wallet::id(wallet);
        let key = type_name::with_defining_ids<RuleT>();
        let policy = borrow_mut(wallet);
        if (!policy.auth_rules.contains(&key)) {
            policy.auth_rules.insert(key);
        };
        event::emit(AuthRuleChanged { wallet_id, rule: key, added: true });
    }

    public fun remove_auth_rule<RuleT>(wallet: &mut Wallet, ctx: &TxContext) {
        wallet::assert_owner(wallet, ctx);
        let wallet_id = wallet::id(wallet);
        let key = type_name::with_defining_ids<RuleT>();
        let policy = borrow_mut(wallet);
        if (policy.auth_rules.contains(&key)) {
            policy.auth_rules.remove(&key);
        };
        event::emit(AuthRuleChanged { wallet_id, rule: key, added: false });
    }

    public fun add_caveat_rule<RuleT>(wallet: &mut Wallet, ctx: &TxContext) {
        wallet::assert_owner(wallet, ctx);
        let wallet_id = wallet::id(wallet);
        let key = type_name::with_defining_ids<RuleT>();
        let policy = borrow_mut(wallet);
        if (!policy.caveat_rules.contains(&key)) {
            policy.caveat_rules.insert(key);
        };
        event::emit(CaveatRuleChanged { wallet_id, rule: key, added: true });
    }

    public fun remove_caveat_rule<RuleT>(wallet: &mut Wallet, ctx: &TxContext) {
        wallet::assert_owner(wallet, ctx);
        let wallet_id = wallet::id(wallet);
        let key = type_name::with_defining_ids<RuleT>();
        let policy = borrow_mut(wallet);
        if (policy.caveat_rules.contains(&key)) {
            policy.caveat_rules.remove(&key);
        };
        event::emit(CaveatRuleChanged { wallet_id, rule: key, added: false });
    }

    /// Mass-revoke: bumps the policy version so every `SpendRequest` started
    /// against the old version aborts at `confirm_spend`. The intended global
    /// kill-switch for delegate caps / sub-delegations bound to a version.
    public fun revoke_all(wallet: &mut Wallet, ctx: &TxContext) {
        wallet::assert_owner(wallet, ctx);
        let wallet_id = wallet::id(wallet);
        let policy = borrow_mut(wallet);
        policy.version = policy.version + 1;
        let new_version = policy.version;
        event::emit(PolicyRevoked { wallet_id, new_version });
    }

    /// ===== spend flow =====

    /// Begin a policy-gated spend. Permissionless to *call*: the request is inert
    /// until rules stamp it, and `confirm_spend` is the gate. Snapshots the
    /// current policy version so a concurrent `revoke_all` invalidates it.
    public fun begin_spend<CoinT>(
        wallet: &Wallet,
        amount: u64,
        recipient: address,
    ): SpendRequest {
        let policy = borrow(wallet);
        SpendRequest {
            wallet_id: wallet::id(wallet),
            coin: type_name::with_defining_ids<CoinT>(),
            amount,
            recipient,
            policy_version: policy.version,
            auth_receipts: vec_set::empty<TypeName>(),
            caveat_receipts: vec_set::empty<TypeName>(),
        }
    }

    /// Witness-gated. A principal/auth rule module stamps its own `RuleT` after
    /// proving who the spender is. Only the module defining `RuleT` can build an
    /// `RuleT` value, so it cannot be forged. Auth rules are OR-gated.
    public fun add_auth_receipt<RuleT: drop>(_witness: RuleT, req: &mut SpendRequest) {
        let key = type_name::with_defining_ids<RuleT>();
        if (!req.auth_receipts.contains(&key)) {
            req.auth_receipts.insert(key);
        };
    }

    /// Witness-gated. A caveat rule module stamps its own `RuleT` after enforcing
    /// its condition (budget, time, recipient allowlist, ...). Caveats are
    /// AND-gated: `confirm_spend` requires every owner-attached caveat present.
    public fun add_caveat_receipt<RuleT: drop>(_witness: RuleT, req: &mut SpendRequest) {
        let key = type_name::with_defining_ids<RuleT>();
        if (!req.caveat_receipts.contains(&key)) {
            req.caveat_receipts.insert(key);
        };
    }

    /// Cash out the request, **returning** the released coin to the caller's PTB
    /// instead of paying `recipient`. Runs the identical gate as `confirm_spend`.
    /// Aborts unless:
    ///   - the request targets this wallet and `CoinT` matches,
    ///   - the policy version is unchanged since `begin_spend`,
    ///   - at least one of the policy's auth rules stamped (OR),
    ///   - every one of the policy's caveat rules stamped (AND).
    /// On success, withdraws `amount` of `CoinT` and hands it back.
    ///
    /// Use to compose a policy-bounded spend into escrow / a swap within one
    /// atomic transaction — the released amount is still bounded by the owner's
    /// allowance. NOTE: on this path `recipient` is the *declared* destination
    /// (emitted for audit) but is NOT enforced by the core; the PTB is trusted to
    /// route the returned coin. Recipient-sensitive caveats (e.g. an allowlist)
    /// are therefore compose-enforced — not core-enforced — with this variant.
    public fun confirm_spend_into<CoinT>(
        wallet: &mut Wallet,
        req: SpendRequest,
        ctx: &mut TxContext,
    ): Coin<CoinT> {
        let SpendRequest {
            wallet_id,
            coin,
            amount,
            recipient,
            policy_version,
            auth_receipts,
            caveat_receipts,
        } = req;

        assert!(wallet_id == wallet::id(wallet), EWrongWallet);
        assert!(coin == type_name::with_defining_ids<CoinT>(), EWrongCoin);

        let policy = borrow(wallet);
        assert!(policy_version == policy.version, EStaleVersion);
        assert!(any_present(&policy.auth_rules, &auth_receipts), EAuthNotProven);
        assert!(all_present(&policy.caveat_rules, &caveat_receipts), EMissingCaveat);

        event::emit(SpendConfirmed {
            wallet_id,
            coin,
            amount,
            recipient,
            policy_version,
        });

        wallet::pay_by_policy<CoinT>(wallet, amount, ctx)
    }

    /// Cash out the request and transfer the released coin to `recipient`.
    /// Thin wrapper over `confirm_spend_into` — behaviour unchanged.
    public fun confirm_spend<CoinT>(
        wallet: &mut Wallet,
        req: SpendRequest,
        ctx: &mut TxContext,
    ) {
        let recipient = req.recipient;
        let paid = confirm_spend_into<CoinT>(wallet, req, ctx);
        transfer::public_transfer(paid, recipient);
    }

    /// ===== request reads (for rule modules) =====

    public fun spend_wallet_id(req: &SpendRequest): ID { req.wallet_id }

    public fun spend_coin(req: &SpendRequest): TypeName { req.coin }

    public fun spend_amount(req: &SpendRequest): u64 { req.amount }

    public fun spend_recipient(req: &SpendRequest): address { req.recipient }

    public fun spend_policy_version(req: &SpendRequest): u64 { req.policy_version }

    public fun has_auth_receipt<RuleT>(req: &SpendRequest): bool {
        req.auth_receipts.contains(&type_name::with_defining_ids<RuleT>())
    }

    public fun has_caveat_receipt<RuleT>(req: &SpendRequest): bool {
        req.caveat_receipts.contains(&type_name::with_defining_ids<RuleT>())
    }

    /// ===== policy reads =====

    public fun is_initialized(wallet: &Wallet): bool {
        df::exists(wallet::uid(wallet), POLICY_DF_KEY)
    }

    public fun version(wallet: &Wallet): u64 {
        borrow(wallet).version
    }

    public fun has_auth_rule<RuleT>(wallet: &Wallet): bool {
        borrow(wallet).auth_rules.contains(&type_name::with_defining_ids<RuleT>())
    }

    public fun has_caveat_rule<RuleT>(wallet: &Wallet): bool {
        borrow(wallet).caveat_rules.contains(&type_name::with_defining_ids<RuleT>())
    }

    public fun auth_rule_count(wallet: &Wallet): u64 {
        borrow(wallet).auth_rules.length()
    }

    public fun caveat_rule_count(wallet: &Wallet): u64 {
        borrow(wallet).caveat_rules.length()
    }

    /// ===== internal helpers =====

    /// True if at least one key in `required` is present in `got` (OR).
    /// Empty `required` => false (no trusted auth rule => nothing can authorize).
    fun any_present(required: &VecSet<TypeName>, got: &VecSet<TypeName>): bool {
        let keys = required.keys();
        let n = keys.length();
        let mut i = 0;
        while (i < n) {
            if (got.contains(&keys[i])) return true;
            i = i + 1;
        };
        false
    }

    /// True if every key in `required` is present in `got` (AND).
    /// Empty `required` => true (no caveats => only auth gates the spend).
    fun all_present(required: &VecSet<TypeName>, got: &VecSet<TypeName>): bool {
        let keys = required.keys();
        let n = keys.length();
        let mut i = 0;
        while (i < n) {
            if (!got.contains(&keys[i])) return false;
            i = i + 1;
        };
        true
    }

    fun borrow(wallet: &Wallet): &DelegationPolicy {
        let uid: &UID = wallet::uid(wallet);
        assert!(df::exists(uid, POLICY_DF_KEY), ENotInitialized);
        df::borrow<vector<u8>, DelegationPolicy>(uid, POLICY_DF_KEY)
    }

    fun borrow_mut(wallet: &mut Wallet): &mut DelegationPolicy {
        let uid_mut: &mut UID = wallet::uid_mut(wallet);
        assert!(df::exists(uid_mut, POLICY_DF_KEY), ENotInitialized);
        df::borrow_mut<vector<u8>, DelegationPolicy>(uid_mut, POLICY_DF_KEY)
    }
}

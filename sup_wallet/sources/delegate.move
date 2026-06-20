module SupWallet::delegate {
    use std::type_name::{Self, TypeName};
    use sui::{
        dynamic_field as df,
        table::{Self, Table},
        coin::Coin,
        event,
    };
    use zzyzx_framework::key_bigvector::{Self, KeyedBigVector};
    use SupWallet::wallet::{Self, AnyCoin, Wallet};

    const REGISTRY_DF_KEY: vector<u8> = b"delegate";
    const INNER_SLICE_SIZE: u32 = 1024;

    /// Sentinel returned by `service_allowance` / `coin_allowance` for `main_owner`,
    /// reported in `*AllowanceDebited` when main_owner spends through this flow,
    /// and usable by owners as a true no-decrement unlimited delegate allowance.
    const UNLIMITED: u64 = 0xFFFFFFFFFFFFFFFF;

    const ENotInitialized: u64 = 1;
    const EAlreadyInitialized: u64 = 2;
    const ENotFound: u64 = 3;
    const EAlreadyExists: u64 = 4;
    const EServiceNotSet: u64 = 5;
    const ECoinNotSet: u64 = 6;
    const EInsufficientServiceAllowance: u64 = 7;
    const EInsufficientCoinAllowance: u64 = 8;
    const ENotDelegate: u64 = 9;
    const EServiceNotAuthorized: u64 = 10;
    /// Tried to manage allowance against `main_owner`, who has unlimited budget.
    const EMainOwnerNoAllowance: u64 = 11;

    /// Per-entry state for a registered delegate. Two parallel budget tables, both
    /// AND-gated and both debited on spend:
    ///   - `by_service` : per-service remaining   (key = ServiceT TypeName)
    ///   - `by_coin`    : per-coin universal      (key = CoinType TypeName)
    /// "Universal" = not scoped to any service. A delegate can be capped on, e.g., SUI
    /// total across all services regardless of which service they spent through.
    public struct Entry has store {
        by_service: KeyedBigVector,
        by_coin: KeyedBigVector,
    }

    /// The delegate registry. Lives as a dynamic field on `Wallet.id` under
    /// `REGISTRY_DF_KEY`. `main_owner` is recorded once at `init` (copied from
    /// `wallet.owner`) and never appears in `entries`. main_owner bypasses both budgets
    /// (`UNLIMITED` across the board). Allowance management fns abort with
    /// `EMainOwnerNoAllowance` if called against main_owner.
    public struct Delegate has store {
        main_owner: address,
        entries: Table<address, Entry>,
    }

    /// ===== events =====

    public struct Initialized has copy, drop {
        wallet_id: sui::object::ID,
        main_owner: address,
    }

    public struct Added has copy, drop {
        wallet_id: sui::object::ID,
        delegate: address,
    }

    public struct Removed has copy, drop {
        wallet_id: sui::object::ID,
        delegate: address,
    }

    public struct ServiceAllowanceChanged has copy, drop {
        wallet_id: sui::object::ID,
        delegate: address,
        service: TypeName,
        new_amount: u64,
    }

    public struct CoinAllowanceChanged has copy, drop {
        wallet_id: sui::object::ID,
        delegate: address,
        coin: TypeName,
        new_amount: u64,
    }

    public struct ServiceAllowanceDebited has copy, drop {
        wallet_id: sui::object::ID,
        spender: address,
        service: TypeName,
        amount: u64,
        remaining: u64,
    }

    public struct CoinAllowanceDebited has copy, drop {
        wallet_id: sui::object::ID,
        spender: address,
        coin: TypeName,
        amount: u64,
        remaining: u64,
    }

    /// ===== main owner: registry lifecycle =====

    public fun initialize(wallet: &mut Wallet, ctx: &mut TxContext) {
        wallet::assert_owner(wallet, ctx);
        let wallet_id = wallet::id(wallet);
        let main_owner = wallet::owner(wallet);
        let uid_mut = wallet::uid_mut(wallet);
        assert!(!df::exists(uid_mut, REGISTRY_DF_KEY), EAlreadyInitialized);
        let registry = Delegate {
            main_owner,
            entries: table::new<address, Entry>(ctx),
        };
        df::add(uid_mut, REGISTRY_DF_KEY, registry);
        event::emit(Initialized { wallet_id, main_owner });
    }

    /// ===== main owner: delegate lifecycle =====

    public fun add(wallet: &mut Wallet, delegate: address, ctx: &mut TxContext) {
        wallet::assert_owner(wallet, ctx);
        let wallet_id = wallet::id(wallet);
        let by_service = key_bigvector::new<TypeName, u64>(INNER_SLICE_SIZE, ctx);
        let by_coin = key_bigvector::new<TypeName, u64>(INNER_SLICE_SIZE, ctx);
        let reg = borrow_mut(wallet);
        assert!(delegate != reg.main_owner, EMainOwnerNoAllowance);
        assert!(!reg.entries.contains(delegate), EAlreadyExists);
        reg.entries.add(delegate, Entry { by_service, by_coin });
        event::emit(Added { wallet_id, delegate });
    }

    public fun remove(wallet: &mut Wallet, delegate: address, ctx: &TxContext) {
        wallet::assert_owner(wallet, ctx);
        let wallet_id = wallet::id(wallet);
        let reg = borrow_mut(wallet);
        assert!(reg.entries.contains(delegate), ENotFound);
        let Entry { by_service, by_coin } = reg.entries.remove(delegate);
        key_bigvector::completely_drop<TypeName, u64>(by_service);
        key_bigvector::completely_drop<TypeName, u64>(by_coin);
        event::emit(Removed { wallet_id, delegate });
    }

    /// ===== main owner: per-service allowance (delegates only) =====

    public fun set_service_allowance<ServiceT>(wallet: &mut Wallet, delegate: address, amount: u64, ctx: &TxContext) {
        wallet::assert_owner(wallet, ctx);
        let wallet_id = wallet::id(wallet);
        let key = type_name::with_defining_ids<ServiceT>();
        let inner = borrow_service_mut(wallet, delegate);
        if (inner.contains(key)) {
            let v: &mut u64 = &mut inner[key];
            *v = amount;
        } else {
            inner.push_back(key, amount);
        };
        event::emit(ServiceAllowanceChanged { wallet_id, delegate, service: key, new_amount: amount });
    }

    public fun increase_service_allowance<ServiceT>(wallet: &mut Wallet, delegate: address, delta: u64, ctx: &TxContext) {
        wallet::assert_owner(wallet, ctx);
        let wallet_id = wallet::id(wallet);
        let key = type_name::with_defining_ids<ServiceT>();
        let inner = borrow_service_mut(wallet, delegate);
        let new_amount;
        if (inner.contains(key)) {
            let v: &mut u64 = &mut inner[key];
            *v = *v + delta;
            new_amount = *v;
        } else {
            inner.push_back(key, delta);
            new_amount = delta;
        };
        event::emit(ServiceAllowanceChanged { wallet_id, delegate, service: key, new_amount });
    }

    public fun decrease_service_allowance<ServiceT>(wallet: &mut Wallet, delegate: address, delta: u64, ctx: &TxContext) {
        wallet::assert_owner(wallet, ctx);
        let wallet_id = wallet::id(wallet);
        let key = type_name::with_defining_ids<ServiceT>();
        let inner = borrow_service_mut(wallet, delegate);
        assert!(inner.contains(key), EServiceNotSet);
        let v: &mut u64 = &mut inner[key];
        assert!(*v >= delta, EInsufficientServiceAllowance);
        *v = *v - delta;
        let new_amount = *v;
        event::emit(ServiceAllowanceChanged { wallet_id, delegate, service: key, new_amount });
    }

    public fun set_service_unlimited_allowance<ServiceT>(wallet: &mut Wallet, delegate: address, ctx: &TxContext) {
        set_service_allowance<ServiceT>(wallet, delegate, UNLIMITED, ctx);
    }

    /// ===== main owner: per-coin allowance (delegates only) =====

    public fun set_coin_allowance<CoinT>(wallet: &mut Wallet, delegate: address, amount: u64, ctx: &TxContext) {
        wallet::assert_owner(wallet, ctx);
        let wallet_id = wallet::id(wallet);
        let key = type_name::with_defining_ids<CoinT>();
        let inner = borrow_coin_mut(wallet, delegate);
        if (inner.contains(key)) {
            let v: &mut u64 = &mut inner[key];
            *v = amount;
        } else {
            inner.push_back(key, amount);
        };
        event::emit(CoinAllowanceChanged { wallet_id, delegate, coin: key, new_amount: amount });
    }

    public fun increase_coin_allowance<CoinT>(wallet: &mut Wallet, delegate: address, delta: u64, ctx: &TxContext) {
        wallet::assert_owner(wallet, ctx);
        let wallet_id = wallet::id(wallet);
        let key = type_name::with_defining_ids<CoinT>();
        let inner = borrow_coin_mut(wallet, delegate);
        let new_amount;
        if (inner.contains(key)) {
            let v: &mut u64 = &mut inner[key];
            *v = *v + delta;
            new_amount = *v;
        } else {
            inner.push_back(key, delta);
            new_amount = delta;
        };
        event::emit(CoinAllowanceChanged { wallet_id, delegate, coin: key, new_amount });
    }

    public fun decrease_coin_allowance<CoinT>(wallet: &mut Wallet, delegate: address, delta: u64, ctx: &TxContext) {
        wallet::assert_owner(wallet, ctx);
        let wallet_id = wallet::id(wallet);
        let key = type_name::with_defining_ids<CoinT>();
        let inner = borrow_coin_mut(wallet, delegate);
        assert!(inner.contains(key), ECoinNotSet);
        let v: &mut u64 = &mut inner[key];
        assert!(*v >= delta, EInsufficientCoinAllowance);
        *v = *v - delta;
        let new_amount = *v;
        event::emit(CoinAllowanceChanged { wallet_id, delegate, coin: key, new_amount });
    }

    /// Wildcard coin allowance. Used when a delegate should be capped by
    /// amount but not by a specific token type.
    public fun set_any_coin_allowance(wallet: &mut Wallet, delegate: address, amount: u64, ctx: &TxContext) {
        set_coin_allowance<AnyCoin>(wallet, delegate, amount, ctx);
    }

    public fun increase_any_coin_allowance(wallet: &mut Wallet, delegate: address, delta: u64, ctx: &TxContext) {
        increase_coin_allowance<AnyCoin>(wallet, delegate, delta, ctx);
    }

    public fun decrease_any_coin_allowance(wallet: &mut Wallet, delegate: address, delta: u64, ctx: &TxContext) {
        decrease_coin_allowance<AnyCoin>(wallet, delegate, delta, ctx);
    }

    public fun set_coin_unlimited_allowance<CoinT>(wallet: &mut Wallet, delegate: address, ctx: &TxContext) {
        set_coin_allowance<CoinT>(wallet, delegate, UNLIMITED, ctx);
    }

    public fun set_any_coin_unlimited_allowance(wallet: &mut Wallet, delegate: address, ctx: &TxContext) {
        set_any_coin_allowance(wallet, delegate, UNLIMITED, ctx);
    }

    /// Full allowance for one service: unlimited amount and any coin type.
    /// Pair this with `wallet::grant_service_any_coin<ServiceT>`.
    public fun set_unlimited_allowance<ServiceT>(wallet: &mut Wallet, delegate: address, ctx: &TxContext) {
        set_service_allowance<ServiceT>(wallet, delegate, UNLIMITED, ctx);
        set_any_coin_allowance(wallet, delegate, UNLIMITED, ctx);
    }

    /// ===== spender path =====

    /// Spend through the delegate flow. Caller (`ctx.sender()`) is either main_owner
    /// (unlimited, both debits no-op) or a registered delegate (both debits applied).
    /// `wallet::is_authorized<ServiceT, CoinT>` must also hold.
    public fun spend<ServiceT: drop, CoinT>(
        _witness: ServiceT,
        wallet: &mut Wallet,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        assert!(wallet::is_authorized<ServiceT, CoinT>(wallet), EServiceNotAuthorized);
        let spender = ctx.sender();
        debit_service_allowance<ServiceT>(wallet, spender, amount);
        debit_coin_allowance<CoinT>(wallet, spender, amount);
        let coin: Coin<CoinT> = wallet::pay_by_service<ServiceT, CoinT>(wallet, amount, ctx);
        transfer::public_transfer(coin, recipient);
    }

    /// ===== read-only views =====

    public fun is_initialized(wallet: &Wallet): bool {
        df::exists(wallet::uid(wallet), REGISTRY_DF_KEY)
    }

    public fun main_owner(wallet: &Wallet): address {
        borrow(wallet).main_owner
    }

    public fun contains(wallet: &Wallet, delegate: address): bool {
        if (!is_initialized(wallet)) return false;
        borrow(wallet).entries.contains(delegate)
    }

    /// Per-service remaining. `UNLIMITED` for main_owner; actual remaining for
    /// a delegate; 0 if no specific service cap is set.
    public fun service_allowance<ServiceT>(wallet: &Wallet, who: address): u64 {
        if (!is_initialized(wallet)) return 0;
        let reg = borrow(wallet);
        if (who == reg.main_owner) return UNLIMITED;
        if (!reg.entries.contains(who)) return 0;
        let inner: &KeyedBigVector = &reg.entries.borrow(who).by_service;
        let key = type_name::with_defining_ids<ServiceT>();
        if (inner.contains(key)) {
            let v: &u64 = &inner[key];
            return *v
        };
        0
    }

    /// Returns whether `who` is allowed to operate `ServiceT`, independently
    /// of the remaining spend amount. This is intended for service actions
    /// that can only move value back into the wallet, such as collecting fees,
    /// removing liquidity, or closing an empty external position.
    public fun is_service_authorized<ServiceT>(wallet: &Wallet, who: address): bool {
        if (!is_initialized(wallet)) return false;
        let reg = borrow(wallet);
        if (who == reg.main_owner) return true;
        if (!reg.entries.contains(who)) return false;
        let inner: &KeyedBigVector = &reg.entries.borrow(who).by_service;
        inner.contains(type_name::with_defining_ids<ServiceT>())
    }

    /// Per-coin universal remaining. Same `UNLIMITED` / wildcard / 0 semantics as service variant.
    public fun coin_allowance<CoinT>(wallet: &Wallet, who: address): u64 {
        if (!is_initialized(wallet)) return 0;
        let reg = borrow(wallet);
        if (who == reg.main_owner) return UNLIMITED;
        if (!reg.entries.contains(who)) return 0;
        let inner: &KeyedBigVector = &reg.entries.borrow(who).by_coin;
        let key = type_name::with_defining_ids<CoinT>();
        if (inner.contains(key)) {
            let v: &u64 = &inner[key];
            return *v
        };
        let any_key = type_name::with_defining_ids<AnyCoin>();
        if (inner.contains(any_key)) {
            let v: &u64 = &inner[any_key];
            *v
        } else {
            0
        }
    }

    /// Number of services a delegate has an allowance for. Aborts if not a delegate.
    public fun service_count(wallet: &Wallet, delegate: address): u64 {
        let reg = borrow(wallet);
        assert!(reg.entries.contains(delegate), ENotFound);
        reg.entries.borrow(delegate).by_service.length()
    }

    /// Number of coins a delegate has an allowance for. Aborts if not a delegate.
    public fun coin_count(wallet: &Wallet, delegate: address): u64 {
        let reg = borrow(wallet);
        assert!(reg.entries.contains(delegate), ENotFound);
        reg.entries.borrow(delegate).by_coin.length()
    }

    public fun any_coin_allowance(wallet: &Wallet, who: address): u64 {
        coin_allowance<AnyCoin>(wallet, who)
    }

    public fun unlimited_allowance(): u64 {
        UNLIMITED
    }

    /// ===== internal helpers =====

    /// Debit per-service budget. `public(package)` so `intent` can call it directly.
    public(package) fun debit_service_allowance<ServiceT>(wallet: &mut Wallet, spender: address, amount: u64) {
        let wallet_id = wallet::id(wallet);
        let key = type_name::with_defining_ids<ServiceT>();
        let reg = borrow_mut(wallet);

        if (spender == reg.main_owner) {
            event::emit(ServiceAllowanceDebited { wallet_id, spender, service: key, amount, remaining: UNLIMITED });
            return
        };

        assert!(reg.entries.contains(spender), ENotDelegate);
        let inner: &mut KeyedBigVector = &mut reg.entries.borrow_mut(spender).by_service;
        assert!(inner.contains(key), EServiceNotSet);
        let v: &mut u64 = &mut inner[key];
        if (*v == UNLIMITED) {
            event::emit(ServiceAllowanceDebited { wallet_id, spender, service: key, amount, remaining: UNLIMITED });
            return
        };
        assert!(*v >= amount, EInsufficientServiceAllowance);
        *v = *v - amount;
        let remaining = *v;
        event::emit(ServiceAllowanceDebited { wallet_id, spender, service: key, amount, remaining });
    }

    /// Debit per-coin universal budget. Same caller semantics as service variant.
    public(package) fun debit_coin_allowance<CoinT>(wallet: &mut Wallet, spender: address, amount: u64) {
        let wallet_id = wallet::id(wallet);
        let key = type_name::with_defining_ids<CoinT>();
        let reg = borrow_mut(wallet);

        if (spender == reg.main_owner) {
            event::emit(CoinAllowanceDebited { wallet_id, spender, coin: key, amount, remaining: UNLIMITED });
            return
        };

        assert!(reg.entries.contains(spender), ENotDelegate);
        let inner: &mut KeyedBigVector = &mut reg.entries.borrow_mut(spender).by_coin;
        let debit_key = if (inner.contains(key)) {
            key
        } else {
            let any_key = type_name::with_defining_ids<AnyCoin>();
            assert!(inner.contains(any_key), ECoinNotSet);
            any_key
        };
        let v: &mut u64 = &mut inner[debit_key];
        if (*v == UNLIMITED) {
            event::emit(CoinAllowanceDebited { wallet_id, spender, coin: debit_key, amount, remaining: UNLIMITED });
            return
        };
        assert!(*v >= amount, EInsufficientCoinAllowance);
        *v = *v - amount;
        let remaining = *v;
        event::emit(CoinAllowanceDebited { wallet_id, spender, coin: debit_key, amount, remaining });
    }

    fun borrow(wallet: &Wallet): &Delegate {
        let uid: &UID = wallet::uid(wallet);
        assert!(df::exists(uid, REGISTRY_DF_KEY), ENotInitialized);
        df::borrow<vector<u8>, Delegate>(uid, REGISTRY_DF_KEY)
    }

    fun borrow_mut(wallet: &mut Wallet): &mut Delegate {
        let uid_mut: &mut UID = wallet::uid_mut(wallet);
        assert!(df::exists(uid_mut, REGISTRY_DF_KEY), ENotInitialized);
        df::borrow_mut<vector<u8>, Delegate>(uid_mut, REGISTRY_DF_KEY)
    }

    fun borrow_service_mut(wallet: &mut Wallet, delegate: address): &mut KeyedBigVector {
        let reg = borrow_mut(wallet);
        assert!(delegate != reg.main_owner, EMainOwnerNoAllowance);
        assert!(reg.entries.contains(delegate), ENotFound);
        &mut reg.entries.borrow_mut(delegate).by_service
    }

    fun borrow_coin_mut(wallet: &mut Wallet, delegate: address): &mut KeyedBigVector {
        let reg = borrow_mut(wallet);
        assert!(delegate != reg.main_owner, EMainOwnerNoAllowance);
        assert!(reg.entries.contains(delegate), ENotFound);
        &mut reg.entries.borrow_mut(delegate).by_coin
    }
}

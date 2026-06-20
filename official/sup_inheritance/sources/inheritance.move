module SupInheritance::inheritance {
    use std::{
        hash,
        string::String,
        type_name::{Self, TypeName},
    };
    use sui::{
        dynamic_field as df,
        vec_map::{Self, VecMap},
        clock::Clock,
        table::{Self, Table},
        event,
    };
    use SupWallet::wallet::{Self, Wallet};
    use SupWallet::intent;

    const ENotYourWallet: u64 = 0;
    const ENotYourInheritance: u64 = 1;
    const ECapNotFound: u64 = 2;
    const ETotalPercentageExceedsHundred: u64 = 3;
    const ELocked: u64 = 4;
    const EAlreadyWithdrawn: u64 = 5;
    const EMemberDeactivated: u64 = 6;
    const ELengthMismatch: u64 = 7;
    const ETotalPercentageNotHundred: u64 = 9;
    const ETooManyMembers: u64 = 10;
    const ENotOwner: u64 = 11;
    const ELockedDuringGrace: u64 = 12;
    const ENoActivePercentage: u64 = 13;
    const ERemainingPercentageExceeded: u64 = 14;
    const EHashlockAlreadyClaimed: u64 = 15;
    const EInvalidHashPreimage: u64 = 16;
    const EInvalidHashLength: u64 = 17;

    const DAY_MS: u64 = 24 * 60 * 60 * 1000;
    const LIVENESS_WINDOW: u64 = 180 * DAY_MS;
    const GRACE_PERIOD: u64 = 7 * DAY_MS;

    /// Inheritance plan attached (by walletID) to a Wallet. Shared so beneficiaries can interact.
    /// `owner` is captured from `wallet::owner(wallet)` at creation — self-contained, won't drift
    /// if the wallet ever gains a transfer-ownership flow.
    public struct Inheritance has key {
        id: UID,
        walletID: ID,
        owner: address,
        last_update: u64,
        time_left: u64,
        is_warned: bool,
        cap_percentage: VecMap<u8, u8>,
        cap_activated: VecMap<u8, bool>,
        /// Monotonic counter so a `capID` is never reused after `remove_member`.
        next_cap_id: u8,
        total_percentage: u16,
        /// Legacy pre-dynamic-field withdrawn list. Kept for object layout
        /// compatibility and checked on payout, but new withdrawals are
        /// recorded as `WithdrawnKey` dynamic fields.
        asset_withdrawn: Table<TypeName, vector<u8>>,
    }

    public struct InheritanceService has drop {}

    public struct MemberCap has key, store {
        id: UID,
        walletID: ID,
        inheritanceID: ID,
        capID: u8,
    }

    public struct HashlockInvite has key {
        id: UID,
        walletID: ID,
        inheritanceID: ID,
        capID: u8,
        label_hash: vector<u8>,
        preimage_hash: vector<u8>,
        member_cap: Option<MemberCap>,
    }

    public struct RemainingPercentageKey has copy, drop, store {
        coin: TypeName,
    }

    public struct WithdrawnKey has copy, drop, store {
        coin: TypeName,
        cap_id: u8,
    }

    /// ===== events =====

    public struct InheritanceCreated has copy, drop {
        inheritance_id: ID,
        wallet_id: ID,
        owner: address,
        created_at_ms: u64,
    }

    public struct MemberAdded has copy, drop {
        inheritance_id: ID,
        cap_id: u8,
        member: address,
        percentage: u8,
    }

    public struct MemberRemoved has copy, drop {
        inheritance_id: ID,
        cap_id: u8,
    }

    public struct MemberCapModified has copy, drop {
        inheritance_id: ID,
        cap_id: u8,
        percentage: u8,
        activated: bool,
    }

    public struct TimeUpdated has copy, drop {
        inheritance_id: ID,
        last_update_ms: u64,
        is_warned: bool,
    }

    public struct GraceStarted has copy, drop {
        inheritance_id: ID,
        started_at_ms: u64,
        grace_period_ms: u64,
        triggered_by_cap_id: u8,
    }

    public struct MemberWithdrew has copy, drop {
        inheritance_id: ID,
        cap_id: u8,
        coin: TypeName,
        amount: u64,
    }

    public struct ZkSendInviteCreated has copy, drop {
        inheritance_id: ID,
        wallet_id: ID,
        cap_id: u8,
        label_hash: vector<u8>,
        percentage: u8,
    }

    public struct HashlockInviteCreated has copy, drop {
        invite_id: ID,
        inheritance_id: ID,
        wallet_id: ID,
        cap_id: u8,
        label_hash: vector<u8>,
        preimage_hash: vector<u8>,
        percentage: u8,
    }

    public struct HashlockInviteClaimed has copy, drop {
        invite_id: ID,
        inheritance_id: ID,
        cap_id: u8,
        recipient: address,
    }

    /// create an inheritance plan bound to an existing wallet. Owner gate: `ctx.sender()`
    /// must equal `wallet::owner(wallet)`. The owner address is then frozen into this
    /// Inheritance plan.
    public fun create_inheritance(wallet: &Wallet, clock: &Clock, ctx: &mut TxContext) {
        let wallet_id = wallet::id(wallet);
        let owner = wallet::owner(wallet);
        assert!(ctx.sender() == owner, ENotYourWallet);

        let now = clock.timestamp_ms();
        let inheritance = Inheritance {
            id: object::new(ctx),
            walletID: wallet_id,
            owner,
            last_update: now,
            time_left: LIVENESS_WINDOW,
            is_warned: false,
            cap_percentage: vec_map::empty<u8, u8>(),
            cap_activated: vec_map::empty<u8, bool>(),
            next_cap_id: 0,
            total_percentage: 0,
            asset_withdrawn: table::new<TypeName, vector<u8>>(ctx),
        };
        let inheritance_id = object::id(&inheritance);
        transfer::share_object(inheritance);

        event::emit(InheritanceCreated {
            inheritance_id,
            wallet_id,
            owner,
            created_at_ms: now,
        });
    }

    /// add multiple members by addresses vector. Maintains `total_percentage <= 100`.
    public fun add_member_by_addresses(
        inheritance: &mut Inheritance,
        address_list: vector<address>,
        percentage_list: vector<u8>,
        ctx: &mut TxContext,
    ) {
        assert_owner(inheritance, ctx);
        assert_mutable(inheritance);
        assert!(address_list.length() == percentage_list.length(), ELengthMismatch);
        let inheritance_id = object::id(inheritance);
        let mut i = 0;
        while (i < address_list.length()) {
            let percentage = percentage_list[i];
            let (cap_id, member_cap) = register_member(inheritance, inheritance_id, percentage, ctx);
            transfer::public_transfer(member_cap, address_list[i]);

            event::emit(MemberAdded {
                inheritance_id,
                cap_id,
                member: address_list[i],
                percentage,
            });

            i = i + 1;
        };
    }

    /// add single member by an email string (caller decides where to send the cap).
    public fun add_member_by_email(
        inheritance: &mut Inheritance,
        _email: String,
        percentage: u8,
        ctx: &mut TxContext,
    ): MemberCap {
        assert_owner(inheritance, ctx);
        assert_mutable(inheritance);

        let inheritance_id = object::id(inheritance);
        let (cap_id, member_cap) = register_member(inheritance, inheritance_id, percentage, ctx);

        event::emit(MemberAdded {
            inheritance_id,
            cap_id,
            member: @0x0,
            percentage,
        });
        member_cap
    }

    /// Create a transferable MemberCap intended to be wrapped into a zkSend
    /// link by the caller's PTB. `label_hash` is only metadata for the UI and
    /// should be a hash of email/label text, never plaintext PII.
    public fun add_member_for_zksend(
        inheritance: &mut Inheritance,
        label_hash: vector<u8>,
        percentage: u8,
        ctx: &mut TxContext,
    ): MemberCap {
        assert_owner(inheritance, ctx);
        assert_mutable(inheritance);

        let inheritance_id = object::id(inheritance);
        let (cap_id, member_cap) = register_member(inheritance, inheritance_id, percentage, ctx);

        event::emit(MemberAdded {
            inheritance_id,
            cap_id,
            member: @0x0,
            percentage,
        });
        event::emit(ZkSendInviteCreated {
            inheritance_id,
            wallet_id: inheritance.walletID,
            cap_id,
            label_hash,
            percentage,
        });
        member_cap
    }

    /// Create a shared invite that escrows a MemberCap until a claimant reveals
    /// a preimage whose `sha2_256(preimage)` equals `preimage_hash`.
    public fun add_member_by_hashlock(
        inheritance: &mut Inheritance,
        label_hash: vector<u8>,
        preimage_hash: vector<u8>,
        percentage: u8,
        ctx: &mut TxContext,
    ) {
        assert_owner(inheritance, ctx);
        assert_mutable(inheritance);
        assert_hash_32(&preimage_hash);

        let inheritance_id = object::id(inheritance);
        let (cap_id, member_cap) = register_member(inheritance, inheritance_id, percentage, ctx);
        let invite = HashlockInvite {
            id: object::new(ctx),
            walletID: inheritance.walletID,
            inheritanceID: inheritance_id,
            capID: cap_id,
            label_hash,
            preimage_hash,
            member_cap: option::some(member_cap),
        };
        let invite_id = object::id(&invite);
        transfer::share_object(invite);

        event::emit(MemberAdded {
            inheritance_id,
            cap_id,
            member: @0x0,
            percentage,
        });
        event::emit(HashlockInviteCreated {
            invite_id,
            inheritance_id,
            wallet_id: inheritance.walletID,
            cap_id,
            label_hash,
            preimage_hash,
            percentage,
        });
    }

    /// Claim a hashlock invite by revealing the preimage. The MemberCap remains
    /// transferable after claim, matching the existing cap semantics.
    #[allow(lint(self_transfer))]
    public fun claim_hashlock_member(
        invite: &mut HashlockInvite,
        preimage: vector<u8>,
        ctx: &mut TxContext,
    ) {
        assert!(option::is_some(&invite.member_cap), EHashlockAlreadyClaimed);
        assert!(hash::sha2_256(preimage) == invite.preimage_hash, EInvalidHashPreimage);

        let member_cap = option::extract(&mut invite.member_cap);
        let recipient = ctx.sender();
        transfer::public_transfer(member_cap, recipient);

        event::emit(HashlockInviteClaimed {
            invite_id: object::id(invite),
            inheritance_id: invite.inheritanceID,
            cap_id: invite.capID,
            recipient,
        });
    }

    /// modify percentage and activated status of a cap. Re-checks the invariant.
    public fun modify_member_cap(
        inheritance: &mut Inheritance,
        capID: u8,
        percentage: u8,
        activated: bool,
        ctx: &TxContext,
    ) {
        assert_owner(inheritance, ctx);
        assert_mutable(inheritance);
        assert!(vec_map::contains(&inheritance.cap_percentage, &capID), ECapNotFound);

        let old_percentage = *vec_map::get(&inheritance.cap_percentage, &capID);
        let old_activated = *vec_map::get(&inheritance.cap_activated, &capID);
        if (old_activated) {
            inheritance.total_percentage = inheritance.total_percentage - (old_percentage as u16);
        };
        if (activated) {
            inheritance.total_percentage = inheritance.total_percentage + (percentage as u16);
        };
        assert!(inheritance.total_percentage <= 100, ETotalPercentageExceedsHundred);

        let percentage_mut = vec_map::get_mut(&mut inheritance.cap_percentage, &capID);
        *percentage_mut = percentage;
        let activated_mut = vec_map::get_mut(&mut inheritance.cap_activated, &capID);
        *activated_mut = activated;

        event::emit(MemberCapModified {
            inheritance_id: object::id(inheritance),
            cap_id: capID,
            percentage,
            activated,
        });
    }

    /// Remove a member entirely from the inheritance plan. Their `MemberCap` object
    /// on-chain becomes useless (`member_withdraw` will abort with `ECapNotFound`).
    public fun remove_member(inheritance: &mut Inheritance, capID: u8, ctx: &TxContext) {
        assert_owner(inheritance, ctx);
        assert_mutable(inheritance);
        assert!(vec_map::contains(&inheritance.cap_percentage, &capID), ECapNotFound);

        let (_, old_percentage) = vec_map::remove(&mut inheritance.cap_percentage, &capID);
        let (_, old_activated) = vec_map::remove(&mut inheritance.cap_activated, &capID);
        if (old_activated) {
            inheritance.total_percentage = inheritance.total_percentage - (old_percentage as u16);
        };

        event::emit(MemberRemoved {
            inheritance_id: object::id(inheritance),
            cap_id: capID,
        });
    }

    /// owner heartbeat — proves liveness and exits any active grace period.
    public fun update_time(inheritance: &mut Inheritance, clock: &Clock, ctx: &TxContext) {
        assert_owner(inheritance, ctx);
        inheritance.last_update = clock.timestamp_ms();
        if (inheritance.is_warned) {
            inheritance.time_left = LIVENESS_WINDOW;
            inheritance.is_warned = false;
        };
        event::emit(TimeUpdated {
            inheritance_id: object::id(inheritance),
            last_update_ms: inheritance.last_update,
            is_warned: inheritance.is_warned,
        });
    }

    /// Member withdraws their share — Mode C intent flow (no allowance debit; MemberCap +
    /// time-gate is the sole authorisation; the owner already vouched for
    /// `InheritanceService` via `grant_service_coin<InheritanceService, CoinType>`).
    /// Two-phase: first call after `last_update + time_left` starts the grace period
    /// (no coin), second call after grace expires actually pays out.
    #[allow(lint(self_transfer))]
    public fun member_withdraw<CoinType>(
        cap: &MemberCap,
        inheritance: &mut Inheritance,
        wallet: &mut Wallet,
        root: &sui::accumulator::AccumulatorRoot,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert_valid_member_cap(cap, inheritance, wallet::id(wallet));
        assert_total_percentage_complete(inheritance);

        let current_time = clock.timestamp_ms();
        assert!(current_time - inheritance.last_update >= inheritance.time_left, ELocked);

        // Phase 1: first member to trigger after liveness lapses starts the grace period.
        if (!inheritance.is_warned) {
            return start_grace_period(inheritance, clock, cap.capID)
        };

        // Phase 2: inheritance has triggered. Withdrawn membership is tracked
        // per (coin, cap), and remaining percentage is snapped per coin.
        let coin_key = type_name::with_defining_ids<CoinType>();
        let full_amount = wallet::balance<CoinType>(wallet, root);
        let amount = withdraw_amount_for_cap(inheritance, coin_key, cap.capID, full_amount);
        let recipient = ctx.sender();

        let sig = intent::request_payment_unmetered<InheritanceService, CoinType>(
            InheritanceService {},
            amount,
            recipient,
        );
        let (coin, wallet_witness) = intent::validate_and_pay_unmetered<InheritanceService, CoinType>(
            wallet,
            sig,
            ctx,
        );
        transfer::public_transfer(coin, recipient);

        let receipt_sig = intent::create_receipt_sig<InheritanceService, CoinType>(
            InheritanceService {},
            amount,
            recipient,
        );
        intent::verify_and_clear(wallet_witness, receipt_sig);

        event::emit(MemberWithdrew {
            inheritance_id: object::id(inheritance),
            cap_id: cap.capID,
            coin: coin_key,
            amount,
        });
    }

    /// Called when a member first triggers withdrawal after the liveness window lapses.
    /// Sets `is_warned`, resets the timer to `GRACE_PERIOD`, and emits an event so
    /// off-chain watchers (and the owner) can react.
    fun start_grace_period(inheritance: &mut Inheritance, clock: &Clock, triggered_by_cap_id: u8) {
        let now = clock.timestamp_ms();
        inheritance.last_update = now;
        inheritance.time_left = GRACE_PERIOD;
        inheritance.is_warned = true;

        event::emit(GraceStarted {
            inheritance_id: object::id(inheritance),
            started_at_ms: now,
            grace_period_ms: GRACE_PERIOD,
            triggered_by_cap_id,
        });
    }

    /// ===== helpers =====

    fun assert_owner(inheritance: &Inheritance, ctx: &TxContext) {
        assert!(ctx.sender() == inheritance.owner, ENotOwner);
    }

    fun assert_mutable(inheritance: &Inheritance) {
        assert!(!inheritance.is_warned, ELockedDuringGrace);
    }

    fun assert_hash_32(hash_value: &vector<u8>) {
        assert!(hash_value.length() == 32, EInvalidHashLength);
    }

    fun register_member(
        inheritance: &mut Inheritance,
        inheritance_id: ID,
        percentage: u8,
        ctx: &mut TxContext,
    ): (u8, MemberCap) {
        inheritance.total_percentage = inheritance.total_percentage + (percentage as u16);
        assert!(inheritance.total_percentage <= 100, ETotalPercentageExceedsHundred);
        assert!(inheritance.next_cap_id < 255, ETooManyMembers);

        let cap_id = inheritance.next_cap_id;
        let member_cap = MemberCap {
            id: object::new(ctx),
            walletID: inheritance.walletID,
            inheritanceID: inheritance_id,
            capID: cap_id,
        };
        inheritance.cap_percentage.insert(cap_id, percentage);
        inheritance.cap_activated.insert(cap_id, true);
        inheritance.next_cap_id = cap_id + 1;
        (cap_id, member_cap)
    }

    fun assert_valid_member_cap(cap: &MemberCap, inheritance: &Inheritance, wallet_id: ID) {
        assert!(cap.walletID == wallet_id, ENotYourWallet);
        assert!(cap.inheritanceID == object::id(inheritance), ENotYourInheritance);
        assert!(inheritance.walletID == wallet_id, ENotYourWallet);
        assert!(vec_map::contains(&inheritance.cap_percentage, &cap.capID), ECapNotFound);
        assert!(*vec_map::get(&inheritance.cap_activated, &cap.capID), EMemberDeactivated);
    }

    fun assert_total_percentage_complete(inheritance: &Inheritance) {
        assert!(inheritance.total_percentage == 100, ETotalPercentageNotHundred);
    }

    fun withdraw_amount_for_cap(
        inheritance: &mut Inheritance,
        coin_key: TypeName,
        cap_id: u8,
        full_amount: u64,
    ): u64 {
        mark_withdrawn(inheritance, coin_key, cap_id);
        let percentage = *vec_map::get(&inheritance.cap_percentage, &cap_id) as u64;
        withdraw_amount_by_remaining_percentage(inheritance, coin_key, full_amount, percentage)
    }

    fun mark_withdrawn(inheritance: &mut Inheritance, coin_key: TypeName, cap_id: u8) {
        let key = WithdrawnKey { coin: coin_key, cap_id };
        assert!(!df::exists(&inheritance.id, key), EAlreadyWithdrawn);
        if (table::contains(&inheritance.asset_withdrawn, coin_key)) {
            let legacy_withdrawn_list = table::borrow(&inheritance.asset_withdrawn, coin_key);
            assert!(!vector::contains(legacy_withdrawn_list, &cap_id), EAlreadyWithdrawn);
        };
        df::add(&mut inheritance.id, key, true);
    }

    fun withdraw_amount_by_remaining_percentage(
        inheritance: &mut Inheritance,
        coin_key: TypeName,
        full_amount: u64,
        percentage: u64,
    ): u64 {
        if (percentage == 0) {
            return 0
        };

        let key = RemainingPercentageKey { coin: coin_key };
        if (!df::exists(&inheritance.id, key)) {
            df::add(&mut inheritance.id, key, inheritance.total_percentage);
        };

        let remaining = df::borrow_mut<RemainingPercentageKey, u16>(&mut inheritance.id, key);
        let percentage_u16 = percentage as u16;
        assert!(*remaining > 0, ENoActivePercentage);
        assert!(*remaining >= percentage_u16, ERemainingPercentageExceeded);

        let amount = if (*remaining == percentage_u16) {
            full_amount
        } else {
            full_amount * percentage / (*remaining as u64)
        };
        *remaining = *remaining - percentage_u16;
        amount
    }

    #[test_only]
    public fun force_warned_for_testing(inheritance: &mut Inheritance) {
        inheritance.is_warned = true;
    }

    #[test_only]
    public fun payout_amount_for_testing<CoinType>(
        cap: &MemberCap,
        inheritance: &mut Inheritance,
        wallet: &Wallet,
        full_amount: u64,
    ): u64 {
        assert_valid_member_cap(cap, inheritance, wallet::id(wallet));
        assert_total_percentage_complete(inheritance);
        withdraw_amount_for_cap(
            inheritance,
            type_name::with_defining_ids<CoinType>(),
            cap.capID,
            full_amount,
        )
    }
}

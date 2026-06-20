module SupInheritance::inheritance_tests;

use std::{hash, unit_test::assert_eq};
use SupInheritance::inheritance::{Self, HashlockInvite, Inheritance, MemberCap};
use SupWallet::wallet::{Self, Wallet};
use sui::{
    clock::{Self},
    sui::SUI,
    test_scenario::{Self as ts},
};

const ALICE: address = @0xA;
const BOB: address = @0xB;
const CHARLIE: address = @0xC;

#[test, expected_failure(abort_code = SupInheritance::inheritance::ETotalPercentageExceedsHundred)]
fun inheritance_percentage_overflow_blocked() {
    let mut scenario = ts::begin(ALICE);
    let clock = clock::create_for_testing(scenario.ctx());

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let w: Wallet = scenario.take_shared();
        inheritance::create_inheritance(&w, &clock, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(ALICE);
    {
        let mut inheritance_plan: Inheritance = scenario.take_shared();

        let mut addrs = vector[];
        let mut pcts = vector[];
        vector::push_back(&mut addrs, BOB);
        vector::push_back(&mut pcts, 60);
        vector::push_back(&mut addrs, CHARLIE);
        vector::push_back(&mut pcts, 60);

        inheritance::add_member_by_addresses(&mut inheritance_plan, addrs, pcts, scenario.ctx());
        ts::return_shared(inheritance_plan);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = SupInheritance::inheritance::ELengthMismatch)]
fun inheritance_add_member_length_mismatch() {
    let mut scenario = ts::begin(ALICE);
    let clock = clock::create_for_testing(scenario.ctx());

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let w: Wallet = scenario.take_shared();
        inheritance::create_inheritance(&w, &clock, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(ALICE);
    {
        let mut inheritance_plan: Inheritance = scenario.take_shared();

        let mut addrs = vector[];
        let mut pcts = vector[];
        vector::push_back(&mut addrs, BOB);
        vector::push_back(&mut addrs, CHARLIE);
        vector::push_back(&mut pcts, 50);

        inheritance::add_member_by_addresses(&mut inheritance_plan, addrs, pcts, scenario.ctx());
        ts::return_shared(inheritance_plan);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = SupInheritance::inheritance::ELockedDuringGrace)]
fun inheritance_modify_member_during_grace_blocked() {
    let mut scenario = ts::begin(ALICE);
    let clock = clock::create_for_testing(scenario.ctx());

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let w: Wallet = scenario.take_shared();
        inheritance::create_inheritance(&w, &clock, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(ALICE);
    {
        let mut inheritance_plan: Inheritance = scenario.take_shared();

        let mut addrs = vector[];
        let mut pcts = vector[];
        vector::push_back(&mut addrs, BOB);
        vector::push_back(&mut pcts, 100);
        inheritance::add_member_by_addresses(&mut inheritance_plan, addrs, pcts, scenario.ctx());

        inheritance::force_warned_for_testing(&mut inheritance_plan);
        inheritance::modify_member_cap(&mut inheritance_plan, 0, 50, true, scenario.ctx());
        ts::return_shared(inheritance_plan);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun inheritance_remove_member_no_cap_collision() {
    let mut scenario = ts::begin(ALICE);
    let clock = clock::create_for_testing(scenario.ctx());

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let w: Wallet = scenario.take_shared();
        inheritance::create_inheritance(&w, &clock, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(ALICE);
    {
        let mut inheritance_plan: Inheritance = scenario.take_shared();

        let mut addrs = vector[];
        let mut pcts = vector[];
        vector::push_back(&mut addrs, BOB);
        vector::push_back(&mut pcts, 50);
        vector::push_back(&mut addrs, CHARLIE);
        vector::push_back(&mut pcts, 50);
        inheritance::add_member_by_addresses(&mut inheritance_plan, addrs, pcts, scenario.ctx());

        inheritance::remove_member(&mut inheritance_plan, 0, scenario.ctx());

        let mut addrs2 = vector[];
        let mut pcts2 = vector[];
        vector::push_back(&mut addrs2, BOB);
        vector::push_back(&mut pcts2, 50);
        inheritance::add_member_by_addresses(&mut inheritance_plan, addrs2, pcts2, scenario.ctx());

        ts::return_shared(inheritance_plan);
    };

    scenario.next_tx(BOB);
    {
        let member_cap: MemberCap = scenario.take_from_sender();
        ts::return_to_sender(&scenario, member_cap);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun inheritance_payout_accounting_distributes_full_balance() {
    let mut scenario = ts::begin(ALICE);
    let clock = clock::create_for_testing(scenario.ctx());

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let w: Wallet = scenario.take_shared();
        inheritance::create_inheritance(&w, &clock, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(ALICE);
    {
        let mut inheritance_plan: Inheritance = scenario.take_shared();
        let mut addrs = vector[];
        let mut pcts = vector[];
        vector::push_back(&mut addrs, BOB);
        vector::push_back(&mut pcts, 20);
        vector::push_back(&mut addrs, CHARLIE);
        vector::push_back(&mut pcts, 80);
        inheritance::add_member_by_addresses(&mut inheritance_plan, addrs, pcts, scenario.ctx());
        ts::return_shared(inheritance_plan);
    };

    scenario.next_tx(BOB);
    {
        let member_cap: MemberCap = scenario.take_from_sender();
        let mut inheritance_plan: Inheritance = scenario.take_shared();
        let w: Wallet = scenario.take_shared();

        let amount = inheritance::payout_amount_for_testing<SUI>(&member_cap, &mut inheritance_plan, &w, 1000);
        assert_eq!(amount, 200);

        transfer::public_transfer(member_cap, ALICE);
        ts::return_shared(inheritance_plan);
        ts::return_shared(w);
    };

    scenario.next_tx(CHARLIE);
    {
        let member_cap: MemberCap = scenario.take_from_sender();
        let mut inheritance_plan: Inheritance = scenario.take_shared();
        let w: Wallet = scenario.take_shared();

        let amount = inheritance::payout_amount_for_testing<SUI>(&member_cap, &mut inheritance_plan, &w, 800);
        assert_eq!(amount, 800);

        ts::return_to_sender(&scenario, member_cap);
        ts::return_shared(inheritance_plan);
        ts::return_shared(w);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = SupInheritance::inheritance::ETotalPercentageNotHundred)]
fun inheritance_partial_percentage_blocked_at_payout() {
    let mut scenario = ts::begin(ALICE);
    let clock = clock::create_for_testing(scenario.ctx());

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let w: Wallet = scenario.take_shared();
        inheritance::create_inheritance(&w, &clock, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(ALICE);
    {
        let mut inheritance_plan: Inheritance = scenario.take_shared();
        let mut addrs = vector[];
        let mut pcts = vector[];
        vector::push_back(&mut addrs, BOB);
        vector::push_back(&mut pcts, 60);
        inheritance::add_member_by_addresses(&mut inheritance_plan, addrs, pcts, scenario.ctx());
        ts::return_shared(inheritance_plan);
    };

    scenario.next_tx(BOB);
    {
        let member_cap: MemberCap = scenario.take_from_sender();
        let mut inheritance_plan: Inheritance = scenario.take_shared();
        let w: Wallet = scenario.take_shared();
        inheritance::payout_amount_for_testing<SUI>(&member_cap, &mut inheritance_plan, &w, 1000);
        ts::return_to_sender(&scenario, member_cap);
        ts::return_shared(inheritance_plan);
        ts::return_shared(w);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = SupInheritance::inheritance::EAlreadyWithdrawn)]
fun inheritance_same_cap_same_coin_cannot_withdraw_twice() {
    let mut scenario = ts::begin(ALICE);
    let clock = clock::create_for_testing(scenario.ctx());

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let w: Wallet = scenario.take_shared();
        inheritance::create_inheritance(&w, &clock, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(ALICE);
    {
        let mut inheritance_plan: Inheritance = scenario.take_shared();
        let mut addrs = vector[];
        let mut pcts = vector[];
        vector::push_back(&mut addrs, BOB);
        vector::push_back(&mut pcts, 100);
        inheritance::add_member_by_addresses(&mut inheritance_plan, addrs, pcts, scenario.ctx());
        ts::return_shared(inheritance_plan);
    };

    scenario.next_tx(BOB);
    {
        let member_cap: MemberCap = scenario.take_from_sender();
        let mut inheritance_plan: Inheritance = scenario.take_shared();
        let w: Wallet = scenario.take_shared();

        let amount = inheritance::payout_amount_for_testing<SUI>(&member_cap, &mut inheritance_plan, &w, 1000);
        assert_eq!(amount, 1000);
        inheritance::payout_amount_for_testing<SUI>(&member_cap, &mut inheritance_plan, &w, 0);
        ts::return_to_sender(&scenario, member_cap);
        ts::return_shared(inheritance_plan);
        ts::return_shared(w);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun inheritance_zksend_invite_returns_usable_member_cap() {
    let mut scenario = ts::begin(ALICE);
    let clock = clock::create_for_testing(scenario.ctx());

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let w: Wallet = scenario.take_shared();
        inheritance::create_inheritance(&w, &clock, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(ALICE);
    {
        let mut inheritance_plan: Inheritance = scenario.take_shared();
        let w: Wallet = scenario.take_shared();
        let member_cap = inheritance::add_member_for_zksend(
            &mut inheritance_plan,
            hash::sha2_256(b"bob@example.com"),
            100,
            scenario.ctx(),
        );

        let amount = inheritance::payout_amount_for_testing<SUI>(&member_cap, &mut inheritance_plan, &w, 1000);
        assert_eq!(amount, 1000);

        transfer::public_transfer(member_cap, ALICE);
        ts::return_shared(inheritance_plan);
        ts::return_shared(w);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun inheritance_hashlock_claim_transfers_usable_member_cap() {
    let mut scenario = ts::begin(ALICE);
    let clock = clock::create_for_testing(scenario.ctx());

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let w: Wallet = scenario.take_shared();
        inheritance::create_inheritance(&w, &clock, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(ALICE);
    {
        let mut inheritance_plan: Inheritance = scenario.take_shared();
        inheritance::add_member_by_hashlock(
            &mut inheritance_plan,
            hash::sha2_256(b"bob@example.com"),
            hash::sha2_256(b"secret"),
            100,
            scenario.ctx(),
        );
        ts::return_shared(inheritance_plan);
    };

    scenario.next_tx(BOB);
    {
        let mut invite: HashlockInvite = scenario.take_shared();
        inheritance::claim_hashlock_member(&mut invite, b"secret", scenario.ctx());
        ts::return_shared(invite);
    };

    scenario.next_tx(BOB);
    {
        let member_cap: MemberCap = scenario.take_from_sender();
        let mut inheritance_plan: Inheritance = scenario.take_shared();
        let w: Wallet = scenario.take_shared();

        let amount = inheritance::payout_amount_for_testing<SUI>(&member_cap, &mut inheritance_plan, &w, 1000);
        assert_eq!(amount, 1000);

        ts::return_to_sender(&scenario, member_cap);
        ts::return_shared(inheritance_plan);
        ts::return_shared(w);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = SupInheritance::inheritance::EInvalidHashPreimage)]
fun inheritance_hashlock_claim_rejects_wrong_preimage() {
    let mut scenario = ts::begin(ALICE);
    let clock = clock::create_for_testing(scenario.ctx());

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let w: Wallet = scenario.take_shared();
        inheritance::create_inheritance(&w, &clock, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(ALICE);
    {
        let mut inheritance_plan: Inheritance = scenario.take_shared();
        inheritance::add_member_by_hashlock(
            &mut inheritance_plan,
            hash::sha2_256(b"bob@example.com"),
            hash::sha2_256(b"secret"),
            100,
            scenario.ctx(),
        );
        ts::return_shared(inheritance_plan);
    };

    scenario.next_tx(BOB);
    {
        let mut invite: HashlockInvite = scenario.take_shared();
        inheritance::claim_hashlock_member(&mut invite, b"wrong", scenario.ctx());
        ts::return_shared(invite);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

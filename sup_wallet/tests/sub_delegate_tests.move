#[test_only]
module SupWallet::sub_delegate_tests;

use SupWallet::sub_delegate::{Self, ScopedCap, ScopedAuth, ScopedBudget};
use SupWallet::policy::{Self};
use SupWallet::wallet::{Self, Wallet};
use sui::{
    coin::{Self, Coin},
    sui::SUI,
    test_scenario::{Self as ts, Scenario},
};
use usdc::usdc::USDC;

const ALICE: address = @0xA; // owner
const BOB: address = @0xB; // root delegate
const DAVE: address = @0xD; // sub-delegate (child holder)
const EVE: address = @0xE; // grand-child holder
const CAROL: address = @0xC; // recipient

fun test_sui(ts: &mut Scenario, amount: u64): Coin<SUI> {
    coin::mint_for_testing(amount, ts.ctx())
}

fun deposit(w: &Wallet, coin: Coin<SUI>) {
    coin::send_funds(coin, wallet::identity(w));
}

/// Funded wallet whose policy accepts scoped caps (ScopedAuth + ScopedBudget).
fun fresh_scoped_wallet(scenario: &mut Scenario): ID {
    sui::transfer::public_share_object(wallet::create(scenario.ctx()));
    scenario.next_tx(ALICE);
    let id = ts::most_recent_id_shared<Wallet>().destroy_some();
    let mut w = ts::take_shared_by_id<Wallet>(scenario, id);
    deposit(&w, test_sui(scenario, 100));
    policy::initialize(&mut w, scenario.ctx());
    policy::add_auth_rule<ScopedAuth>(&mut w, scenario.ctx());
    policy::add_caveat_rule<ScopedBudget>(&mut w, scenario.ctx());
    ts::return_shared(w);
    id
}

#[test]
fun root_cap_spends_and_debits() {
    let mut scenario = ts::begin(ALICE);
    let wid = fresh_scoped_wallet(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        sub_delegate::mint_root_and_transfer<SUI>(&w, 100, 2, BOB, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let mut w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        let mut cap: ScopedCap = scenario.take_from_address(BOB);
        let mut req = policy::begin_spend<SUI>(&w, 30, CAROL);
        sub_delegate::spend(&mut cap, &mut req);
        policy::confirm_spend<SUI>(&mut w, req, scenario.ctx());
        assert!(sub_delegate::remaining(&cap) == 70, 0);
        ts::return_to_sender(&scenario, cap);
        ts::return_shared(w);
    };

    scenario.next_tx(CAROL);
    {
        let received: Coin<SUI> = scenario.take_from_address(CAROL);
        assert!(coin::value(&received) == 30, 0);
        ts::return_to_sender(&scenario, received);
    };

    ts::end(scenario);
}

#[test]
fun subdelegate_attenuates_and_both_spend() {
    let mut scenario = ts::begin(ALICE);
    let wid = fresh_scoped_wallet(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        sub_delegate::mint_root_and_transfer<SUI>(&w, 100, 2, BOB, scenario.ctx());
        ts::return_shared(w);
    };

    // BOB carves 40 out to DAVE (BOB: 100 -> 60).
    scenario.next_tx(BOB);
    {
        let mut cap: ScopedCap = scenario.take_from_address(BOB);
        sub_delegate::subdelegate_and_transfer(&mut cap, 40, DAVE, scenario.ctx());
        assert!(sub_delegate::remaining(&cap) == 60, 0);
        assert!(sub_delegate::depth(&cap) == 0, 0);
        ts::return_to_sender(&scenario, cap);
    };

    // DAVE spends 25 from the child (child: 40 -> 15).
    scenario.next_tx(DAVE);
    {
        let mut w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        let mut child: ScopedCap = scenario.take_from_address(DAVE);
        assert!(sub_delegate::depth(&child) == 1, 0);
        let mut req = policy::begin_spend<SUI>(&w, 25, CAROL);
        sub_delegate::spend(&mut child, &mut req);
        policy::confirm_spend<SUI>(&mut w, req, scenario.ctx());
        assert!(sub_delegate::remaining(&child) == 15, 0);
        ts::return_to_sender(&scenario, child);
        ts::return_shared(w);
    };

    scenario.next_tx(CAROL);
    {
        let received: Coin<SUI> = scenario.take_from_address(CAROL);
        assert!(coin::value(&received) == 25, 0);
        ts::return_to_sender(&scenario, received);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 4, location = SupWallet::sub_delegate)]
fun subdelegate_cannot_exceed_parent() {
    let mut scenario = ts::begin(ALICE);
    let wid = fresh_scoped_wallet(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        sub_delegate::mint_root_and_transfer<SUI>(&w, 100, 2, BOB, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let mut cap: ScopedCap = scenario.take_from_address(BOB);
        // 150 > 100 remaining -> EInsufficientBudget (4)
        sub_delegate::subdelegate_and_transfer(&mut cap, 150, DAVE, scenario.ctx());
        ts::return_to_sender(&scenario, cap);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 4, location = SupWallet::sub_delegate)]
fun child_overspend_aborts() {
    let mut scenario = ts::begin(ALICE);
    let wid = fresh_scoped_wallet(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        sub_delegate::mint_root_and_transfer<SUI>(&w, 30, 2, BOB, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let mut w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        let mut cap: ScopedCap = scenario.take_from_address(BOB);
        let mut req = policy::begin_spend<SUI>(&w, 50, CAROL);
        sub_delegate::spend(&mut cap, &mut req); // 50 > 30 -> EInsufficientBudget (4)
        policy::confirm_spend<SUI>(&mut w, req, scenario.ctx()); // unreachable
        ts::return_to_sender(&scenario, cap);
        ts::return_shared(w);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 5, location = SupWallet::sub_delegate)]
fun max_depth_enforced() {
    let mut scenario = ts::begin(ALICE);
    let wid = fresh_scoped_wallet(&mut scenario);

    // max_depth = 1: root (0) -> child (1) is allowed; child -> grandchild is not.
    scenario.next_tx(ALICE);
    {
        let w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        sub_delegate::mint_root_and_transfer<SUI>(&w, 100, 1, BOB, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let mut cap: ScopedCap = scenario.take_from_address(BOB);
        sub_delegate::subdelegate_and_transfer(&mut cap, 40, DAVE, scenario.ctx());
        ts::return_to_sender(&scenario, cap);
    };

    scenario.next_tx(DAVE);
    {
        let mut child: ScopedCap = scenario.take_from_address(DAVE);
        // child.depth (1) < max_depth (1) is false -> EMaxDepthExceeded (5)
        sub_delegate::subdelegate_and_transfer(&mut child, 10, EVE, scenario.ctx());
        ts::return_to_sender(&scenario, child);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 2, location = SupWallet::sub_delegate)]
fun revoke_kills_chain() {
    let mut scenario = ts::begin(ALICE);
    let wid = fresh_scoped_wallet(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        sub_delegate::mint_root_and_transfer<SUI>(&w, 100, 2, BOB, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(ALICE);
    {
        let mut w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        policy::revoke_all(&mut w, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let mut w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        let mut cap: ScopedCap = scenario.take_from_address(BOB);
        let mut req = policy::begin_spend<SUI>(&w, 10, CAROL);
        sub_delegate::spend(&mut cap, &mut req); // stale version -> ECapRevoked (2)
        policy::confirm_spend<SUI>(&mut w, req, scenario.ctx()); // unreachable
        ts::return_to_sender(&scenario, cap);
        ts::return_shared(w);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 3, location = SupWallet::sub_delegate)]
fun wrong_coin_aborts() {
    let mut scenario = ts::begin(ALICE);
    let wid = fresh_scoped_wallet(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        sub_delegate::mint_root_and_transfer<SUI>(&w, 100, 2, BOB, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let mut w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        let mut cap: ScopedCap = scenario.take_from_address(BOB);
        let mut req = policy::begin_spend<USDC>(&w, 10, CAROL);
        sub_delegate::spend(&mut cap, &mut req); // cap is SUI-scoped -> EWrongCoin (3)
        policy::confirm_spend<USDC>(&mut w, req, scenario.ctx()); // unreachable
        ts::return_to_sender(&scenario, cap);
        ts::return_shared(w);
    };

    ts::end(scenario);
}

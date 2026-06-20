#[test_only]
module policy_rule_recipient_allowlist::rule_tests;

use policy_rule_recipient_allowlist::rule::{Self, Allowlist};
use SupWallet::wallet::{Self, Wallet};
use SupWallet::policy;
use SupWallet::cap_auth::{Self, DelegateCap, CapAuth};
use sui::{
    coin::{Self, Coin},
    sui::SUI,
    test_scenario::{Self as ts, Scenario},
};

const ALICE: address = @0xA; // owner
const BOB: address = @0xB; // cap-holding delegate
const CAROL: address = @0xC; // allowed recipient
const MALLORY: address = @0xE; // NOT allowed

fun test_sui(ts: &mut Scenario, amount: u64): Coin<SUI> {
    coin::mint_for_testing(amount, ts.ctx())
}

fun deposit(w: &Wallet, coin: Coin<SUI>) {
    coin::send_funds(coin, wallet::identity(w));
}

/// Wallet that accepts a cap principal (CapAuth, from SupWallet) AND this
/// package's third-party RecipientAllowlist caveat. Returns the wallet id.
fun setup(scenario: &mut Scenario): ID {
    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    let id = ts::most_recent_id_shared<Wallet>().destroy_some();
    let mut w = ts::take_shared_by_id<Wallet>(scenario, id);
    deposit(&w, test_sui(scenario, 100));
    policy::initialize(&mut w, scenario.ctx());
    policy::add_auth_rule<CapAuth>(&mut w, scenario.ctx());
    policy::add_caveat_rule<rule::RecipientAllowlist>(&mut w, scenario.ctx());
    cap_auth::mint_and_transfer(&w, BOB, scenario.ctx());
    rule::create_and_share(&w, scenario.ctx());
    ts::return_shared(w);
    id
}

#[test]
fun allowed_recipient_spends() {
    let mut scenario = ts::begin(ALICE);
    let wid = setup(&mut scenario);

    // Owner allows CAROL.
    scenario.next_tx(ALICE);
    {
        let mut list: Allowlist = scenario.take_shared();
        rule::allow(&mut list, CAROL, scenario.ctx());
        ts::return_shared(list);
    };

    // BOB (cap holder) pays CAROL: CapAuth + RecipientAllowlist both stamp.
    scenario.next_tx(BOB);
    {
        let mut w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        let list: Allowlist = scenario.take_shared();
        let cap: DelegateCap = scenario.take_from_address(BOB);
        let mut req = policy::begin_spend<SUI>(&w, 30, CAROL);
        cap_auth::prove(&cap, &mut req);
        rule::enforce(&list, &mut req);
        policy::confirm_spend<SUI>(&mut w, req, scenario.ctx());
        ts::return_to_sender(&scenario, cap);
        ts::return_shared(list);
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
#[expected_failure(abort_code = 1, location = policy_rule_recipient_allowlist::rule)]
fun disallowed_recipient_aborts() {
    let mut scenario = ts::begin(ALICE);
    let wid = setup(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut list: Allowlist = scenario.take_shared();
        rule::allow(&mut list, CAROL, scenario.ctx()); // only CAROL
        ts::return_shared(list);
    };

    // BOB tries to pay MALLORY, who is not on the list -> ENotAllowed (1).
    scenario.next_tx(BOB);
    {
        let mut w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        let list: Allowlist = scenario.take_shared();
        let cap: DelegateCap = scenario.take_from_address(BOB);
        let mut req = policy::begin_spend<SUI>(&w, 30, MALLORY);
        cap_auth::prove(&cap, &mut req);
        rule::enforce(&list, &mut req); // aborts ENotAllowed (1)
        policy::confirm_spend<SUI>(&mut w, req, scenario.ctx()); // unreachable
        ts::return_to_sender(&scenario, cap);
        ts::return_shared(list);
        ts::return_shared(w);
    };

    ts::end(scenario);
}

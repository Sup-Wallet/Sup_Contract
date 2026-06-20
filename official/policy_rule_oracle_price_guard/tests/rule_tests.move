#[test_only]
module policy_rule_oracle_price_guard::rule_tests;

use policy_rule_oracle_price_guard::rule::{Self, PriceGuard, PriceFeed};
use SupWallet::wallet::{Self, Wallet};
use SupWallet::policy;
use SupWallet::cap_auth::{Self, DelegateCap, CapAuth};
use sui::{
    clock::{Self, Clock},
    coin::{Self, Coin},
    sui::SUI,
    test_scenario::{Self as ts, Scenario},
};

const ALICE: address = @0xA; // owner
const BOB: address = @0xB; // cap-holding delegate
const CAROL: address = @0xC; // recipient

fun test_sui(ts: &mut Scenario, amount: u64): Coin<SUI> {
    coin::mint_for_testing(amount, ts.ctx())
}

fun deposit(w: &Wallet, coin: Coin<SUI>) {
    coin::send_funds(coin, wallet::identity(w));
}

/// Wallet that accepts a cap principal (CapAuth) AND this package's
/// OraclePriceGuard caveat, bound to a shared PriceFeed seeded at `seed_price`,
/// with the band [min, max]. Returns (wallet id, feed id).
fun setup(scenario: &mut Scenario, seed_price: u64, min: u64, max: u64): (ID, ID) {
    // Seed a reference price feed (shared) and capture its id.
    scenario.next_tx(ALICE);
    let clock = clock::create_for_testing(scenario.ctx());
    rule::new_feed_and_share(seed_price, &clock, scenario.ctx());
    clock::destroy_for_testing(clock);

    scenario.next_tx(ALICE);
    let feed_id = ts::most_recent_id_shared<PriceFeed>().destroy_some();

    // Create the wallet, fund it, turn on policy + rules, mint a cap, bind guard.
    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    let wid = ts::most_recent_id_shared<Wallet>().destroy_some();
    let mut w = ts::take_shared_by_id<Wallet>(scenario, wid);
    deposit(&w, test_sui(scenario, 100));
    policy::initialize(&mut w, scenario.ctx());
    policy::add_auth_rule<CapAuth>(&mut w, scenario.ctx());
    policy::add_caveat_rule<rule::OraclePriceGuard>(&mut w, scenario.ctx());
    cap_auth::mint_and_transfer(&w, BOB, scenario.ctx());
    rule::create_and_share(&w, feed_id, min, max, scenario.ctx());
    ts::return_shared(w);

    (wid, feed_id)
}

#[test]
fun in_band_price_spends() {
    let mut scenario = ts::begin(ALICE);
    // price 2000 within band [1500, 2500].
    let (wid, _feed_id) = setup(&mut scenario, 2000, 1500, 2500);

    scenario.next_tx(BOB);
    {
        let mut w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        let guard: PriceGuard = scenario.take_shared();
        let feed: PriceFeed = scenario.take_shared();
        let cap: DelegateCap = scenario.take_from_address(BOB);
        let mut req = policy::begin_spend<SUI>(&w, 30, CAROL);
        cap_auth::prove(&cap, &mut req);
        rule::enforce(&guard, &feed, &mut req);
        policy::confirm_spend<SUI>(&mut w, req, scenario.ctx());
        ts::return_to_sender(&scenario, cap);
        ts::return_shared(feed);
        ts::return_shared(guard);
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
#[expected_failure(abort_code = 1, location = policy_rule_oracle_price_guard::rule)]
fun out_of_band_price_aborts() {
    let mut scenario = ts::begin(ALICE);
    // price 3000 is ABOVE band [1500, 2500] -> EOutOfBand (1).
    let (wid, _feed_id) = setup(&mut scenario, 3000, 1500, 2500);

    scenario.next_tx(BOB);
    {
        let mut w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        let guard: PriceGuard = scenario.take_shared();
        let feed: PriceFeed = scenario.take_shared();
        let cap: DelegateCap = scenario.take_from_address(BOB);
        let mut req = policy::begin_spend<SUI>(&w, 30, CAROL);
        cap_auth::prove(&cap, &mut req);
        rule::enforce(&guard, &feed, &mut req); // aborts EOutOfBand (1)
        policy::confirm_spend<SUI>(&mut w, req, scenario.ctx()); // unreachable
        ts::return_to_sender(&scenario, cap);
        ts::return_shared(feed);
        ts::return_shared(guard);
        ts::return_shared(w);
    };

    ts::end(scenario);
}

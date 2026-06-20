#[test_only]
module SupWallet::policy_tests;

use SupWallet::policy::{Self, SpendRequest};
use SupWallet::wallet::{Self, Wallet};
use sui::{
    coin::{Self, Coin},
    sui::SUI,
    test_scenario::{Self as ts, Scenario},
};
use usdc::usdc::USDC;

const ALICE: address = @0xA; // wallet owner
const BOB: address = @0xB; // delegate (the spender / principal)
const CAROL: address = @0xC; // allowed recipient
const MALLORY: address = @0xD; // disallowed recipient

/// ===== example rule witnesses (stand in for separately-deployed rule pkgs) =====
///
/// In production each of these lives in its own package; the mechanic Ã¢â‚¬â€ a module
/// constructing its own witness and stamping the request Ã¢â‚¬â€ is identical whether
/// same-package (here) or cross-package.

/// Auth rule: principal is a specific address. OR-gated.
public struct AddrAuth has drop {}

/// Caveat rule: recipient must equal CAROL. AND-gated.
public struct OnlyCarolRecipient has drop {}

/// Caveat rule: amount must be <= 50. AND-gated. Used to show two caveats AND together.
public struct MaxAmount50 has drop {}

/// ===== example rule entrypoints =====

fun prove_addr_auth(allowed: address, req: &mut SpendRequest, ctx: &TxContext) {
    assert!(ctx.sender() == allowed, 1001);
    policy::add_auth_receipt(AddrAuth {}, req);
}

fun enforce_only_carol(req: &mut SpendRequest) {
    assert!(policy::spend_recipient(req) == CAROL, 1002);
    policy::add_caveat_receipt(OnlyCarolRecipient {}, req);
}

fun enforce_max_50(req: &mut SpendRequest) {
    assert!(policy::spend_amount(req) <= 50, 1003);
    policy::add_caveat_receipt(MaxAmount50 {}, req);
}

/// ===== helpers =====

fun test_sui(ts: &mut Scenario, amount: u64): Coin<SUI> {
    coin::mint_for_testing(amount, ts.ctx())
}

fun deposit<CoinType>(w: &Wallet, coin: Coin<CoinType>) {
    coin::send_funds(coin, wallet::identity(w));
}

/// Owner sets up a wallet with a funded balance and an initialized policy.
fun setup(scenario: &mut Scenario) {
    sui::transfer::public_share_object(wallet::create(scenario.ctx()));
    scenario.next_tx(ALICE);
    let w: Wallet = scenario.take_shared();
    deposit(&w, test_sui(scenario, 100));
    ts::return_shared(w);
}

/// ===== tests =====

#[test]
fun happy_path_addr_auth_plus_two_caveats() {
    let mut scenario = ts::begin(ALICE);
    setup(&mut scenario);

    // Owner: AddrAuth (OR) + OnlyCarolRecipient AND MaxAmount50 (AND).
    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();
        policy::initialize(&mut w, scenario.ctx());
        policy::add_auth_rule<AddrAuth>(&mut w, scenario.ctx());
        policy::add_caveat_rule<OnlyCarolRecipient>(&mut w, scenario.ctx());
        policy::add_caveat_rule<MaxAmount50>(&mut w, scenario.ctx());
        assert!(policy::auth_rule_count(&w) == 1, 0);
        assert!(policy::caveat_rule_count(&w) == 2, 0);
        ts::return_shared(w);
    };

    // Delegate BOB spends 40 to CAROL; both caveats + auth satisfied.
    scenario.next_tx(BOB);
    {
        let mut w: Wallet = scenario.take_shared();
        let mut req = policy::begin_spend<SUI>(&w, 40, CAROL);
        prove_addr_auth(BOB, &mut req, scenario.ctx());
        enforce_only_carol(&mut req);
        enforce_max_50(&mut req);
        policy::confirm_spend<SUI>(&mut w, req, scenario.ctx());
        ts::return_shared(w);
    };

    // CAROL received exactly 40 SUI.
    scenario.next_tx(CAROL);
    {
        let received: Coin<SUI> = scenario.take_from_address(CAROL);
        assert!(coin::value(&received) == 40, 0);
        ts::return_to_sender(&scenario, received);
    };

    ts::end(scenario);
}

#[test]
fun auth_only_no_caveats_succeeds() {
    let mut scenario = ts::begin(ALICE);
    setup(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();
        policy::initialize(&mut w, scenario.ctx());
        policy::add_auth_rule<AddrAuth>(&mut w, scenario.ctx());
        ts::return_shared(w);
    };

    // No caveats attached => AND over empty set is true; only auth gates.
    scenario.next_tx(BOB);
    {
        let mut w: Wallet = scenario.take_shared();
        let mut req = policy::begin_spend<SUI>(&w, 10, MALLORY);
        prove_addr_auth(BOB, &mut req, scenario.ctx());
        policy::confirm_spend<SUI>(&mut w, req, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(MALLORY);
    {
        let received: Coin<SUI> = scenario.take_from_address(MALLORY);
        assert!(coin::value(&received) == 10, 0);
        ts::return_to_sender(&scenario, received);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 3, location = SupWallet::policy)]
fun missing_auth_aborts() {
    let mut scenario = ts::begin(ALICE);
    setup(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();
        policy::initialize(&mut w, scenario.ctx());
        policy::add_auth_rule<AddrAuth>(&mut w, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let mut w: Wallet = scenario.take_shared();
        let req = policy::begin_spend<SUI>(&w, 10, CAROL);
        // never prove auth -> EAuthNotProven (3)
        policy::confirm_spend<SUI>(&mut w, req, scenario.ctx());
        ts::return_shared(w);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 4, location = SupWallet::policy)]
fun missing_caveat_aborts() {
    let mut scenario = ts::begin(ALICE);
    setup(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();
        policy::initialize(&mut w, scenario.ctx());
        policy::add_auth_rule<AddrAuth>(&mut w, scenario.ctx());
        policy::add_caveat_rule<OnlyCarolRecipient>(&mut w, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let mut w: Wallet = scenario.take_shared();
        let mut req = policy::begin_spend<SUI>(&w, 10, CAROL);
        prove_addr_auth(BOB, &mut req, scenario.ctx());
        // caveat attached but never stamped -> EMissingCaveat (4)
        policy::confirm_spend<SUI>(&mut w, req, scenario.ctx());
        ts::return_shared(w);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 5, location = SupWallet::policy)]
fun stale_version_after_revoke_aborts() {
    let mut scenario = ts::begin(ALICE);
    setup(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();
        policy::initialize(&mut w, scenario.ctx());
        policy::add_auth_rule<AddrAuth>(&mut w, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let w: Wallet = scenario.take_shared();
        let mut req = policy::begin_spend<SUI>(&w, 10, CAROL);
        prove_addr_auth(BOB, &mut req, scenario.ctx());
        ts::return_shared(w);

        // Owner revokes between begin and confirm: version bumps, request is stale.
        scenario.next_tx(ALICE);
        let mut w2: Wallet = scenario.take_shared();
        policy::revoke_all(&mut w2, scenario.ctx());

        // -> EStaleVersion (5)
        policy::confirm_spend<SUI>(&mut w2, req, scenario.ctx());
        ts::return_shared(w2);
    };

    ts::end(scenario);
}

/// `confirm_spend_into` runs the same gate but hands the coin back to the PTB
/// (bounded by the same allowance) instead of paying `recipient`.
#[test]
fun confirm_spend_into_returns_bounded_coin() {
    let mut scenario = ts::begin(ALICE);
    setup(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();
        policy::initialize(&mut w, scenario.ctx());
        policy::add_auth_rule<AddrAuth>(&mut w, scenario.ctx());
        policy::add_caveat_rule<MaxAmount50>(&mut w, scenario.ctx());
        ts::return_shared(w);
    };

    // BOB spends 40 via the `_into` path: the coin comes back to the PTB.
    scenario.next_tx(BOB);
    {
        let mut w: Wallet = scenario.take_shared();
        let mut req = policy::begin_spend<SUI>(&w, 40, CAROL);
        prove_addr_auth(BOB, &mut req, scenario.ctx());
        enforce_max_50(&mut req);
        let paid = policy::confirm_spend_into<SUI>(&mut w, req, scenario.ctx());
        // bounded by the caveat (<=50) and equal to the requested amount
        assert!(coin::value(&paid) == 40, 0);
        coin::burn_for_testing(paid); // the PTB would route this into escrow / a swap
        ts::return_shared(w);
    };

    ts::end(scenario);
}

/// The `_into` path enforces the identical gate: a missing caveat still aborts.
#[test]
#[expected_failure(abort_code = 4, location = SupWallet::policy)]
fun confirm_spend_into_missing_caveat_aborts() {
    let mut scenario = ts::begin(ALICE);
    setup(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();
        policy::initialize(&mut w, scenario.ctx());
        policy::add_auth_rule<AddrAuth>(&mut w, scenario.ctx());
        policy::add_caveat_rule<OnlyCarolRecipient>(&mut w, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let mut w: Wallet = scenario.take_shared();
        let mut req = policy::begin_spend<SUI>(&w, 10, CAROL);
        prove_addr_auth(BOB, &mut req, scenario.ctx());
        // caveat attached but never stamped -> EMissingCaveat (4)
        let paid = policy::confirm_spend_into<SUI>(&mut w, req, scenario.ctx());
        coin::burn_for_testing(paid); // unreachable
        ts::return_shared(w);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 7, location = SupWallet::policy)]
fun wrong_coin_aborts() {
    let mut scenario = ts::begin(ALICE);
    setup(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();
        policy::initialize(&mut w, scenario.ctx());
        policy::add_auth_rule<AddrAuth>(&mut w, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let mut w: Wallet = scenario.take_shared();
        let mut req = policy::begin_spend<SUI>(&w, 10, CAROL);
        prove_addr_auth(BOB, &mut req, scenario.ctx());
        // started as SUI, confirmed as USDC -> EWrongCoin (7)
        policy::confirm_spend<USDC>(&mut w, req, scenario.ctx());
        ts::return_shared(w);
    };

    ts::end(scenario);
}

#[test_only]
module adaptor_bluefin_margin::adaptor_tests;

use adaptor_bluefin_margin::adaptor::{Self, BluefinMarginAccount};
use SupWallet::wallet::{Self, Wallet};
use sui::test_scenario::{Self as ts};

const ALICE: address = @0xA;
const BOB: address = @0xB;
const BLUEFIN_ACCT: address = @0xB1;
const BLUEFIN_ACCT_2: address = @0xB2;

// NOTE: the deposit happy-path (`deposit_margin`) is intentionally NOT exercised
// here — `bluefin_exchange::exchange::deposit_to_asset_bank` is an ABI stub whose
// body aborts. Once the real Bluefin deposit ABI is vendored, add a capped-spend
// round-trip (grant_service_coin + delegate allowances, deposit as a delegate,
// assert the per-service/per-coin debit). These tests cover the owner-gating and
// destination-binding the adaptor itself enforces.

#[test]
fun test_adopt_set_reclaim_round_trip() {
    let mut scenario = ts::begin(ALICE);
    transfer::public_share_object(wallet::create(scenario.ctx()));

    // Owner binds a Bluefin account.
    scenario.next_tx(ALICE);
    {
        let wallet: Wallet = scenario.take_shared();
        let _id = adaptor::adopt(&wallet, BLUEFIN_ACCT, scenario.ctx());
        ts::return_shared(wallet);
    };

    // Owner re-points it, then reclaims (deletes) it.
    scenario.next_tx(ALICE);
    {
        let wallet: Wallet = scenario.take_shared();
        let mut acct: BluefinMarginAccount = scenario.take_shared();
        assert!(adaptor::bluefin_account(&acct) == BLUEFIN_ACCT, 0);

        adaptor::set_account(&wallet, &mut acct, BLUEFIN_ACCT_2, scenario.ctx());
        assert!(adaptor::bluefin_account(&acct) == BLUEFIN_ACCT_2, 1);

        adaptor::reclaim(&wallet, acct, scenario.ctx());
        ts::return_shared(wallet);
    };

    ts::end(scenario);
}

#[test, expected_failure(abort_code = adaptor_bluefin_margin::adaptor::ENotOwner)]
fun test_adopt_not_owner_aborts() {
    let mut scenario = ts::begin(ALICE);
    transfer::public_share_object(wallet::create(scenario.ctx()));

    // A non-owner (BOB) cannot bind a Bluefin account to ALICE's vault.
    scenario.next_tx(BOB);
    {
        let wallet: Wallet = scenario.take_shared();
        let _id = adaptor::adopt(&wallet, BLUEFIN_ACCT, scenario.ctx());
        ts::return_shared(wallet);
    };

    ts::end(scenario);
}

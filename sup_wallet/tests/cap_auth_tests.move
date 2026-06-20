#[test_only]
module SupWallet::cap_auth_tests;

use SupWallet::cap_auth::{Self, DelegateCap, CapAuth};
use SupWallet::policy::{Self, SpendRequest};
use SupWallet::wallet::{Self, Wallet};
use sui::{
    coin::{Self, Coin},
    sui::SUI,
    test_scenario::{Self as ts, Scenario},
    object,
};

const ALICE: address = @0xA; // wallet owner
const BOB: address = @0xB; // first cap holder
const DAVE: address = @0xD; // second holder (after transfer)
const CAROL: address = @0xC; // recipient

/// A caveat rule a "contract" enforces on itself (see contract_custody test).
public struct VaultCaveat has drop {}

/// A minimal on-chain "contract" that custodies a DelegateCap and spends from
/// the wallet on its own logic Ã¢â‚¬â€ demonstrating that the delegate can be a
/// contract, not an address.
public struct Vault has key {
    id: UID,
    cap: DelegateCap,
}

/// ===== helpers =====

fun test_sui(ts: &mut Scenario, amount: u64): Coin<SUI> {
    coin::mint_for_testing(amount, ts.ctx())
}

fun deposit(w: &Wallet, coin: Coin<SUI>) {
    coin::send_funds(coin, wallet::identity(w));
}

/// Create a funded wallet with an initialized policy that accepts `CapAuth` as
/// its (only) auth rule. Returns the shared wallet's id.
fun fresh_wallet(scenario: &mut Scenario): ID {
    sui::transfer::public_share_object(wallet::create(scenario.ctx()));
    scenario.next_tx(ALICE);
    let id = ts::most_recent_id_shared<Wallet>().destroy_some();
    let mut w = ts::take_shared_by_id<Wallet>(scenario, id);
    deposit(&w, test_sui(scenario, 100));
    policy::initialize(&mut w, scenario.ctx());
    policy::add_auth_rule<CapAuth>(&mut w, scenario.ctx());
    ts::return_shared(w);
    id
}

/// ===== tests =====

#[test]
fun cap_holder_spends() {
    let mut scenario = ts::begin(ALICE);
    let wid = fresh_wallet(&mut scenario);

    // Owner mints a cap and hands it to BOB.
    scenario.next_tx(ALICE);
    {
        let w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        cap_auth::mint_and_transfer(&w, BOB, scenario.ctx());
        ts::return_shared(w);
    };

    // BOB Ã¢â‚¬â€ never registered as an address delegate Ã¢â‚¬â€ spends purely by holding the cap.
    scenario.next_tx(BOB);
    {
        let mut w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        let cap: DelegateCap = scenario.take_from_address(BOB);
        let mut req = policy::begin_spend<SUI>(&w, 30, CAROL);
        cap_auth::prove(&cap, &mut req);
        policy::confirm_spend<SUI>(&mut w, req, scenario.ctx());
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
fun cap_is_bearer_after_transfer() {
    let mut scenario = ts::begin(ALICE);
    let wid = fresh_wallet(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        cap_auth::mint_and_transfer(&w, BOB, scenario.ctx());
        ts::return_shared(w);
    };

    // BOB forwards the cap to DAVE (bearer authority moves with the object).
    scenario.next_tx(BOB);
    {
        let cap: DelegateCap = scenario.take_from_address(BOB);
        transfer::public_transfer(cap, DAVE);
    };

    // DAVE, the new holder, can now spend.
    scenario.next_tx(DAVE);
    {
        let mut w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        let cap: DelegateCap = scenario.take_from_address(DAVE);
        let mut req = policy::begin_spend<SUI>(&w, 15, CAROL);
        cap_auth::prove(&cap, &mut req);
        policy::confirm_spend<SUI>(&mut w, req, scenario.ctx());
        ts::return_to_sender(&scenario, cap);
        ts::return_shared(w);
    };

    scenario.next_tx(CAROL);
    {
        let received: Coin<SUI> = scenario.take_from_address(CAROL);
        assert!(coin::value(&received) == 15, 0);
        ts::return_to_sender(&scenario, received);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 2, location = SupWallet::cap_auth)]
fun revoked_cap_aborts() {
    let mut scenario = ts::begin(ALICE);
    let wid = fresh_wallet(&mut scenario);

    scenario.next_tx(ALICE);
    {
        let w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        cap_auth::mint_and_transfer(&w, BOB, scenario.ctx());
        ts::return_shared(w);
    };

    // Owner pulls the kill-switch: bumps policy version.
    scenario.next_tx(ALICE);
    {
        let mut w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        policy::revoke_all(&mut w, scenario.ctx());
        ts::return_shared(w);
    };

    // BOB's cap now carries a stale version -> prove aborts ECapRevoked (2).
    scenario.next_tx(BOB);
    {
        let mut w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        let cap: DelegateCap = scenario.take_from_address(BOB);
        let mut req = policy::begin_spend<SUI>(&w, 10, CAROL);
        cap_auth::prove(&cap, &mut req); // aborts ECapRevoked (2)
        policy::confirm_spend<SUI>(&mut w, req, scenario.ctx()); // unreachable; consumes the hot potato
        ts::return_to_sender(&scenario, cap);
        ts::return_shared(w);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 1, location = SupWallet::cap_auth)]
fun wrong_wallet_cap_aborts() {
    let mut scenario = ts::begin(ALICE);
    let wid_a = fresh_wallet(&mut scenario);

    // Mint a cap for wallet A, give it to BOB.
    scenario.next_tx(ALICE);
    {
        let w = ts::take_shared_by_id<Wallet>(&scenario, wid_a);
        cap_auth::mint_and_transfer(&w, BOB, scenario.ctx());
        ts::return_shared(w);
    };

    // A second, unrelated wallet B.
    let wid_b = fresh_wallet(&mut scenario);

    // BOB tries to use wallet A's cap against wallet B -> EWrongWallet (1).
    scenario.next_tx(BOB);
    {
        let mut w_b = ts::take_shared_by_id<Wallet>(&scenario, wid_b);
        let cap: DelegateCap = scenario.take_from_address(BOB);
        let mut req = policy::begin_spend<SUI>(&w_b, 10, CAROL);
        cap_auth::prove(&cap, &mut req);
        // unreachable
        policy::confirm_spend<SUI>(&mut w_b, req, scenario.ctx());
        ts::return_to_sender(&scenario, cap);
        ts::return_shared(w_b);
    };

    ts::end(scenario);
}

#[test]
fun contract_custody_spends() {
    let mut scenario = ts::begin(ALICE);
    let wid = fresh_wallet(&mut scenario);

    // Owner adds the vault's caveat, mints a cap, and locks it inside a Vault
    // "contract" which is then shared. The Vault Ã¢â‚¬â€ not any address Ã¢â‚¬â€ is the delegate.
    scenario.next_tx(ALICE);
    {
        let mut w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        policy::add_caveat_rule<VaultCaveat>(&mut w, scenario.ctx());
        let cap = cap_auth::mint(&w, scenario.ctx());
        let vault = Vault { id: object::new(scenario.ctx()), cap };
        transfer::share_object(vault);
        ts::return_shared(w);
    };

    // Anyone can poke the vault; the vault spends from the wallet using its
    // custodied cap + its own caveat logic.
    scenario.next_tx(BOB);
    {
        let mut w = ts::take_shared_by_id<Wallet>(&scenario, wid);
        let vault: Vault = scenario.take_shared();
        let mut req = policy::begin_spend<SUI>(&w, 25, CAROL);
        cap_auth::prove(&vault.cap, &mut req);
        policy::add_caveat_receipt(VaultCaveat {}, &mut req); // vault enforces its own rule
        policy::confirm_spend<SUI>(&mut w, req, scenario.ctx());
        ts::return_shared(vault);
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

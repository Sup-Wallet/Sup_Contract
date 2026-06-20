module SupWallet::wallet_tests;

use SupWallet::delegate;
use SupWallet::wallet::{Self, Wallet};
use sui::{
    coin::{Self, Coin},
    sui::SUI,
    test_scenario::{Self as ts, Scenario},
};
use usdc::usdc::USDC;
use zzyzx_framework::account;

const ALICE: address = @0xA;
const BOB: address = @0xB;

public struct AmountOnlyService has drop {}
public struct TokenOnlyServiceA has drop {}
public struct TokenOnlyServiceB has drop {}
public struct FullAccessServiceA has drop {}
public struct FullAccessServiceB has drop {}
public struct ExternalAccountService has drop {}

#[test_only]
fun test_sui(ts: &mut Scenario, amount: u64): Coin<SUI> {
    coin::mint_for_testing(amount, ts.ctx())
}

#[test_only]
fun test_usdc(ts: &mut Scenario, amount: u64): Coin<USDC> {
    coin::mint_for_testing(amount, ts.ctx())
}

#[test_only]
fun deposit_to_wallet<CoinType>(w: &Wallet, coin: Coin<CoinType>) {
    coin::send_funds(coin, wallet::identity(w));
}

// SIP-58 NOTE: wallet balance now lives on the address accumulator. Reading
// it requires the system `AccumulatorRoot` object which is not trivially
// available in `test_scenario`. We therefore verify deposit / withdraw flow
// via the post-tx `take_from_sender<Coin<T>>` pattern (Coin object received
// equals what `take_coin` produced).
#[test]
fun test_wallet_basic_operations() {
    let mut scenario = ts::begin(ALICE);

    sui::transfer::public_share_object(wallet::create(scenario.ctx()));

    scenario.next_tx(ALICE);
    {
        let w: Wallet = scenario.take_shared();

        // Deposits ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â direct SIP-58 transfer to the wallet identity.
        let sui_coin = test_sui(&mut scenario, 100);
        deposit_to_wallet(&w, sui_coin);

        let more_sui = test_sui(&mut scenario, 100);
        deposit_to_wallet(&w, more_sui);

        let usdc_coin = test_usdc(&mut scenario, 200);
        deposit_to_wallet(&w, usdc_coin);

        ts::return_shared(w);
    };

    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();

        // Withdrawals ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â owner-direct via wallet::take_coin (wraps
        // withdraw_funds_from_object + redeem_funds + public_transfer).
        wallet::take_coin<SUI>(&mut w, 50, scenario.ctx());
        wallet::take_coin<USDC>(&mut w, 150, scenario.ctx());

        ts::return_shared(w);
    };

    scenario.next_tx(ALICE);
    {
        // Verify the Coin objects actually landed at sender with the right amounts.
        let sui_received: Coin<SUI> = scenario.take_from_sender();
        let usdc_received: Coin<USDC> = scenario.take_from_sender();
        assert!(coin::value(&sui_received) == 50, 0);
        assert!(coin::value(&usdc_received) == 150, 0);
        ts::return_to_sender(&scenario, sui_received);
        ts::return_to_sender(&scenario, usdc_received);
    };

    ts::end(scenario);
}

#[test]
fun sweep_legacy_coin_is_permissionless_but_credits_wallet() {
    let mut scenario = ts::begin(ALICE);

    sui::transfer::public_share_object(wallet::create(scenario.ctx()));

    scenario.next_tx(ALICE);
    {
        let w: Wallet = scenario.take_shared();
        let legacy_coin = test_sui(&mut scenario, 77);
        sui::transfer::public_transfer(legacy_coin, object::id(&w).to_address());
        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let mut w: Wallet = scenario.take_shared();
        let wallet_id = object::id(&w);
        let receiving = ts::most_recent_receiving_ticket<Coin<SUI>>(&wallet_id);
        wallet::sweep_legacy_coin<SUI>(&mut w, receiving);
        ts::return_shared(w);
    };

    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();
        wallet::take_coin<SUI>(&mut w, 77, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(ALICE);
    {
        let received: Coin<SUI> = scenario.take_from_sender();
        assert!(coin::value(&received) == 77, 0);
        ts::return_to_sender(&scenario, received);
    };

    ts::end(scenario);
}

// === Owner-gated AccountRequest issuance ===
//
// The previous `wallet::signer_ref(&Wallet) -> &Account` accessor let any
// caller of a shared `Wallet` grab the nested `Account` and feed it through
// `account::request_with_account` to mint an `AccountRequest` whose
// `.address()` matched the wallet's identity ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â bypassing every
// owner-gated path that relied on that identity (notably
// `os_account::OsAccount` admin operations whose `parent_wallet_identity`
// is set to `wallet::identity(sup_wallet)` by the Sup adaptor).
//
// `signer_ref` is now deleted. The only AccountRequest issuance path on a
// Wallet is `wallet::sign(&Wallet, &TxContext)`, which asserts
// `ctx.sender() == wallet.owner` before producing the request. These two
// tests cover both arms of that gate.

#[test]
fun sign_with_owner_returns_request_matching_identity() {
    let mut scenario = ts::begin(ALICE);
    sui::transfer::public_share_object(wallet::create(scenario.ctx()));

    scenario.next_tx(ALICE);
    {
        let w: Wallet = scenario.take_shared();
        let identity = wallet::identity(&w);

        let req = wallet::sign(&w, scenario.ctx());
        assert!(account::request_address(&req) == identity, 0);

        ts::return_shared(w);
    };

    ts::end(scenario);
}

/// ENotYourWallet = 5 in `SupWallet::wallet`.
#[test, expected_failure(abort_code = 5, location = SupWallet::wallet)]
fun sign_with_non_owner_aborts() {
    let mut scenario = ts::begin(ALICE);
    sui::transfer::public_share_object(wallet::create(scenario.ctx()));

    // Switch to BOB and try to forge a request against ALICE's wallet.
    scenario.next_tx(BOB);
    {
        let w: Wallet = scenario.take_shared();
        let _req = wallet::sign(&w, scenario.ctx());
        ts::return_shared(w);
    };

    ts::end(scenario);
}

#[test]
fun external_account_binding_owner_flow() {
    let mut scenario = ts::begin(ALICE);
    sui::transfer::public_share_object(wallet::create(scenario.ctx()));

    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();
        assert!(!wallet::is_external_account_bound<ExternalAccountService>(&w, BOB), 0);

        wallet::bind_external_account<ExternalAccountService>(&mut w, BOB, scenario.ctx());
        assert!(wallet::is_external_account_bound<ExternalAccountService>(&w, BOB), 0);
        wallet::assert_external_account_bound_or_owner<ExternalAccountService>(&w, BOB, scenario.ctx());

        wallet::unbind_external_account<ExternalAccountService>(&mut w, BOB, scenario.ctx());
        assert!(!wallet::is_external_account_bound<ExternalAccountService>(&w, BOB), 0);
        wallet::assert_external_account_bound_or_owner<ExternalAccountService>(&w, BOB, scenario.ctx());

        ts::return_shared(w);
    };

    ts::end(scenario);
}

#[test, expected_failure(abort_code = 5, location = SupWallet::wallet)]
fun external_account_bind_non_owner_aborts() {
    let mut scenario = ts::begin(ALICE);
    sui::transfer::public_share_object(wallet::create(scenario.ctx()));

    scenario.next_tx(BOB);
    {
        let mut w: Wallet = scenario.take_shared();
        wallet::bind_external_account<ExternalAccountService>(&mut w, BOB, scenario.ctx());
        ts::return_shared(w);
    };

    ts::end(scenario);
}

#[test, expected_failure(abort_code = 12, location = SupWallet::wallet)]
fun external_account_unbound_delegate_aborts() {
    let mut scenario = ts::begin(ALICE);
    sui::transfer::public_share_object(wallet::create(scenario.ctx()));

    scenario.next_tx(BOB);
    {
        let w: Wallet = scenario.take_shared();
        wallet::assert_external_account_bound_or_owner<ExternalAccountService>(&w, BOB, scenario.ctx());
        ts::return_shared(w);
    };

    ts::end(scenario);
}

#[test]
fun delegate_amount_only_allows_any_token_for_service() {
    let mut scenario = ts::begin(ALICE);
    sui::transfer::public_share_object(wallet::create(scenario.ctx()));

    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();
        deposit_to_wallet(&w, test_sui(&mut scenario, 100));
        deposit_to_wallet(&w, test_usdc(&mut scenario, 100));

        wallet::grant_service_any_coin<AmountOnlyService>(&mut w, scenario.ctx());
        delegate::initialize(&mut w, scenario.ctx());
        delegate::add(&mut w, BOB, scenario.ctx());
        delegate::set_service_allowance<AmountOnlyService>(&mut w, BOB, 100, scenario.ctx());
        delegate::set_any_coin_unlimited_allowance(&mut w, BOB, scenario.ctx());

        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let mut w: Wallet = scenario.take_shared();
        delegate::spend<AmountOnlyService, SUI>(AmountOnlyService {}, &mut w, 40, BOB, scenario.ctx());
        delegate::spend<AmountOnlyService, USDC>(AmountOnlyService {}, &mut w, 60, BOB, scenario.ctx());

        assert!(delegate::service_allowance<AmountOnlyService>(&w, BOB) == 0, 0);
        assert!(delegate::is_service_authorized<AmountOnlyService>(&w, BOB), 0);
        assert!(!delegate::is_service_authorized<TokenOnlyServiceA>(&w, BOB), 0);
        assert!(delegate::any_coin_allowance(&w, BOB) == delegate::unlimited_allowance(), 0);

        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let sui_received: Coin<SUI> = scenario.take_from_sender();
        let usdc_received: Coin<USDC> = scenario.take_from_sender();
        assert!(coin::value(&sui_received) == 40, 0);
        assert!(coin::value(&usdc_received) == 60, 0);
        ts::return_to_sender(&scenario, sui_received);
        ts::return_to_sender(&scenario, usdc_received);
    };

    ts::end(scenario);
}

#[test]
fun delegate_token_only_unlimited_allows_service_for_token() {
    let mut scenario = ts::begin(ALICE);
    sui::transfer::public_share_object(wallet::create(scenario.ctx()));

    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();
        deposit_to_wallet(&w, test_sui(&mut scenario, 100));

        wallet::grant_service_coin<TokenOnlyServiceA, SUI>(&mut w, scenario.ctx());
        delegate::initialize(&mut w, scenario.ctx());
        delegate::add(&mut w, BOB, scenario.ctx());
        delegate::set_service_unlimited_allowance<TokenOnlyServiceA>(&mut w, BOB, scenario.ctx());
        delegate::set_coin_unlimited_allowance<SUI>(&mut w, BOB, scenario.ctx());

        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let mut w: Wallet = scenario.take_shared();
        delegate::spend<TokenOnlyServiceA, SUI>(TokenOnlyServiceA {}, &mut w, 30, BOB, scenario.ctx());
        delegate::spend<TokenOnlyServiceA, SUI>(TokenOnlyServiceA {}, &mut w, 40, BOB, scenario.ctx());

        let unlimited = delegate::unlimited_allowance();
        assert!(delegate::service_allowance<TokenOnlyServiceA>(&w, BOB) == unlimited, 0);
        assert!(delegate::service_allowance<TokenOnlyServiceB>(&w, BOB) == 0, 0);
        assert!(delegate::coin_allowance<SUI>(&w, BOB) == unlimited, 0);

        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let sui_received_a: Coin<SUI> = scenario.take_from_sender();
        let sui_received_b: Coin<SUI> = scenario.take_from_sender();
        assert!(coin::value(&sui_received_a) + coin::value(&sui_received_b) == 70, 0);
        ts::return_to_sender(&scenario, sui_received_a);
        ts::return_to_sender(&scenario, sui_received_b);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = delegate::EServiceNotAuthorized)]
fun delegate_token_only_does_not_authorize_other_service() {
    let mut scenario = ts::begin(ALICE);
    sui::transfer::public_share_object(wallet::create(scenario.ctx()));

    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();
        deposit_to_wallet(&w, test_sui(&mut scenario, 100));

        wallet::grant_service_coin<TokenOnlyServiceA, SUI>(&mut w, scenario.ctx());
        delegate::initialize(&mut w, scenario.ctx());
        delegate::add(&mut w, BOB, scenario.ctx());
        delegate::set_service_unlimited_allowance<TokenOnlyServiceA>(&mut w, BOB, scenario.ctx());
        delegate::set_coin_unlimited_allowance<SUI>(&mut w, BOB, scenario.ctx());

        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let mut w: Wallet = scenario.take_shared();
        delegate::spend<TokenOnlyServiceB, SUI>(TokenOnlyServiceB {}, &mut w, 1, BOB, scenario.ctx());
        ts::return_shared(w);
    };

    ts::end(scenario);
}

#[test]
fun delegate_full_unlimited_allows_any_token_for_service() {
    let mut scenario = ts::begin(ALICE);
    sui::transfer::public_share_object(wallet::create(scenario.ctx()));

    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();
        deposit_to_wallet(&w, test_sui(&mut scenario, 100));
        deposit_to_wallet(&w, test_usdc(&mut scenario, 100));

        wallet::grant_service_any_coin<FullAccessServiceA>(&mut w, scenario.ctx());
        delegate::initialize(&mut w, scenario.ctx());
        delegate::add(&mut w, BOB, scenario.ctx());
        delegate::set_unlimited_allowance<FullAccessServiceA>(&mut w, BOB, scenario.ctx());

        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let mut w: Wallet = scenario.take_shared();
        delegate::spend<FullAccessServiceA, SUI>(FullAccessServiceA {}, &mut w, 25, BOB, scenario.ctx());
        delegate::spend<FullAccessServiceA, USDC>(FullAccessServiceA {}, &mut w, 35, BOB, scenario.ctx());

        let unlimited = delegate::unlimited_allowance();
        assert!(delegate::service_allowance<FullAccessServiceA>(&w, BOB) == unlimited, 0);
        assert!(delegate::service_allowance<FullAccessServiceB>(&w, BOB) == 0, 0);
        assert!(delegate::any_coin_allowance(&w, BOB) == unlimited, 0);

        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let sui_received: Coin<SUI> = scenario.take_from_sender();
        let usdc_received: Coin<USDC> = scenario.take_from_sender();
        assert!(coin::value(&sui_received) == 25, 0);
        assert!(coin::value(&usdc_received) == 35, 0);
        ts::return_to_sender(&scenario, sui_received);
        ts::return_to_sender(&scenario, usdc_received);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = delegate::EServiceNotAuthorized)]
fun delegate_full_unlimited_does_not_authorize_other_service() {
    let mut scenario = ts::begin(ALICE);
    sui::transfer::public_share_object(wallet::create(scenario.ctx()));

    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();
        deposit_to_wallet(&w, test_sui(&mut scenario, 100));

        wallet::grant_service_any_coin<FullAccessServiceA>(&mut w, scenario.ctx());
        delegate::initialize(&mut w, scenario.ctx());
        delegate::add(&mut w, BOB, scenario.ctx());
        delegate::set_unlimited_allowance<FullAccessServiceA>(&mut w, BOB, scenario.ctx());

        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    {
        let mut w: Wallet = scenario.take_shared();
        delegate::spend<FullAccessServiceB, SUI>(FullAccessServiceB {}, &mut w, 1, BOB, scenario.ctx());
        ts::return_shared(w);
    };

    ts::end(scenario);
}

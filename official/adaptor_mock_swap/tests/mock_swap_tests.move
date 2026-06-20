#[test_only]
module AdaptorMockSwap::mock_swap_tests;

use AdaptorMockSwap::mock_swap::{Self, MockSwap};
use SupWallet::wallet::{Self, Wallet};
use SupWallet::delegate;
use sui::{
    coin::{Self, Coin},
    sui::SUI,
    test_scenario::{Self as ts},
};
use usdc::usdc::USDC;

const ALICE: address = @0xA;

#[test_only]
fun deposit_to_wallet<CoinType>(w: &Wallet, coin: Coin<CoinType>) {
    coin::send_funds(coin, wallet::identity(w));
}

// Full round-trip: ALICE (== main_owner) triggers a SUI → USDC swap of 1000
// SUI at 2:1 ratio, expecting 500 USDC back into the wallet.
#[test]
fun test_mock_swap_main_owner_round_trip() {
    let mut scenario = ts::begin(ALICE);

    // Wallet bring-up + permission grants
    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();

        let sui_coin = coin::mint_for_testing<SUI>(2000, scenario.ctx());
        deposit_to_wallet(&w, sui_coin);

        // grant MockSwap to spend SUI (CoinIn) and credit USDC (CoinOut).
        // Although Mode D only debits CoinIn allowance, wallet::is_authorized
        // is still asserted against CoinIn.
        wallet::grant_service_coin<MockSwap, SUI>(&mut w, scenario.ctx());

        // Initialize delegate registry so main_owner check inside
        // debit_*_allowance can short-circuit to UNLIMITED.
        delegate::initialize(&mut w, scenario.ctx());

        ts::return_shared(w);
    };

    // Trigger swap.
    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();

        mock_swap::do_swap<SUI, USDC>(
            &mut w,
            1000,           // amount_in
            450,            // min_amount_out
            1,              // rate_num
            2,              // rate_den → 500 out per 1000 in
            scenario.ctx(),
        );

        ts::return_shared(w);
    };

    // Adaptor doesn't transfer anything to ALICE — CoinOut lands back inside
    // the wallet via Mode D credit. No post-tx Coin<USDC> to take.

    ts::end(scenario);
}

// Slippage failure: ask for min_amount_out > actual swap output.
#[test, expected_failure(abort_code = SupWallet::intent::ESwapSlippageExceeded)]
fun test_mock_swap_slippage_aborts() {
    let mut scenario = ts::begin(ALICE);

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();
        let sui_coin = coin::mint_for_testing<SUI>(2000, scenario.ctx());
        deposit_to_wallet(&w, sui_coin);
        wallet::grant_service_coin<MockSwap, SUI>(&mut w, scenario.ctx());
        delegate::initialize(&mut w, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();
        mock_swap::do_swap<SUI, USDC>(
            &mut w,
            1000,           // amount_in
            600,            // min_amount_out > actual (500) → abort
            1,
            2,
            scenario.ctx(),
        );
        ts::return_shared(w);
    };

    ts::end(scenario);
}

// Service-not-authorized failure: MockSwap not in wallet.auth[CoinIn].
#[test, expected_failure(abort_code = SupWallet::intent::EAuthMissing)]
fun test_mock_swap_unauthorized_aborts() {
    let mut scenario = ts::begin(ALICE);

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();
        let sui_coin = coin::mint_for_testing<SUI>(2000, scenario.ctx());
        deposit_to_wallet(&w, sui_coin);
        // intentionally skip grant_service_coin<MockSwap, SUI>
        delegate::initialize(&mut w, scenario.ctx());
        ts::return_shared(w);
    };

    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();
        mock_swap::do_swap<SUI, USDC>(
            &mut w,
            1000, 450, 1, 2,
            scenario.ctx(),
        );
        ts::return_shared(w);
    };

    ts::end(scenario);
}

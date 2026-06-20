#[test_only]
module adaptor_typus::adaptor_tests;

use adaptor_typus::adaptor::{Self, TypusAdaptor};
use SupWallet::delegate;
use SupWallet::wallet::{Self, Wallet};
use sui::{
    coin::{Self, Coin},
    sui::SUI,
    test_scenario::{Self as ts},
};

const ALICE: address = @0xA;

#[test_only]
fun deposit_to_wallet<CoinType>(wallet: &Wallet, coin: Coin<CoinType>) {
    coin::send_funds(coin, wallet::identity(wallet));
}

#[test]
fun test_deposit_round_trip() {
    let mut scenario = ts::begin(ALICE);

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let mut wallet: Wallet = scenario.take_shared();
        let coin = coin::mint_for_testing<SUI>(2_000, scenario.ctx());
        deposit_to_wallet(&wallet, coin);
        wallet::grant_service_coin<TypusAdaptor, SUI>(&mut wallet, scenario.ctx());
        delegate::initialize(&mut wallet, scenario.ctx());
        ts::return_shared(wallet);
    };

    scenario.next_tx(ALICE);
    {
        let mut wallet: Wallet = scenario.take_shared();
        let (coin_in, witness) = adaptor::begin_deposit<SUI, SUI>(
            &mut wallet,
            1_000,
            900,
            scenario.ctx(),
        );
        coin::burn_for_testing(coin_in);

        let share_out = coin::mint_for_testing<SUI>(950, scenario.ctx());
        adaptor::finish_deposit<SUI, SUI>(&mut wallet, witness, share_out);
        ts::return_shared(wallet);
    };

    ts::end(scenario);
}

#[test]
fun test_redeem_round_trip() {
    let mut scenario = ts::begin(ALICE);

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let mut wallet: Wallet = scenario.take_shared();
        let share = coin::mint_for_testing<SUI>(2_000, scenario.ctx());
        deposit_to_wallet(&wallet, share);
        wallet::grant_service_coin<TypusAdaptor, SUI>(&mut wallet, scenario.ctx());
        delegate::initialize(&mut wallet, scenario.ctx());
        ts::return_shared(wallet);
    };

    scenario.next_tx(ALICE);
    {
        let mut wallet: Wallet = scenario.take_shared();
        let (share_in, witness) = adaptor::begin_redeem<SUI, SUI>(
            &mut wallet,
            1_000,
            900,
            scenario.ctx(),
        );
        coin::burn_for_testing(share_in);

        let asset_out = coin::mint_for_testing<SUI>(950, scenario.ctx());
        adaptor::finish_redeem<SUI, SUI>(&mut wallet, witness, asset_out);
        ts::return_shared(wallet);
    };

    ts::end(scenario);
}

#[test, expected_failure(abort_code = SupWallet::intent::ESwapSlippageExceeded)]
fun test_min_out_aborts() {
    let mut scenario = ts::begin(ALICE);

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let mut wallet: Wallet = scenario.take_shared();
        let coin = coin::mint_for_testing<SUI>(2_000, scenario.ctx());
        deposit_to_wallet(&wallet, coin);
        wallet::grant_service_coin<TypusAdaptor, SUI>(&mut wallet, scenario.ctx());
        delegate::initialize(&mut wallet, scenario.ctx());
        ts::return_shared(wallet);
    };

    scenario.next_tx(ALICE);
    {
        let mut wallet: Wallet = scenario.take_shared();
        let (coin_in, witness) = adaptor::begin_deposit<SUI, SUI>(
            &mut wallet,
            1_000,
            1_001,
            scenario.ctx(),
        );
        coin::burn_for_testing(coin_in);

        let share_out = coin::mint_for_testing<SUI>(950, scenario.ctx());
        adaptor::finish_deposit<SUI, SUI>(&mut wallet, witness, share_out);
        ts::return_shared(wallet);
    };

    ts::end(scenario);
}

#[test, expected_failure(abort_code = SupWallet::intent::EAuthMissing)]
fun test_unauthorized_aborts() {
    let mut scenario = ts::begin(ALICE);

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let mut wallet: Wallet = scenario.take_shared();
        let coin = coin::mint_for_testing<SUI>(2_000, scenario.ctx());
        deposit_to_wallet(&wallet, coin);
        delegate::initialize(&mut wallet, scenario.ctx());
        ts::return_shared(wallet);
    };

    scenario.next_tx(ALICE);
    {
        let mut wallet: Wallet = scenario.take_shared();
        let (coin_in, witness) = adaptor::begin_deposit<SUI, SUI>(
            &mut wallet,
            1_000,
            900,
            scenario.ctx(),
        );
        coin::burn_for_testing(coin_in);

        let share_out = coin::mint_for_testing<SUI>(950, scenario.ctx());
        adaptor::finish_deposit<SUI, SUI>(&mut wallet, witness, share_out);
        ts::return_shared(wallet);
    };

    ts::end(scenario);
}

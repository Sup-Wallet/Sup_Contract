module SupSubscription::subscription_tests;

use SupSubscription::subscription::{Self, SubscriptionService, Service, ChargeCap, Receipt};
use SupWallet::wallet::{Self, Wallet};
use SupWallet::delegate;
use SupWallet::intent;
use payment_kit::payment_kit::{Self as paykit, PaymentRegistry};
use sui::{
    coin::{Self, Coin},
    sui::SUI,
    clock::{Self},
    test_scenario::{Self as ts, Scenario},
};
use std::ascii;
use std::string;

const ALICE: address = @0xA;      // wallet owner
const ALICE_BOT: address = @0xA1; // delegate that ALICE authorised
const BOB: address = @0xB;        // service operator

#[test_only]
fun test_sui(ts: &mut Scenario, amount: u64): Coin<SUI> {
    coin::mint_for_testing(amount, ts.ctx())
}

#[test_only]
fun deposit_to_wallet<CoinType>(w: &Wallet, coin: Coin<CoinType>) {
    coin::send_funds(coin, wallet::identity(w));
}

#[test_only]
fun init_payment_registry(ctx: &mut TxContext) {
    paykit::init_for_testing(ctx);
}

/// SubscriptionService is not in the wallet's allowlist → intent::validate_and_pay aborts.
#[test]
#[expected_failure(abort_code = intent::EAuthMissing)]
fun test_subscription_unauthorized_should_fail() {
    let mut scenario = ts::begin(ALICE);
    init_payment_registry(scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();

        let sui_coin = test_sui(&mut scenario, 500);
        deposit_to_wallet(&w, sui_coin);

        // Registry + delegate + allowances set up, but NO grant_service_coin.
        delegate::initialize(&mut w, scenario.ctx());
        delegate::add(&mut w, ALICE_BOT, scenario.ctx());
        delegate::set_service_allowance<SubscriptionService>(&mut w, ALICE_BOT, 1000, scenario.ctx());
        delegate::set_coin_allowance<SUI>(&mut w, ALICE_BOT, 1000, scenario.ctx());

        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    subscription::create_service<SUI>(
        100,
        string::utf8(b"Premium"),
        BOB,
        100,
        scenario.ctx(),
    );

    // Delegate (NOT owner) signs the subscribe.
    scenario.next_tx(ALICE_BOT);
    {
        let mut w: Wallet = scenario.take_shared();
        let service: Service<SUI> = scenario.take_shared();
        let mut registry: PaymentRegistry = scenario.take_shared();

        subscription::subscribe<SUI>(
            &mut w,
            &service,
            &mut registry,
            ascii::string(b"unauthorized-1"),
            false,
            &clock,
            scenario.ctx(),
        );

        ts::return_shared(w);
        ts::return_shared(service);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_subscription_success_and_charge_fee() {
    let mut scenario = ts::begin(ALICE);
    init_payment_registry(scenario.ctx());
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Owner setup.
    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();

        let sui_coin = test_sui(&mut scenario, 500);
        deposit_to_wallet(&w, sui_coin);

        wallet::grant_service_coin<SubscriptionService, SUI>(&mut w, scenario.ctx());

        delegate::initialize(&mut w, scenario.ctx());
        delegate::add(&mut w, ALICE_BOT, scenario.ctx());
        delegate::set_service_allowance<SubscriptionService>(&mut w, ALICE_BOT, 1000, scenario.ctx());
        delegate::set_coin_allowance<SUI>(&mut w, ALICE_BOT, 1000, scenario.ctx());

        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    subscription::create_service<SUI>(
        100,
        string::utf8(b"Premium"),
        BOB,
        100,
        scenario.ctx(),
    );

    // Delegate signs the initial subscribe — Mode A.
    scenario.next_tx(ALICE_BOT);
    {
        let mut w: Wallet = scenario.take_shared();
        let service: Service<SUI> = scenario.take_shared();
        let mut registry: PaymentRegistry = scenario.take_shared();

        subscription::subscribe<SUI>(
            &mut w,
            &service,
            &mut registry,
            ascii::string(b"subscribe-1"),
            false,
            &clock,
            scenario.ctx(),
        );

        // SIP-58: wallet balance lives on the address accumulator; reading
        // it requires AccumulatorRoot which test_scenario doesn't expose.
        // Subscription correctness is verified via the Coin<SUI> Bob
        // receives + the delegate allowance debits below.
        assert!(delegate::service_allowance<SubscriptionService>(&w, ALICE_BOT) == 900, 0);
        assert!(delegate::coin_allowance<SUI>(&w, ALICE_BOT) == 900, 0);

        ts::return_shared(w);
        ts::return_shared(service);
        ts::return_shared(registry);
    };

    scenario.next_tx(BOB);
    {
        let payment: Coin<SUI> = scenario.take_from_sender();
        assert!(coin::value(&payment) == 100, 0);
        ts::return_to_sender(&scenario, payment);
    };

    // Receipt goes to the delegate (on-chain subscriber).
    scenario.next_tx(ALICE_BOT);
    {
        let receipt: Receipt<SUI> = scenario.take_from_sender();
        ts::return_to_sender(&scenario, receipt);
    };

    // Recurring charge after 31 days — Mode B: BOB charges ALICE_BOT's allowances.
    {
        let thirty_one_days_ms = 31 * 24 * 60 * 60 * 1000;
        clock::increment_for_testing(&mut clock, thirty_one_days_ms);
        scenario.next_tx(BOB);

        let mut charge_cap: ChargeCap = scenario.take_from_sender();
        let mut w: Wallet = scenario.take_shared();
        let service: Service<SUI> = scenario.take_shared();
        let mut registry: PaymentRegistry = scenario.take_shared();

        subscription::charge_fee<SUI>(
            &mut charge_cap,
            &mut w,
            &service,
            &mut registry,
            ascii::string(b"charge-1"),
            &clock,
            scenario.ctx(),
        );

        // SIP-58 balance is on the accumulator (see note above). The
        // delegate-allowance debits prove the charge_fee debited correctly.
        assert!(delegate::service_allowance<SubscriptionService>(&w, ALICE_BOT) == 800, 0);
        assert!(delegate::coin_allowance<SUI>(&w, ALICE_BOT) == 800, 0);

        ts::return_to_sender(&scenario, charge_cap);
        ts::return_shared(w);
        ts::return_shared(service);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = delegate::EInsufficientServiceAllowance)]
fun test_subscription_service_allowance_capped() {
    let mut scenario = ts::begin(ALICE);
    init_payment_registry(scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();

        let sui_coin = test_sui(&mut scenario, 500);
        deposit_to_wallet(&w, sui_coin);
        wallet::grant_service_coin<SubscriptionService, SUI>(&mut w, scenario.ctx());

        delegate::initialize(&mut w, scenario.ctx());
        delegate::add(&mut w, ALICE_BOT, scenario.ctx());
        // service allowance = 50, but subscription costs 100
        delegate::set_service_allowance<SubscriptionService>(&mut w, ALICE_BOT, 50, scenario.ctx());
        delegate::set_coin_allowance<SUI>(&mut w, ALICE_BOT, 1000, scenario.ctx());

        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    subscription::create_service<SUI>(100, string::utf8(b"Premium"), BOB, 100, scenario.ctx());

    scenario.next_tx(ALICE_BOT);
    {
        let mut w: Wallet = scenario.take_shared();
        let service: Service<SUI> = scenario.take_shared();
        let mut registry: PaymentRegistry = scenario.take_shared();

        subscription::subscribe<SUI>(
            &mut w,
            &service,
            &mut registry,
            ascii::string(b"cap-service-1"),
            false,
            &clock,
            scenario.ctx(),
        );

        ts::return_shared(w);
        ts::return_shared(service);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

/// Coin allowance is the second gate — service allowance can be high but if coin is low,
/// the spend still aborts.
#[test]
#[expected_failure(abort_code = delegate::EInsufficientCoinAllowance)]
fun test_subscription_coin_allowance_capped() {
    let mut scenario = ts::begin(ALICE);
    init_payment_registry(scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();

        let sui_coin = test_sui(&mut scenario, 500);
        deposit_to_wallet(&w, sui_coin);
        wallet::grant_service_coin<SubscriptionService, SUI>(&mut w, scenario.ctx());

        delegate::initialize(&mut w, scenario.ctx());
        delegate::add(&mut w, ALICE_BOT, scenario.ctx());
        delegate::set_service_allowance<SubscriptionService>(&mut w, ALICE_BOT, 1000, scenario.ctx());
        // coin allowance = 50, but subscription costs 100
        delegate::set_coin_allowance<SUI>(&mut w, ALICE_BOT, 50, scenario.ctx());

        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    subscription::create_service<SUI>(100, string::utf8(b"Premium"), BOB, 100, scenario.ctx());

    scenario.next_tx(ALICE_BOT);
    {
        let mut w: Wallet = scenario.take_shared();
        let service: Service<SUI> = scenario.take_shared();
        let mut registry: PaymentRegistry = scenario.take_shared();

        subscription::subscribe<SUI>(
            &mut w,
            &service,
            &mut registry,
            ascii::string(b"cap-coin-1"),
            false,
            &clock,
            scenario.ctx(),
        );

        ts::return_shared(w);
        ts::return_shared(service);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

/// Without `add` delegate, even if allowlist is granted the wallet doesn't know the sender.
#[test]
#[expected_failure(abort_code = delegate::ENotDelegate)]
fun test_subscription_non_delegate_blocked() {
    let mut scenario = ts::begin(ALICE);
    init_payment_registry(scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let mut w: Wallet = scenario.take_shared();

        let sui_coin = test_sui(&mut scenario, 500);
        deposit_to_wallet(&w, sui_coin);
        wallet::grant_service_coin<SubscriptionService, SUI>(&mut w, scenario.ctx());

        // Registry exists but ALICE_BOT is NOT added as a delegate.
        delegate::initialize(&mut w, scenario.ctx());

        ts::return_shared(w);
    };

    scenario.next_tx(BOB);
    subscription::create_service<SUI>(100, string::utf8(b"Premium"), BOB, 100, scenario.ctx());

    scenario.next_tx(ALICE_BOT);
    {
        let mut w: Wallet = scenario.take_shared();
        let service: Service<SUI> = scenario.take_shared();
        let mut registry: PaymentRegistry = scenario.take_shared();

        subscription::subscribe<SUI>(
            &mut w,
            &service,
            &mut registry,
            ascii::string(b"non-delegate-1"),
            false,
            &clock,
            scenario.ctx(),
        );

        ts::return_shared(w);
        ts::return_shared(service);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

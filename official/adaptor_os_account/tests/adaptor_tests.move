#[test_only]
module adaptor_os_account::adaptor_tests {
    use std::unit_test::assert_eq;
    use sui::clock;
    use sui::coin::{Self, Coin};
    use sui::test_scenario::{Self as ts};
    use SupWallet::delegate;
    use SupWallet::wallet::{Self, Wallet};
    use adaptor_os_account::adaptor::{Self, OsAccountAdaptor};
    use os_account::account::{Self, OsAccount};
    use os_account::registry::{Self, WalletAccountRegistry};

    const ALICE: address = @0xA;
    const BOT: address = @0xB;

    public struct USDC has drop {}

    fun mint_usdc(amount: u64, ctx: &mut TxContext): Coin<USDC> {
        coin::mint_for_testing<USDC>(amount, ctx)
    }

    fun deposit_to_wallet<CoinType>(w: &Wallet, coin: Coin<CoinType>) {
        coin::send_funds(coin, wallet::identity(w));
    }

    #[test]
    fun sup_creates_deposits_and_withdraws() {
        let mut scenario = ts::begin(ALICE);

        wallet::create(scenario.ctx());
        registry::create_and_share(scenario.ctx());

        scenario.next_tx(ALICE);
        let acc_id;
        {
            let mut w: Wallet = scenario.take_shared();
            let mut reg: WalletAccountRegistry = scenario.take_shared();
            let mut clock = clock::create_for_testing(scenario.ctx());
            clock::set_for_testing(&mut clock, 1);

            delegate::initialize(&mut w, scenario.ctx());
            wallet::grant_service_coin<OsAccountAdaptor, USDC>(&mut w, scenario.ctx());
            deposit_to_wallet(&w, mint_usdc(1_000, scenario.ctx()));

            acc_id = adaptor::create_os_account<USDC>(
                &mut w,
                &mut reg,
                option::some(b"btc-bot".to_string()),
                50_000,
                400,
                &clock,
                scenario.ctx(),
            );

            clock::destroy_for_testing(clock);
            ts::return_shared(w);
            ts::return_shared(reg);
        };

        scenario.next_tx(ALICE);
        {
            let mut w: Wallet = scenario.take_shared();
            let mut acc: OsAccount = scenario.take_shared_by_id(acc_id);

            adaptor::deposit<USDC>(&mut w, &acc, 200, scenario.ctx());
            adaptor::withdraw<USDC>(&mut w, &mut acc, 300, scenario.ctx());

            // Sup started with 1000, sent 600 to OS, received 300 back => 700.
            wallet::take_coin<USDC>(&mut w, 700, scenario.ctx());

            ts::return_shared(w);
            ts::return_shared(acc);
        };

        scenario.next_tx(ALICE);
        {
            let received: Coin<USDC> = scenario.take_from_sender();
            assert_eq!(coin::value(&received), 700);
            ts::return_to_sender(&scenario, received);
        };

        ts::end(scenario);
    }

    #[test]
    fun sup_request_can_admin_os_account() {
        let mut scenario = ts::begin(ALICE);

        wallet::create(scenario.ctx());
        registry::create_and_share(scenario.ctx());

        scenario.next_tx(ALICE);
        let acc_id;
        {
            let mut w: Wallet = scenario.take_shared();
            let mut reg: WalletAccountRegistry = scenario.take_shared();
            let mut clock = clock::create_for_testing(scenario.ctx());
            clock::set_for_testing(&mut clock, 1);
            delegate::initialize(&mut w, scenario.ctx());
            wallet::grant_service_coin<OsAccountAdaptor, USDC>(&mut w, scenario.ctx());
            acc_id = adaptor::create_os_account<USDC>(
                &mut w,
                &mut reg,
                option::none(),
                50_000,
                0,
                &clock,
                scenario.ctx(),
            );
            clock::destroy_for_testing(clock);
            ts::return_shared(w);
            ts::return_shared(reg);
        };

        scenario.next_tx(ALICE);
        {
            let w: Wallet = scenario.take_shared();
            let mut acc: OsAccount = scenario.take_shared_by_id(acc_id);
            let req = wallet::sign(&w, scenario.ctx());

            account::add_delegate_by_request(
                &mut acc,
                &req,
                BOT,
                account::perm_open() | account::perm_close(),
            );
            assert!(account::has_permission(&acc, BOT, account::perm_open()));
            assert!(!account::has_permission(&acc, BOT, account::perm_withdraw()));

            ts::return_shared(w);
            ts::return_shared(acc);
        };

        ts::end(scenario);
    }
}

module adaptor_navi::adaptor;

use SupWallet::intent;
use SupWallet::wallet::{Self, Wallet};
use navi_oracle::oracle::PriceOracle;
use navi_protocol::account::{Self, AccountCap};
use navi_protocol::incentive_v2;
use navi_protocol::incentive_v3::{Self, Incentive as IncentiveV3};
use navi_protocol::pool::Pool;
use navi_protocol::storage::Storage;
use sui::clock::Clock;
use sui::coin;
use sui::event;
use sui_system::sui_system::SuiSystemState;

const EZeroAmount: u64 = 0;
const EAccountOwnerMismatch: u64 = 1;
const EInsufficientOutput: u64 = 2;

public struct NaviAdaptor has drop {}

public struct NaviDeposited has copy, drop {
    account_owner: address,
    asset_id: u8,
    amount: u64,
}

public struct NaviWithdrawn has copy, drop {
    account_owner: address,
    asset_id: u8,
    amount: u64,
}

public fun deposit<CoinT>(
    wallet: &mut Wallet,
    account_cap: &AccountCap,
    expected_account_owner: address,
    storage: &mut Storage,
    pool: &mut Pool<CoinT>,
    asset_id: u8,
    amount: u64,
    incentive_v2_obj: &mut incentive_v2::Incentive,
    incentive_v3_obj: &mut IncentiveV3,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(amount > 0, EZeroAmount);
    assert_owner(account_cap, expected_account_owner);
    wallet::assert_external_account_bound_or_owner<NaviAdaptor>(
        wallet,
        expected_account_owner,
        ctx,
    );

    let sig = intent::request_payment<NaviAdaptor, CoinT>(
        NaviAdaptor {},
        amount,
        expected_account_owner,
    );
    let (coin_in, wallet_witness) =
        intent::validate_and_pay<NaviAdaptor, CoinT>(wallet, sig, ctx);
    incentive_v3::deposit_with_account_cap<CoinT>(
        clock,
        storage,
        pool,
        asset_id,
        coin_in,
        incentive_v2_obj,
        incentive_v3_obj,
        account_cap,
    );
    let receipt = intent::create_receipt_sig<NaviAdaptor, CoinT>(
        NaviAdaptor {},
        amount,
        expected_account_owner,
    );
    intent::verify_and_clear<NaviAdaptor, CoinT>(wallet_witness, receipt);

    event::emit(NaviDeposited {
        account_owner: expected_account_owner,
        asset_id,
        amount,
    });
}

public fun withdraw<CoinT>(
    wallet: &mut Wallet,
    account_cap: &AccountCap,
    expected_account_owner: address,
    oracle: &PriceOracle,
    storage: &mut Storage,
    pool: &mut Pool<CoinT>,
    asset_id: u8,
    amount: u64,
    min_amount_out: u64,
    incentive_v2_obj: &mut incentive_v2::Incentive,
    incentive_v3_obj: &mut IncentiveV3,
    system_state: &mut SuiSystemState,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(amount > 0, EZeroAmount);
    assert_owner(account_cap, expected_account_owner);
    wallet::assert_external_account_bound_or_owner<NaviAdaptor>(
        wallet,
        expected_account_owner,
        ctx,
    );

    let balance_out = incentive_v3::withdraw_with_account_cap_v2<CoinT>(
        clock,
        oracle,
        storage,
        pool,
        asset_id,
        amount,
        incentive_v2_obj,
        incentive_v3_obj,
        account_cap,
        system_state,
        ctx,
    );
    let coin_out = coin::from_balance(balance_out, ctx);
    let amount_out = coin::value(&coin_out);
    assert!(amount_out >= min_amount_out, EInsufficientOutput);
    wallet::receive_from_service<NaviAdaptor, CoinT>(wallet, coin_out, NaviAdaptor {});

    event::emit(NaviWithdrawn {
        account_owner: expected_account_owner,
        asset_id,
        amount: amount_out,
    });
}

fun assert_owner(account_cap: &AccountCap, expected: address) {
    assert!(account::account_owner(account_cap) == expected, EAccountOwnerMismatch);
}

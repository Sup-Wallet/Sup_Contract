module adaptor_cetus::adaptor;

use std::string::{Self, String};
use SupWallet::delegate;
use SupWallet::intent;
use SupWallet::wallet::{Self, Wallet};
use cetus_clmm::config::GlobalConfig;
use cetus_clmm::pool::{Self, Pool};
use cetus_clmm::position::Position;
use cetus_clmm::rewarder::RewarderGlobalVault;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin;
use sui::event;

const EZeroAmount: u64 = 0;
const EInsufficientInput: u64 = 1;
const ENotAuthorized: u64 = 2;
const EZeroLiquidity: u64 = 3;

public struct CetusAdaptor has drop {}

public struct CetusSwapped has copy, drop {
    a2b: bool,
    amount_in: u64,
    amount_out: u64,
}

public struct PositionStored has copy, drop {
    wallet_id: ID,
    position_id: ID,
}

public struct PositionClosed has copy, drop {
    wallet_id: ID,
}

public fun swap_a_to_b<CoinTypeA, CoinTypeB>(
    wallet: &mut Wallet,
    config: &GlobalConfig,
    pool_obj: &mut Pool<CoinTypeA, CoinTypeB>,
    amount_in: u64,
    min_amount_out: u64,
    sqrt_price_limit: u128,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(amount_in > 0, EZeroAmount);

    let sig = intent::request_swap<CetusAdaptor, CoinTypeA, CoinTypeB>(
        CetusAdaptor {},
        amount_in,
        min_amount_out,
    );
    let (coin_in, wallet_swap_witness) =
        intent::validate_and_swap_out<CetusAdaptor, CoinTypeA, CoinTypeB>(
            wallet,
            sig,
            ctx,
        );
    let mut input_balance = coin::into_balance(coin_in);
    let (flash_a, flash_b, receipt) = pool::flash_swap<CoinTypeA, CoinTypeB>(
        config,
        pool_obj,
        true,
        true,
        amount_in,
        sqrt_price_limit,
        clock,
    );
    balance::join(&mut input_balance, flash_a);
    let pay_amount = pool::swap_pay_amount<CoinTypeA, CoinTypeB>(&receipt);
    assert!(pay_amount <= balance::value(&input_balance), EInsufficientInput);
    let pay_a = balance::split(&mut input_balance, pay_amount);
    let pay_b = balance::zero<CoinTypeB>();
    pool::repay_flash_swap<CoinTypeA, CoinTypeB>(
        config,
        pool_obj,
        pay_a,
        pay_b,
        receipt,
    );

    let coin_out = coin::from_balance(flash_b, ctx);
    let amount_out = coin::value(&coin_out);
    let receipt = intent::create_swap_receipt<CetusAdaptor, CoinTypeA, CoinTypeB>(
        CetusAdaptor {},
        amount_in,
        amount_out,
    );
    intent::verify_swap_and_credit<CetusAdaptor, CoinTypeA, CoinTypeB>(
        wallet,
        wallet_swap_witness,
        receipt,
        coin_out,
    );
    credit_or_destroy_balance<CetusAdaptor, CoinTypeA>(wallet, input_balance, CetusAdaptor {}, ctx);

    event::emit(CetusSwapped {
        a2b: true,
        amount_in,
        amount_out,
    });
}

public fun swap_b_to_a<CoinTypeA, CoinTypeB>(
    wallet: &mut Wallet,
    config: &GlobalConfig,
    pool_obj: &mut Pool<CoinTypeA, CoinTypeB>,
    amount_in: u64,
    min_amount_out: u64,
    sqrt_price_limit: u128,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(amount_in > 0, EZeroAmount);

    let sig = intent::request_swap<CetusAdaptor, CoinTypeB, CoinTypeA>(
        CetusAdaptor {},
        amount_in,
        min_amount_out,
    );
    let (coin_in, wallet_swap_witness) =
        intent::validate_and_swap_out<CetusAdaptor, CoinTypeB, CoinTypeA>(
            wallet,
            sig,
            ctx,
        );
    let mut input_balance = coin::into_balance(coin_in);
    let (flash_a, flash_b, receipt) = pool::flash_swap<CoinTypeA, CoinTypeB>(
        config,
        pool_obj,
        false,
        true,
        amount_in,
        sqrt_price_limit,
        clock,
    );
    balance::join(&mut input_balance, flash_b);
    let pay_amount = pool::swap_pay_amount<CoinTypeA, CoinTypeB>(&receipt);
    assert!(pay_amount <= balance::value(&input_balance), EInsufficientInput);
    let pay_a = balance::zero<CoinTypeA>();
    let pay_b = balance::split(&mut input_balance, pay_amount);
    pool::repay_flash_swap<CoinTypeA, CoinTypeB>(
        config,
        pool_obj,
        pay_a,
        pay_b,
        receipt,
    );

    let coin_out = coin::from_balance(flash_a, ctx);
    let amount_out = coin::value(&coin_out);
    let receipt = intent::create_swap_receipt<CetusAdaptor, CoinTypeB, CoinTypeA>(
        CetusAdaptor {},
        amount_in,
        amount_out,
    );
    intent::verify_swap_and_credit<CetusAdaptor, CoinTypeB, CoinTypeA>(
        wallet,
        wallet_swap_witness,
        receipt,
        coin_out,
    );
    credit_or_destroy_balance<CetusAdaptor, CoinTypeB>(wallet, input_balance, CetusAdaptor {}, ctx);

    event::emit(CetusSwapped {
        a2b: false,
        amount_in,
        amount_out,
    });
}

public fun open_position_from_vault<A, B>(
    wallet: &mut Wallet,
    config: &GlobalConfig,
    pool_obj: &mut Pool<A, B>,
    name: String,
    tick_lower: u32,
    tick_upper: u32,
    max_amount_a: u64,
    max_amount_b: u64,
    fixed_amount: u64,
    fix_amount_a: bool,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert_operator(wallet, ctx);
    let mut position =
        pool::open_position<A, B>(config, pool_obj, tick_lower, tick_upper, ctx);
    add_liquidity_internal<A, B>(
        wallet,
        config,
        pool_obj,
        &mut position,
        max_amount_a,
        max_amount_b,
        fixed_amount,
        fix_amount_a,
        clock,
        ctx,
    );
    let position_id = object::id(&position);
    put_position(wallet, position, name);
    event::emit(PositionStored { wallet_id: wallet::id(wallet), position_id });
}

public fun add_liquidity_from_vault<A, B>(
    wallet: &mut Wallet,
    config: &GlobalConfig,
    pool_obj: &mut Pool<A, B>,
    name: String,
    max_amount_a: u64,
    max_amount_b: u64,
    fixed_amount: u64,
    fix_amount_a: bool,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let mut position = take_position(wallet, clone_string(&name));
    add_liquidity_internal<A, B>(
        wallet,
        config,
        pool_obj,
        &mut position,
        max_amount_a,
        max_amount_b,
        fixed_amount,
        fix_amount_a,
        clock,
        ctx,
    );
    put_position(wallet, position, name);
}

public fun remove_liquidity_to_vault<A, B>(
    wallet: &mut Wallet,
    config: &GlobalConfig,
    pool_obj: &mut Pool<A, B>,
    name: String,
    liquidity_amount: u128,
    min_amount_a: u64,
    min_amount_b: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(liquidity_amount > 0, EZeroLiquidity);
    assert_operator(wallet, ctx);
    let mut position = take_position(wallet, clone_string(&name));
    let (balance_a, balance_b) = pool::remove_liquidity_with_slippage<A, B>(
        config,
        pool_obj,
        &mut position,
        liquidity_amount,
        min_amount_a,
        min_amount_b,
        clock,
    );
    credit_or_destroy_balance<CetusAdaptor, A>(wallet, balance_a, CetusAdaptor {}, ctx);
    credit_or_destroy_balance<CetusAdaptor, B>(wallet, balance_b, CetusAdaptor {}, ctx);
    put_position(wallet, position, name);
}

public fun collect_fees_to_vault<A, B>(
    wallet: &mut Wallet,
    config: &GlobalConfig,
    pool_obj: &mut Pool<A, B>,
    name: String,
    recalculate: bool,
    ctx: &mut TxContext,
) {
    assert_operator(wallet, ctx);
    let position = take_position(wallet, clone_string(&name));
    let (balance_a, balance_b) =
        pool::collect_fee<A, B>(config, pool_obj, &position, recalculate);
    credit_or_destroy_balance<CetusAdaptor, A>(wallet, balance_a, CetusAdaptor {}, ctx);
    credit_or_destroy_balance<CetusAdaptor, B>(wallet, balance_b, CetusAdaptor {}, ctx);
    put_position(wallet, position, name);
}

public fun collect_reward_to_vault<A, B, Reward>(
    wallet: &mut Wallet,
    config: &GlobalConfig,
    pool_obj: &mut Pool<A, B>,
    reward_vault: &mut RewarderGlobalVault,
    name: String,
    recalculate: bool,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert_operator(wallet, ctx);
    let position = take_position(wallet, clone_string(&name));
    let reward = pool::collect_reward<A, B, Reward>(
        config,
        pool_obj,
        &position,
        reward_vault,
        recalculate,
        clock,
    );
    credit_or_destroy_balance<CetusAdaptor, Reward>(wallet, reward, CetusAdaptor {}, ctx);
    put_position(wallet, position, name);
}

public fun close_empty_position<A, B>(
    wallet: &mut Wallet,
    config: &GlobalConfig,
    pool_obj: &mut Pool<A, B>,
    name: String,
    ctx: &mut TxContext,
) {
    assert_operator(wallet, ctx);
    let position = take_position(wallet, name);
    pool::close_position<A, B>(config, pool_obj, position);
    event::emit(PositionClosed { wallet_id: wallet::id(wallet) });
}

fun add_liquidity_internal<A, B>(
    wallet: &mut Wallet,
    config: &GlobalConfig,
    pool_obj: &mut Pool<A, B>,
    position: &mut Position,
    max_amount_a: u64,
    max_amount_b: u64,
    fixed_amount: u64,
    fix_amount_a: bool,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let coin_a = pull_from_vault<A>(wallet, max_amount_a, ctx);
    let coin_b = pull_from_vault<B>(wallet, max_amount_b, ctx);
    let mut balance_a = coin::into_balance(coin_a);
    let mut balance_b = coin::into_balance(coin_b);
    let receipt = pool::add_liquidity_fix_coin<A, B>(
        config,
        pool_obj,
        position,
        fixed_amount,
        fix_amount_a,
        clock,
    );
    let (pay_amount_a, pay_amount_b) = pool::add_liquidity_pay_amount(&receipt);
    assert!(pay_amount_a <= balance::value(&balance_a), EInsufficientInput);
    assert!(pay_amount_b <= balance::value(&balance_b), EInsufficientInput);
    let pay_a = balance::split(&mut balance_a, pay_amount_a);
    let pay_b = balance::split(&mut balance_b, pay_amount_b);
    pool::repay_add_liquidity<A, B>(config, pool_obj, pay_a, pay_b, receipt);
    credit_or_destroy_balance<CetusAdaptor, A>(wallet, balance_a, CetusAdaptor {}, ctx);
    credit_or_destroy_balance<CetusAdaptor, B>(wallet, balance_b, CetusAdaptor {}, ctx);
}

fun pull_from_vault<CoinType>(
    wallet: &mut Wallet,
    amount: u64,
    ctx: &mut TxContext,
): coin::Coin<CoinType> {
    if (amount == 0) return coin::zero<CoinType>(ctx);
    let recipient = wallet::identity(wallet);
    let sig = intent::request_payment<CetusAdaptor, CoinType>(
        CetusAdaptor {},
        amount,
        recipient,
    );
    let (coin_in, witness) =
        intent::validate_and_pay<CetusAdaptor, CoinType>(wallet, sig, ctx);
    let receipt = intent::create_receipt_sig<CetusAdaptor, CoinType>(
        CetusAdaptor {},
        amount,
        recipient,
    );
    intent::verify_and_clear<CetusAdaptor, CoinType>(witness, receipt);
    coin_in
}

fun take_position(wallet: &mut Wallet, name: String): Position {
    wallet::take_asset_for_service<CetusAdaptor, Position>(
        wallet,
        name,
        CetusAdaptor {},
    )
}

fun put_position(wallet: &mut Wallet, position: Position, name: String) {
    wallet::receive_asset_from_service<CetusAdaptor, Position>(
        wallet,
        position,
        name,
        CetusAdaptor {},
    );
}

fun assert_operator(wallet: &Wallet, ctx: &TxContext) {
    let sender = ctx.sender();
    if (sender == wallet::owner(wallet)) return;
    assert!(
        delegate::is_service_authorized<CetusAdaptor>(wallet, sender),
        ENotAuthorized,
    );
}

fun clone_string(value: &String): String {
    string::utf8(*string::as_bytes(value))
}

fun credit_or_destroy_balance<ServiceT: drop, CoinT>(
    wallet: &Wallet,
    balance_in: Balance<CoinT>,
    witness: ServiceT,
    ctx: &mut TxContext,
) {
    if (balance::value(&balance_in) == 0) {
        balance::destroy_zero(balance_in);
    } else {
        let coin = coin::from_balance(balance_in, ctx);
        wallet::receive_from_service<ServiceT, CoinT>(wallet, coin, witness);
    }
}

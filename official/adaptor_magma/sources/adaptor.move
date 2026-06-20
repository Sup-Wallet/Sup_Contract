module adaptor_magma::adaptor;

use std::string::{Self, String};
use SupWallet::delegate;
use SupWallet::intent;
use SupWallet::wallet::{Self, Wallet};
use magma_clmm::config::GlobalConfig;
use magma_clmm::pool::{Self, Pool};
use magma_clmm::position::Position;
use magma_clmm::rewarder::RewarderGlobalVault;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::event;

const ENotAuthorized: u64 = 0;
const EInsufficientInput: u64 = 1;
const EZeroLiquidity: u64 = 2;

public struct MagmaAdaptor has drop {}

public struct PositionStored has copy, drop {
    wallet_id: ID,
    position_id: ID,
}

public struct PositionClosed has copy, drop {
    wallet_id: ID,
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
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(liquidity_amount > 0, EZeroLiquidity);
    assert_operator(wallet, ctx);
    let mut position = take_position(wallet, clone_string(&name));
    let (balance_a, balance_b) = pool::remove_liquidity<A, B>(
        config,
        pool_obj,
        &mut position,
        liquidity_amount,
        clock,
    );
    credit_or_destroy_balance<A>(wallet, balance_a, ctx);
    credit_or_destroy_balance<B>(wallet, balance_b, ctx);
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
    credit_or_destroy_balance<A>(wallet, balance_a, ctx);
    credit_or_destroy_balance<B>(wallet, balance_b, ctx);
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
    credit_or_destroy_balance<Reward>(wallet, reward, ctx);
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
        ctx,
    );
    let (pay_amount_a, pay_amount_b) = pool::add_liquidity_pay_amount(&receipt);
    assert!(pay_amount_a <= balance::value(&balance_a), EInsufficientInput);
    assert!(pay_amount_b <= balance::value(&balance_b), EInsufficientInput);
    let pay_a = balance::split(&mut balance_a, pay_amount_a);
    let pay_b = balance::split(&mut balance_b, pay_amount_b);
    pool::repay_add_liquidity<A, B>(config, pool_obj, pay_a, pay_b, receipt);
    credit_or_destroy_balance<A>(wallet, balance_a, ctx);
    credit_or_destroy_balance<B>(wallet, balance_b, ctx);
}

fun pull_from_vault<CoinType>(
    wallet: &mut Wallet,
    amount: u64,
    ctx: &mut TxContext,
): Coin<CoinType> {
    if (amount == 0) return coin::zero<CoinType>(ctx);
    let recipient = wallet::identity(wallet);
    let sig = intent::request_payment<MagmaAdaptor, CoinType>(
        MagmaAdaptor {},
        amount,
        recipient,
    );
    let (coin_in, witness) =
        intent::validate_and_pay<MagmaAdaptor, CoinType>(wallet, sig, ctx);
    let receipt = intent::create_receipt_sig<MagmaAdaptor, CoinType>(
        MagmaAdaptor {},
        amount,
        recipient,
    );
    intent::verify_and_clear<MagmaAdaptor, CoinType>(witness, receipt);
    coin_in
}

fun take_position(wallet: &mut Wallet, name: String): Position {
    wallet::take_asset_for_service<MagmaAdaptor, Position>(
        wallet,
        name,
        MagmaAdaptor {},
    )
}

fun put_position(wallet: &mut Wallet, position: Position, name: String) {
    wallet::receive_asset_from_service<MagmaAdaptor, Position>(
        wallet,
        position,
        name,
        MagmaAdaptor {},
    );
}

fun credit_or_destroy_balance<CoinType>(
    wallet: &Wallet,
    balance_out: Balance<CoinType>,
    ctx: &mut TxContext,
) {
    if (balance::value(&balance_out) == 0) {
        balance::destroy_zero(balance_out);
    } else {
        wallet::receive_from_service<MagmaAdaptor, CoinType>(
            wallet,
            coin::from_balance(balance_out, ctx),
            MagmaAdaptor {},
        );
    }
}

fun assert_operator(wallet: &Wallet, ctx: &TxContext) {
    let sender = ctx.sender();
    if (sender == wallet::owner(wallet)) return;
    assert!(
        delegate::is_service_authorized<MagmaAdaptor>(wallet, sender),
        ENotAuthorized,
    );
}

fun clone_string(value: &String): String {
    string::utf8(*string::as_bytes(value))
}

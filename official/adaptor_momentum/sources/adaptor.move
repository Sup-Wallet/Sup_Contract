module adaptor_momentum::adaptor;

use std::string::{Self, String};
use SupWallet::delegate;
use SupWallet::intent;
use SupWallet::wallet::{Self, Wallet};
use mmt_v3::collect;
use mmt_v3::i32;
use mmt_v3::liquidity;
use mmt_v3::pool::Pool;
use mmt_v3::position::Position;
use mmt_v3::version::Version;
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::event;

const ENotAuthorized: u64 = 0;
const EZeroLiquidity: u64 = 1;

public struct MomentumAdaptor has drop {}

public struct PositionStored has copy, drop {
    wallet_id: ID,
    position_id: ID,
}

public struct PositionClosed has copy, drop {
    wallet_id: ID,
}

public fun open_position_from_vault<X, Y>(
    wallet: &mut Wallet,
    pool: &mut Pool<X, Y>,
    version: &Version,
    name: String,
    tick_lower_abs: u32,
    tick_lower_negative: bool,
    tick_upper_abs: u32,
    tick_upper_negative: bool,
    max_amount_x: u64,
    max_amount_y: u64,
    min_amount_x: u64,
    min_amount_y: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert_operator(wallet, ctx);
    let lower = if (tick_lower_negative) {
        i32::neg_from(tick_lower_abs)
    } else {
        i32::from_u32(tick_lower_abs)
    };
    let upper = if (tick_upper_negative) {
        i32::neg_from(tick_upper_abs)
    } else {
        i32::from_u32(tick_upper_abs)
    };
    let mut position = liquidity::open_position<X, Y>(pool, lower, upper, version, ctx);
    add_liquidity_internal<X, Y>(
        wallet,
        pool,
        &mut position,
        version,
        max_amount_x,
        max_amount_y,
        min_amount_x,
        min_amount_y,
        clock,
        ctx,
    );
    let position_id = object::id(&position);
    put_position(wallet, position, name);
    event::emit(PositionStored { wallet_id: wallet::id(wallet), position_id });
}

public fun add_liquidity_from_vault<X, Y>(
    wallet: &mut Wallet,
    pool: &mut Pool<X, Y>,
    version: &Version,
    name: String,
    max_amount_x: u64,
    max_amount_y: u64,
    min_amount_x: u64,
    min_amount_y: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let mut position = take_position(wallet, clone_string(&name));
    add_liquidity_internal<X, Y>(
        wallet,
        pool,
        &mut position,
        version,
        max_amount_x,
        max_amount_y,
        min_amount_x,
        min_amount_y,
        clock,
        ctx,
    );
    put_position(wallet, position, name);
}

public fun remove_liquidity_to_vault<X, Y>(
    wallet: &mut Wallet,
    pool: &mut Pool<X, Y>,
    version: &Version,
    name: String,
    liquidity_amount: u128,
    min_amount_x: u64,
    min_amount_y: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(liquidity_amount > 0, EZeroLiquidity);
    assert_operator(wallet, ctx);
    let mut position = take_position(wallet, clone_string(&name));
    let (coin_x, coin_y) = liquidity::remove_liquidity<X, Y>(
        pool,
        &mut position,
        liquidity_amount,
        min_amount_x,
        min_amount_y,
        clock,
        version,
        ctx,
    );
    credit_or_destroy<X>(wallet, coin_x);
    credit_or_destroy<Y>(wallet, coin_y);
    put_position(wallet, position, name);
}

public fun collect_fees_to_vault<X, Y>(
    wallet: &mut Wallet,
    pool: &mut Pool<X, Y>,
    version: &Version,
    name: String,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert_operator(wallet, ctx);
    let mut position = take_position(wallet, clone_string(&name));
    let (coin_x, coin_y) = collect::fee<X, Y>(pool, &mut position, clock, version, ctx);
    credit_or_destroy<X>(wallet, coin_x);
    credit_or_destroy<Y>(wallet, coin_y);
    put_position(wallet, position, name);
}

public fun collect_reward_to_vault<X, Y, Reward>(
    wallet: &mut Wallet,
    pool: &mut Pool<X, Y>,
    version: &Version,
    name: String,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert_operator(wallet, ctx);
    let mut position = take_position(wallet, clone_string(&name));
    let reward = collect::reward<X, Y, Reward>(pool, &mut position, clock, version, ctx);
    credit_or_destroy<Reward>(wallet, reward);
    put_position(wallet, position, name);
}

public fun close_empty_position(
    wallet: &mut Wallet,
    version: &Version,
    name: String,
    ctx: &mut TxContext,
) {
    assert_operator(wallet, ctx);
    let position = take_position(wallet, name);
    liquidity::close_position(position, version, ctx);
    event::emit(PositionClosed { wallet_id: wallet::id(wallet) });
}

fun add_liquidity_internal<X, Y>(
    wallet: &mut Wallet,
    pool: &mut Pool<X, Y>,
    position: &mut Position,
    version: &Version,
    max_amount_x: u64,
    max_amount_y: u64,
    min_amount_x: u64,
    min_amount_y: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let coin_x = pull_from_vault<X>(wallet, max_amount_x, ctx);
    let coin_y = pull_from_vault<Y>(wallet, max_amount_y, ctx);
    let (refund_x, refund_y) = liquidity::add_liquidity<X, Y>(
        pool,
        position,
        coin_x,
        coin_y,
        min_amount_x,
        min_amount_y,
        clock,
        version,
        ctx,
    );
    credit_or_destroy<X>(wallet, refund_x);
    credit_or_destroy<Y>(wallet, refund_y);
}

fun pull_from_vault<CoinType>(
    wallet: &mut Wallet,
    amount: u64,
    ctx: &mut TxContext,
): Coin<CoinType> {
    if (amount == 0) return coin::zero<CoinType>(ctx);
    let recipient = wallet::identity(wallet);
    let sig = intent::request_payment<MomentumAdaptor, CoinType>(
        MomentumAdaptor {},
        amount,
        recipient,
    );
    let (coin_in, witness) =
        intent::validate_and_pay<MomentumAdaptor, CoinType>(wallet, sig, ctx);
    let receipt = intent::create_receipt_sig<MomentumAdaptor, CoinType>(
        MomentumAdaptor {},
        amount,
        recipient,
    );
    intent::verify_and_clear<MomentumAdaptor, CoinType>(witness, receipt);
    coin_in
}

fun take_position(wallet: &mut Wallet, name: String): Position {
    wallet::take_asset_for_service<MomentumAdaptor, Position>(
        wallet,
        name,
        MomentumAdaptor {},
    )
}

fun put_position(wallet: &mut Wallet, position: Position, name: String) {
    wallet::receive_asset_from_service<MomentumAdaptor, Position>(
        wallet,
        position,
        name,
        MomentumAdaptor {},
    );
}

fun credit_or_destroy<CoinType>(wallet: &Wallet, coin_out: Coin<CoinType>) {
    if (coin::value(&coin_out) == 0) {
        coin::destroy_zero(coin_out);
    } else {
        wallet::receive_from_service<MomentumAdaptor, CoinType>(
            wallet,
            coin_out,
            MomentumAdaptor {},
        );
    }
}

fun assert_operator(wallet: &Wallet, ctx: &TxContext) {
    let sender = ctx.sender();
    if (sender == wallet::owner(wallet)) return;
    assert!(
        delegate::is_service_authorized<MomentumAdaptor>(wallet, sender),
        ENotAuthorized,
    );
}

fun clone_string(value: &String): String {
    string::utf8(*string::as_bytes(value))
}

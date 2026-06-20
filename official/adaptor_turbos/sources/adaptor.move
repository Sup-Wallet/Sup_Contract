module adaptor_turbos::adaptor;

use std::string::{Self, String};
use SupWallet::delegate;
use SupWallet::intent;
use SupWallet::wallet::{Self, Wallet};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::event;
use turbos_clmm::pool::{Pool, PoolRewardVault, Versioned};
use turbos_clmm::position_manager::{Self, Positions};
use turbos_clmm::position_nft::TurbosPositionNFT;

const ENotAuthorized: u64 = 0;
const EZeroLiquidity: u64 = 1;

public struct TurbosAdaptor has drop {}

public struct PositionStored has copy, drop {
    wallet_id: ID,
    position_id: ID,
}

public struct PositionClosed has copy, drop {
    wallet_id: ID,
}

public fun open_position_from_vault<A, B, Fee>(
    wallet: &mut Wallet,
    pool: &mut Pool<A, B, Fee>,
    positions: &mut Positions,
    versioned: &Versioned,
    name: String,
    tick_lower_abs: u32,
    tick_lower_negative: bool,
    tick_upper_abs: u32,
    tick_upper_negative: bool,
    amount_a_desired: u64,
    amount_b_desired: u64,
    amount_a_min: u64,
    amount_b_min: u64,
    deadline_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert_operator(wallet, ctx);
    let coin_a = pull_from_vault<A>(wallet, amount_a_desired, ctx);
    let coin_b = pull_from_vault<B>(wallet, amount_b_desired, ctx);
    let (position, refund_a, refund_b) =
        position_manager::mint_with_return_<A, B, Fee>(
            pool,
            positions,
            vector[coin_a],
            vector[coin_b],
            tick_lower_abs,
            tick_lower_negative,
            tick_upper_abs,
            tick_upper_negative,
            amount_a_desired,
            amount_b_desired,
            amount_a_min,
            amount_b_min,
            deadline_ms,
            clock,
            versioned,
            ctx,
        );
    credit_or_destroy<A>(wallet, refund_a);
    credit_or_destroy<B>(wallet, refund_b);
    let position_id = object::id(&position);
    put_position(wallet, position, name);
    event::emit(PositionStored { wallet_id: wallet::id(wallet), position_id });
}

public fun add_liquidity_from_vault<A, B, Fee>(
    wallet: &mut Wallet,
    pool: &mut Pool<A, B, Fee>,
    positions: &mut Positions,
    versioned: &Versioned,
    name: String,
    amount_a_desired: u64,
    amount_b_desired: u64,
    amount_a_min: u64,
    amount_b_min: u64,
    deadline_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert_operator(wallet, ctx);
    let mut position = take_position(wallet, clone_string(&name));
    let coin_a = pull_from_vault<A>(wallet, amount_a_desired, ctx);
    let coin_b = pull_from_vault<B>(wallet, amount_b_desired, ctx);
    let (refund_a, refund_b) =
        position_manager::increase_liquidity_with_return_<A, B, Fee>(
            pool,
            positions,
            vector[coin_a],
            vector[coin_b],
            &mut position,
            amount_a_desired,
            amount_b_desired,
            amount_a_min,
            amount_b_min,
            deadline_ms,
            clock,
            versioned,
            ctx,
        );
    credit_or_destroy<A>(wallet, refund_a);
    credit_or_destroy<B>(wallet, refund_b);
    put_position(wallet, position, name);
}

public fun remove_liquidity_to_vault<A, B, Fee>(
    wallet: &mut Wallet,
    pool: &mut Pool<A, B, Fee>,
    positions: &mut Positions,
    versioned: &Versioned,
    name: String,
    liquidity_amount: u128,
    amount_a_min: u64,
    amount_b_min: u64,
    deadline_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(liquidity_amount > 0, EZeroLiquidity);
    assert_operator(wallet, ctx);
    let mut position = take_position(wallet, clone_string(&name));
    let (coin_a, coin_b) =
        position_manager::decrease_liquidity_with_return_<A, B, Fee>(
            pool,
            positions,
            &mut position,
            liquidity_amount,
            amount_a_min,
            amount_b_min,
            deadline_ms,
            clock,
            versioned,
            ctx,
        );
    credit_or_destroy<A>(wallet, coin_a);
    credit_or_destroy<B>(wallet, coin_b);
    put_position(wallet, position, name);
}

public fun collect_fees_to_vault<A, B, Fee>(
    wallet: &mut Wallet,
    pool: &mut Pool<A, B, Fee>,
    positions: &mut Positions,
    versioned: &Versioned,
    name: String,
    amount_a_max: u64,
    amount_b_max: u64,
    deadline_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert_operator(wallet, ctx);
    let mut position = take_position(wallet, clone_string(&name));
    let recipient = wallet::identity(wallet);
    let (coin_a, coin_b) = position_manager::collect_with_return_<A, B, Fee>(
        pool,
        positions,
        &mut position,
        amount_a_max,
        amount_b_max,
        recipient,
        deadline_ms,
        clock,
        versioned,
        ctx,
    );
    credit_or_destroy<A>(wallet, coin_a);
    credit_or_destroy<B>(wallet, coin_b);
    put_position(wallet, position, name);
}

public fun collect_reward_to_vault<A, B, Fee, Reward>(
    wallet: &mut Wallet,
    pool: &mut Pool<A, B, Fee>,
    positions: &mut Positions,
    reward_vault: &mut PoolRewardVault<Reward>,
    versioned: &Versioned,
    name: String,
    reward_index: u64,
    amount_max: u64,
    deadline_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert_operator(wallet, ctx);
    let mut position = take_position(wallet, clone_string(&name));
    let recipient = wallet::identity(wallet);
    let reward = position_manager::collect_reward_with_return_<A, B, Fee, Reward>(
        pool,
        positions,
        &mut position,
        reward_vault,
        reward_index,
        amount_max,
        recipient,
        deadline_ms,
        clock,
        versioned,
        ctx,
    );
    credit_or_destroy<Reward>(wallet, reward);
    put_position(wallet, position, name);
}

public fun close_empty_position<A, B, Fee>(
    wallet: &mut Wallet,
    positions: &mut Positions,
    versioned: &Versioned,
    name: String,
    ctx: &mut TxContext,
) {
    assert_operator(wallet, ctx);
    let position = take_position(wallet, name);
    position_manager::burn<A, B, Fee>(positions, position, versioned, ctx);
    event::emit(PositionClosed { wallet_id: wallet::id(wallet) });
}

fun pull_from_vault<CoinType>(
    wallet: &mut Wallet,
    amount: u64,
    ctx: &mut TxContext,
): Coin<CoinType> {
    if (amount == 0) return coin::zero<CoinType>(ctx);
    let recipient = wallet::identity(wallet);
    let sig = intent::request_payment<TurbosAdaptor, CoinType>(
        TurbosAdaptor {},
        amount,
        recipient,
    );
    let (coin_in, witness) =
        intent::validate_and_pay<TurbosAdaptor, CoinType>(wallet, sig, ctx);
    let receipt = intent::create_receipt_sig<TurbosAdaptor, CoinType>(
        TurbosAdaptor {},
        amount,
        recipient,
    );
    intent::verify_and_clear<TurbosAdaptor, CoinType>(witness, receipt);
    coin_in
}

fun take_position(wallet: &mut Wallet, name: String): TurbosPositionNFT {
    wallet::take_asset_for_service<TurbosAdaptor, TurbosPositionNFT>(
        wallet,
        name,
        TurbosAdaptor {},
    )
}

fun put_position(wallet: &mut Wallet, position: TurbosPositionNFT, name: String) {
    wallet::receive_asset_from_service<TurbosAdaptor, TurbosPositionNFT>(
        wallet,
        position,
        name,
        TurbosAdaptor {},
    );
}

fun credit_or_destroy<CoinType>(wallet: &Wallet, coin_out: Coin<CoinType>) {
    if (coin::value(&coin_out) == 0) {
        coin::destroy_zero(coin_out);
    } else {
        wallet::receive_from_service<TurbosAdaptor, CoinType>(
            wallet,
            coin_out,
            TurbosAdaptor {},
        );
    }
}

fun assert_operator(wallet: &Wallet, ctx: &TxContext) {
    let sender = ctx.sender();
    if (sender == wallet::owner(wallet)) return;
    assert!(
        delegate::is_service_authorized<TurbosAdaptor>(wallet, sender),
        ENotAuthorized,
    );
}

fun clone_string(value: &String): String {
    string::utf8(*string::as_bytes(value))
}

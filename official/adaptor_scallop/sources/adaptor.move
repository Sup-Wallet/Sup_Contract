module adaptor_scallop::adaptor;

use SupWallet::intent;
use SupWallet::wallet::Wallet;
use scallop_protocol::market::Market;
use scallop_protocol::mint;
use scallop_protocol::redeem;
use scallop_protocol::version::Version;
use scallop_scoin::s_coin_converter::{Self, SCoinTreasury};
use sui::clock::Clock;
use sui::coin;
use sui::event;

const EZeroAmount: u64 = 0;

/// Service witness. Users must grant this adaptor on each input coin type:
/// underlying coins for `deposit`, sCoins for `withdraw`.
public struct ScallopAdaptor has drop {}

public struct Deposited has copy, drop {
    amount_in: u64,
    amount_out: u64,
}

public struct Withdrawn has copy, drop {
    amount_in: u64,
    amount_out: u64,
}

public fun deposit<Underlying, SCoin>(
    wallet: &mut Wallet,
    version: &Version,
    market: &mut Market,
    treasury: &mut SCoinTreasury<SCoin, Underlying>,
    amount_in: u64,
    min_scoin_out: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(amount_in > 0, EZeroAmount);

    let sig = intent::request_swap<ScallopAdaptor, Underlying, SCoin>(
        ScallopAdaptor {},
        amount_in,
        min_scoin_out,
    );
    let (coin_in, wallet_swap_witness) =
        intent::validate_and_swap_out<ScallopAdaptor, Underlying, SCoin>(
            wallet,
            sig,
            ctx,
        );

    let market_coin = mint::mint<Underlying>(version, market, coin_in, clock, ctx);
    let s_coin = s_coin_converter::mint_s_coin<SCoin, Underlying>(
        treasury,
        market_coin,
        ctx,
    );
    let amount_out = coin::value(&s_coin);
    let receipt = intent::create_swap_receipt<ScallopAdaptor, Underlying, SCoin>(
        ScallopAdaptor {},
        amount_in,
        amount_out,
    );

    intent::verify_swap_and_credit<ScallopAdaptor, Underlying, SCoin>(
        wallet,
        wallet_swap_witness,
        receipt,
        s_coin,
    );
    event::emit(Deposited { amount_in, amount_out });
}

public fun withdraw<SCoin, Underlying>(
    wallet: &mut Wallet,
    version: &Version,
    market: &mut Market,
    treasury: &mut SCoinTreasury<SCoin, Underlying>,
    amount_in: u64,
    min_underlying_out: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(amount_in > 0, EZeroAmount);

    let sig = intent::request_swap<ScallopAdaptor, SCoin, Underlying>(
        ScallopAdaptor {},
        amount_in,
        min_underlying_out,
    );
    let (s_coin, wallet_swap_witness) =
        intent::validate_and_swap_out<ScallopAdaptor, SCoin, Underlying>(
            wallet,
            sig,
            ctx,
        );

    let market_coin = s_coin_converter::burn_s_coin<SCoin, Underlying>(
        treasury,
        s_coin,
        ctx,
    );
    let coin_out = redeem::redeem<Underlying>(version, market, market_coin, clock, ctx);
    let amount_out = coin::value(&coin_out);
    let receipt = intent::create_swap_receipt<ScallopAdaptor, SCoin, Underlying>(
        ScallopAdaptor {},
        amount_in,
        amount_out,
    );

    intent::verify_swap_and_credit<ScallopAdaptor, SCoin, Underlying>(
        wallet,
        wallet_swap_witness,
        receipt,
        coin_out,
    );
    event::emit(Withdrawn { amount_in, amount_out });
}

#[test_only]
public fun zero_amount_error(): u64 {
    EZeroAmount
}

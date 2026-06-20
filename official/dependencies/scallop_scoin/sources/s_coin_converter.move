module scallop_scoin::s_coin_converter;

use scallop_protocol::reserve::MarketCoin;
use sui::coin::Coin;

public struct SCoinTreasury<phantom SCoin, phantom Underlying> has key {
    id: UID,
}

public fun mint_s_coin<SCoin, Underlying>(
    _treasury: &mut SCoinTreasury<SCoin, Underlying>,
    _market_coin: Coin<MarketCoin<Underlying>>,
    _ctx: &mut TxContext,
): Coin<SCoin> {
    abort 0
}

public fun burn_s_coin<SCoin, Underlying>(
    _treasury: &mut SCoinTreasury<SCoin, Underlying>,
    _s_coin: Coin<SCoin>,
    _ctx: &mut TxContext,
): Coin<MarketCoin<Underlying>> {
    abort 0
}

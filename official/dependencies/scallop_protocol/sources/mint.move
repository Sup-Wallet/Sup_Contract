module scallop_protocol::mint;

use scallop_protocol::market::Market;
use scallop_protocol::reserve::MarketCoin;
use scallop_protocol::version::Version;
use sui::clock::Clock;
use sui::coin::Coin;

public fun mint<T>(
    _version: &Version,
    _market: &mut Market,
    _coin: Coin<T>,
    _clock: &Clock,
    _ctx: &mut TxContext,
): Coin<MarketCoin<T>> {
    abort 0
}

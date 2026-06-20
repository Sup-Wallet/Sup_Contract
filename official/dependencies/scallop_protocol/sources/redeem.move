module scallop_protocol::redeem;

use scallop_protocol::market::Market;
use scallop_protocol::reserve::MarketCoin;
use scallop_protocol::version::Version;
use sui::clock::Clock;
use sui::coin::Coin;

public fun redeem<T>(
    _version: &Version,
    _market: &mut Market,
    _coin: Coin<MarketCoin<T>>,
    _clock: &Clock,
    _ctx: &mut TxContext,
): Coin<T> {
    abort 0
}

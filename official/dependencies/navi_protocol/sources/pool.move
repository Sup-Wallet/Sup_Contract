module navi_protocol::pool;

use sui::balance::Balance;

public struct Pool<phantom T> has key, store {
    id: UID,
    balance: Balance<T>,
    treasury_balance: Balance<T>,
    decimal: u8,
}

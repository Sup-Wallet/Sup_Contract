module navi_oracle::oracle;

use sui::table::Table;

public struct PriceOracle has key {
    id: UID,
    version: u64,
    update_interval: u64,
    price_oracles: Table<u8, Price>,
}

public struct Price has store {
    value: u256,
    decimal: u8,
    timestamp: u64,
}

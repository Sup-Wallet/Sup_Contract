module navi_protocol::storage;

use std::ascii::String;
use sui::table::Table;

public struct Storage has key, store {
    id: UID,
    version: u64,
    paused: bool,
    reserves: Table<u8, ReserveData>,
    reserves_count: u8,
    users: vector<address>,
    user_info: Table<address, UserInfo>,
}

public struct ReserveData has store {
    id: u8,
    oracle_id: u8,
    coin_type: String,
    is_isolated: bool,
    supply_cap_ceiling: u256,
    borrow_cap_ceiling: u256,
    current_supply_rate: u256,
    current_borrow_rate: u256,
    current_supply_index: u256,
    current_borrow_index: u256,
    supply_balance: TokenBalance,
    borrow_balance: TokenBalance,
    last_update_timestamp: u64,
    ltv: u256,
    treasury_factor: u256,
    treasury_balance: u256,
    borrow_rate_factors: BorrowRateFactors,
    liquidation_factors: LiquidationFactors,
    reserve_field_a: u256,
    reserve_field_b: u256,
    reserve_field_c: u256,
}

public struct UserInfo has store {
    collaterals: vector<u8>,
    loans: vector<u8>,
}

public struct ReserveConfigurationMap has copy, store {
    data: u256,
}

public struct UserConfigurationMap has copy, store {
    data: u256,
}

public struct TokenBalance has store {
    user_state: Table<address, u256>,
    total_supply: u256,
}

public struct BorrowRateFactors has store {
    base_rate: u256,
    multiplier: u256,
    jump_rate_multiplier: u256,
    reserve_factor: u256,
    optimal_utilization: u256,
}

public struct LiquidationFactors has store {
    ratio: u256,
    bonus: u256,
    threshold: u256,
}

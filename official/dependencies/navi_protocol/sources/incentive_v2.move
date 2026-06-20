module navi_protocol::incentive_v2;

use std::type_name::TypeName;
use sui::balance::Balance;
use sui::table::Table;

public struct Incentive has key, store {
    id: UID,
    version: u64,
    pool_objs: vector<address>,
    inactive_objs: vector<address>,
    pools: Table<address, IncentivePool>,
    funds: Table<address, IncentiveFundsPoolInfo>,
}

public struct IncentivePool has key, store {
    id: UID,
    phase: u64,
    funds: address,
    start_at: u64,
    end_at: u64,
    closed_at: u64,
    total_supply: u64,
    option: u8,
    asset_id: u8,
    factor: u256,
    last_update_at: u64,
    distributed: u64,
    index_reward: u256,
    index_rewards_paids: Table<address, u256>,
    total_rewards_of_users: Table<address, u256>,
    total_claimed_of_users: Table<address, u256>,
}

public struct IncentiveFundsPool<phantom CoinType> has key, store {
    id: UID,
    oracle_id: u8,
    balance: Balance<CoinType>,
    coin_type: TypeName,
}

public struct IncentiveFundsPoolInfo has key, store {
    id: UID,
    oracle_id: u8,
    coin_type: TypeName,
}

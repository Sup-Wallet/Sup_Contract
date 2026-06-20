module navi_protocol::incentive_v3;

use std::ascii::String;
use navi_oracle::oracle::PriceOracle;
use navi_protocol::account::AccountCap;
use navi_protocol::incentive_v2;
use navi_protocol::pool::Pool;
use navi_protocol::storage::Storage;
use sui::balance::Balance;
use sui::bag::Bag;
use sui::clock::Clock;
use sui::coin::Coin;
use sui::table::Table;
use sui::vec_map::VecMap;
use sui_system::sui_system::SuiSystemState;

public struct Incentive has key, store {
    id: UID,
    version: u64,
    pools: VecMap<String, AssetPool>,
    borrow_fee_rate: u64,
    fee_balance: Bag,
}

public struct AssetPool has key, store {
    id: UID,
    asset: u8,
    asset_coin_type: String,
    rules: VecMap<address, Rule>,
}

public struct Rule has key, store {
    id: UID,
    option: u8,
    enable: bool,
    reward_coin_type: String,
    rate: u256,
    max_rate: u256,
    last_update_at: u64,
    global_index: u256,
    user_index: Table<address, u256>,
    user_total_rewards: Table<address, u256>,
    user_rewards_claimed: Table<address, u256>,
}

public struct RewardFund<phantom CoinType> has key, store {
    id: UID,
    balance: Balance<CoinType>,
    coin_type: String,
}

public fun deposit_with_account_cap<T>(
    _clock: &Clock,
    _storage: &mut Storage,
    _pool: &mut Pool<T>,
    _asset_id: u8,
    _coin: Coin<T>,
    _incentive_v2: &mut incentive_v2::Incentive,
    _incentive_v3: &mut Incentive,
    _account_cap: &AccountCap,
) {
    abort 0
}

public fun withdraw_with_account_cap_v2<T>(
    _clock: &Clock,
    _oracle: &PriceOracle,
    _storage: &mut Storage,
    _pool: &mut Pool<T>,
    _asset_id: u8,
    _amount: u64,
    _incentive_v2: &mut incentive_v2::Incentive,
    _incentive_v3: &mut Incentive,
    _account_cap: &AccountCap,
    _system_state: &mut SuiSystemState,
    _ctx: &mut TxContext,
): Balance<T> {
    abort 0
}

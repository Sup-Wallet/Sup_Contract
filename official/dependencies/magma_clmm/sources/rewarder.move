module magma_clmm::rewarder {
    use integer_mate::full_math_u128;
    use magma_clmm::config;
    use std::type_name;
    use sui::{bag, balance::{Self, Balance}, event};

    const ErrSlotIsFull: u64 = 1;
    const ErrRewardAlreadyExist: u64 = 2;
    const ErrInvalidTime: u64 = 3;
    const ErrRewardAmountInsufficient: u64 = 4;
    const ErrRewardNotExist: u64 = 5;

    const Q64_SCALE: u128 = 18446744073709551616000000;

    public struct RewarderManager has store {
        rewarders: vector<Rewarder>,
        points_released: u128,
        points_growth_global: u128,
        last_updated_time: u64,
    }

    public struct Rewarder has copy, drop, store {
        reward_coin: type_name::TypeName,
        emissions_per_second: u128,
        growth_global: u128,
    }

    public struct RewarderGlobalVault has key, store {
        id: UID,
        balances: bag::Bag,
    }

    public struct RewarderInitEvent has copy, drop {
        global_vault_id: ID,
    }

    public struct DepositEvent has copy, drop, store {
        reward_type: type_name::TypeName,
        deposit_amount: u64,
        after_amount: u64,
    }

    public struct EmergentWithdrawEvent has copy, drop, store {
        reward_type: type_name::TypeName,
        withdraw_amount: u64,
        after_amount: u64,
    }

    public fun balance_of<RewardType>(_vault: &RewarderGlobalVault): u64 {
        abort (0)
    }

    public fun balances(_vault: &RewarderGlobalVault): &bag::Bag {
        abort (0)
    }

    public fun borrow_rewarder<RewardType>(_reward_manager: &RewarderManager): &Rewarder {
        abort (0)
    }

    public fun deposit_reward<RewardType>(
        _cfg: &config::GlobalConfig,
        _vault: &mut RewarderGlobalVault,
        _deposit: Balance<RewardType>,
    ): u64 {
        abort (0)
    }

    public fun emergent_withdraw<RewardType>(
        _admin_cap: &config::AdminCap,
        _cfg: &config::GlobalConfig,
        _vault: &mut RewarderGlobalVault,
        _amount: u64,
    ): Balance<RewardType> {
        abort (0)
    }

    public fun emissions_per_second(_rewarder: &Rewarder): u128 {
        abort (0)
    }

    public fun growth_global(_rewarder: &Rewarder): u128 {
        abort (0)
    }

    public fun last_update_time(_reward_manager: &RewarderManager): u64 {
        abort (0)
    }

    public fun points_growth_global(_reward_manager: &RewarderManager): u128 {
        abort (0)
    }

    public fun points_released(_reward_manager: &RewarderManager): u128 {
        abort (0)
    }

    public fun reward_coin(_reward_manager: &Rewarder): type_name::TypeName {
        abort (0)
    }

    public fun rewarder_index<RewardType>(_reward_manager: &RewarderManager): option::Option<u64> {
        abort (0)
    }

    public fun rewarders(_reward_manager: &RewarderManager): vector<Rewarder> {
        abort (0)
    }

    public fun rewards_growth_global(_reward_manager: &RewarderManager): vector<u128> {
        abort (0)
    }
}

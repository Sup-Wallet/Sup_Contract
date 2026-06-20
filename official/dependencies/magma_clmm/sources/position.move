#[allow(unused_const)]

module magma_clmm::position {
    use integer_mate::{full_math_u128, i32::{Self, I32}, math_u128, math_u64};
    use magma_clmm::{config, tick_math, utils};
    use move_stl::linked_table;
    use std::{string::{Self, String}, type_name};
    use sui::{display, event, package};

    const ErrRemainderAmountUnderflow: u64 = 1;
    const ErrFeeOwnedOverflow: u64 = 2;
    const ErrPointsOwnedOverflow: u64 = 3;
    const ErrInvalidDeltaLiquidity: u64 = 4;
    const ErrInvalidPositionTickRange: u64 = 5;
    const ErrPositionNotExists: u64 = 6;
    const ErrPositionIsNotEmpty: u64 = 7;
    const ErrLiquidityChangeOverflow: u64 = 8;
    const ErrLiquidityChangeUnderflow: u64 = 9;
    const ErrInvalidRewardIndex: u64 = 10;
    const ErrPositionStaked: u64 = 11;

    public struct StakePositionEvent has copy, drop {
        position_id: ID,
        staked: bool,
    }

    public struct PositionManager has store {
        tick_spacing: u32,
        position_index: u64,
        positions: linked_table::LinkedTable<ID, PositionInfo>,
    }

    public struct POSITION has drop {}

    public struct Position has key, store {
        id: UID,
        pool: ID,
        index: u64,
        coin_type_a: type_name::TypeName,
        coin_type_b: type_name::TypeName,
        name: String,
        description: String,
        url: String,
        tick_lower_index: I32,
        tick_upper_index: I32,
        liquidity: u128,
    }

    public struct PositionInfo has copy, drop, store {
        position_id: ID,
        liquidity: u128,
        tick_lower_index: I32,
        tick_upper_index: I32,
        fee_growth_inside_a: u128,
        fee_growth_inside_b: u128,
        fee_owned_a: u64,
        fee_owned_b: u64,
        points_owned: u128,
        points_growth_inside: u128,
        rewards: vector<PositionReward>,
        magma_distribution_staked: bool,
        magma_distribution_growth_inside: u128,
        magma_distribution_owned: u64,
    }

    public struct PositionReward has copy, drop, store {
        growth_inside: u128,
        amount_owned: u64,
    }

    public fun is_empty(_position_info: &PositionInfo): bool {
        abort (0)
    }

    public fun borrow_position_info(
        _position_manager: &PositionManager,
        _position_id: ID,
    ): &PositionInfo {
        abort (0)
    }

    public fun check_position_tick_range(
        _tick_lower_index: I32,
        _tick_upper_index: I32,
        _tick_spacing: u32,
    ) {
        abort (0)
    }

    public fun description(_position: &Position): String {
        abort (0)
    }

    public fun fetch_positions(
        _position_manager: &PositionManager,
        _start: vector<ID>,
        _limit: u64,
    ): vector<PositionInfo> {
        abort (0)
    }

    public fun index(_position: &Position): u64 {
        abort (0)
    }

    public fun info_fee_growth_inside(_position_info: &PositionInfo): (u128, u128) {
        abort (0)
    }

    public fun info_fee_owned(_position_info: &PositionInfo): (u64, u64) {
        abort (0)
    }

    public fun info_liquidity(_position_info: &PositionInfo): u128 {
        abort (0)
    }

    public fun info_points_growth_inside(_position_info: &PositionInfo): u128 {
        abort (0)
    }

    public fun info_points_owned(_position_info: &PositionInfo): u128 {
        abort (0)
    }

    public fun info_position_id(_position_info: &PositionInfo): ID {
        abort (0)
    }

    public fun info_rewards(_position_info: &PositionInfo): &vector<PositionReward> {
        abort (0)
    }

    public fun info_tick_range(_position_info: &PositionInfo): (I32, I32) {
        abort (0)
    }

    public fun info_magma_distribution_owned(_position_info: &PositionInfo): u64 {
        abort (0)
    }

    public fun inited_rewards_count(_position_manager: &PositionManager, _position_id: ID): u64 {
        abort (0)
    }

    public fun is_position_exist(_position_manager: &PositionManager, _position_id: ID): bool {
        abort (0)
    }

    public fun liquidity(_position: &Position): u128 {
        abort (0)
    }

    public fun name(_position: &Position): String {
        abort (0)
    }

    public fun pool_id(_position: &Position): ID {
        abort (0)
    }

    public fun set_description(_position: &mut Position, _desc: String) {
        abort (0)
    }

    public fun reward_amount_owned(_position_reward: &PositionReward): u64 {
        abort (0)
    }

    public fun reward_growth_inside(_position_reward: &PositionReward): u128 {
        abort (0)
    }

    #[allow(lint(self_transfer))]
    public fun set_display(
        _cfg: &config::GlobalConfig,
        _publisher: &package::Publisher,
        _description: String,
        _link: String,
        _project_url: String,
        _creator: String,
        _ctx: &mut TxContext,
    ) {
        abort (0)
    }

    public fun tick_range(_position: &Position): (I32, I32) {
        abort (0)
    }

    public fun url(_position: &Position): String {
        abort (0)
    }

    public fun is_staked(_info: &PositionInfo): bool {
        abort (0)
    }
}

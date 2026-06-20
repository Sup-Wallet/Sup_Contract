module magma_clmm::tick {
    use integer_mate::{i128::{Self, I128}, i32::{Self, I32}, math_u128};
    use magma_clmm::tick_math;
    use move_stl::{option_u64, skip_list};

    const ErrLiquidityOverflow: u64 = 0;
    const ErrLiquidityUnderflow: u64 = 1;
    const ErrInvalidTick: u64 = 2;
    const ErrTickNotFound: u64 = 3;

    public struct TickManager has store {
        tick_spacing: u32,
        ticks: skip_list::SkipList<Tick>,
    }

    public struct Tick has copy, drop, store {
        index: I32,
        sqrt_price: u128,
        liquidity_net: I128,
        liquidity_gross: u128,
        fee_growth_outside_a: u128,
        fee_growth_outside_b: u128,
        points_growth_outside: u128,
        rewards_growth_outside: vector<u128>,
        magma_distribution_staked_liquidity_net: I128,
        magma_distribution_growth_outside: u128,
    }

    public fun borrow_tick(_tick_manager: &TickManager, _tick_index: I32): &Tick {
        abort (0)
    }

    public fun borrow_tick_for_swap(
        _tick_manager: &TickManager,
        _score: u64,
        _a2b: bool,
    ): (&Tick, option_u64::OptionU64) {
        abort (0)
    }

    public fun fee_growth_outside(_tick: &Tick): (u128, u128) {
        abort (0)
    }

    public fun fetch_ticks(
        _tick_manager: &TickManager,
        _start: vector<u32>,
        _limit: u64,
    ): vector<Tick> {
        abort (0)
    }

    public fun first_score_for_swap(
        _tick_manager: &TickManager,
        _tick_index: I32,
        _a2b: bool,
    ): option_u64::OptionU64 {
        abort (0)
    }

    public fun get_fee_in_range(
        _current_tick_index: I32,
        _fee_growth_outside_a: u128,
        _fee_growth_outside_b: u128,
        _maybe_tick_lower: option::Option<Tick>,
        _maybe_tick_upper: option::Option<Tick>,
    ): (u128, u128) {
        abort (0)
    }

    public fun get_magma_distribution_growth_in_range(
        _tick_index: I32,
        _growth: u128,
        _maybe_tick_lower: option::Option<Tick>,
        _maybe_tick_upper: option::Option<Tick>,
    ): u128 {
        abort (0)
    }

    public fun get_points_in_range(
        _tick_index: I32,
        _points_growth: u128,
        _maybe_tick_lower: option::Option<Tick>,
        _maybe_tick_upper: option::Option<Tick>,
    ): u128 {
        abort (0)
    }

    public fun get_reward_growth_outside(_tick: &Tick, _reward_growth_id: u64): u128 {
        abort (0)
    }

    public fun get_rewards_in_range(
        _current_tick_index: I32,
        _rewards: vector<u128>,
        _maybe_lower_tick: option::Option<Tick>,
        _maybe_upper_tick: option::Option<Tick>,
    ): vector<u128> {
        abort (0)
    }

    public(package) fun increase_liquidity(
        _tick_manager: &mut TickManager,
        _current_tick_index: I32,
        _tick_lower_index: I32,
        _tick_upper_index: I32,
        _liquidity_delta: u128,
        _fee_growth_a: u128,
        _fee_growth_b: u128,
        _points_growth: u128,
        _rewards_growth: vector<u128>,
        _magma_distribution_growth: u128,
    ) {
        abort (0)
    }

    public fun index(_tick: &Tick): I32 {
        abort (0)
    }

    public fun liquidity_gross(_tick: &Tick): u128 {
        abort (0)
    }

    public fun liquidity_net(_tick: &Tick): i128::I128 {
        abort (0)
    }

    public fun points_growth_outside(_tick: &Tick): u128 {
        abort (0)
    }

    public fun rewards_growth_outside(_tick: &Tick): &vector<u128> {
        abort (0)
    }

    public fun magma_distribution_growth_outside(_tick: &Tick): u128 {
        abort (0)
    }

    public fun magma_distribution_staked_liquidity_net(_tick: &Tick): i128::I128 {
        abort (0)
    }

    public fun sqrt_price(_tick: &Tick): u128 {
        abort (0)
    }

    public fun tick_spacing(_tick_manager: &TickManager): u32 {
        abort (0)
    }
}

#[allow(unused_const)]

module magma_clmm::pool {
    use integer_mate::{
        full_math_u128,
        full_math_u64,
        i128::{Self, I128},
        i32::{Self, I32},
        math_u128,
        math_u64
    };
    use magma_caps::gauge_cap::GaugeCap;
    use magma_clmm::{clmm_math, config, partner, position, rewarder, tick, tick_math};
    use std::{string::{Self, String}, type_name::{Self, TypeName}};
    use sui::{balance::{Self, Balance}, clock, display, event, package};

    const ErrAmountIncorrect: u64 = 0;
    const ErrLiquidityOverflow: u64 = 1;
    const ErrLiquidityUnderflow: u64 = 2;
    const ErrLiquidityIsZero: u64 = 3;
    const ErrNotEnoughLiquidity: u64 = 4;
    const ErrRemainderAmountUnderflow: u64 = 5;
    const ErrSwapAmountInOverflow: u64 = 6;
    const ErrSwapAmountOutOverflow: u64 = 7;
    const ErrFeeAmountOverflow: u64 = 8;
    const ErrInvalidFeeRate: u64 = 9;
    const ErrInvalidFixedCoinType: u64 = 10;
    const ErrWrongSqrtPriceLimit: u64 = 11;
    const ErrPoolIdIsError: u64 = 12;
    const ErrPoolPaused: u64 = 13;
    const ErrFlashSwapReceiptNotMatch: u64 = 14;
    const ErrInvalidProtocolFeeRate: u64 = 15;
    const ErrInvalidProtocolRefFeeRate: u64 = 16;
    const ErrRewardNotExist: u64 = 17;
    const ErrAmountOutIsZero: u64 = 18;
    const ErrWrongTick: u64 = 19;
    const ErrNoTickForSwap: u64 = 20;

    #[error]
    const ErrStakedLiquidityOverflow: vector<u8> = b"staked liquidity overflow";

    const Q64: u128 = 1 << 64;

    public struct POOL has drop {}

    public struct Pool<phantom CoinTypeA, phantom CoinTypeB> has key, store {
        id: UID,
        coin_a: Balance<CoinTypeA>,
        coin_b: Balance<CoinTypeB>,
        tick_spacing: u32,
        fee_rate: u64,
        liquidity: u128,
        current_sqrt_price: u128,
        current_tick_index: I32,
        fee_growth_global_a: u128,
        fee_growth_global_b: u128,
        fee_protocol_coin_a: u64,
        fee_protocol_coin_b: u64,
        tick_manager: tick::TickManager,
        rewarder_manager: rewarder::RewarderManager,
        position_manager: position::PositionManager,
        is_pause: bool,
        index: u64,
        url: String,
        unstaked_liquidity_fee_rate: u64,
        magma_distribution_gauger_id: Option<ID>,
        magma_distribution_growth_global: u128,
        magma_distribution_rate: u128,
        magma_distribution_reserve: u64,
        magma_distribution_period_finish: u64,
        magma_distribution_rollover: u64,
        magma_distribution_last_updated: u64,
        magma_distribution_staked_liquidity: u128,
        magma_distribution_gauger_fee: PoolFee,
    }

    public fun magma_distribution_gauger_fee<A, B>(_pool: &Pool<A, B>): PoolFee {
        abort (0)
    }

    public struct PoolFee has drop, store {
        coin_a: u64,
        coin_b: u64,
    }

    public fun pool_fee_a_b(_pf: &PoolFee): (u64, u64) {
        abort (0)
    }

    public struct SwapResult has copy, drop {
        amount_in: u64,
        amount_out: u64,
        fee_amount: u64,
        protocol_fee_amount: u64,
        ref_fee_amount: u64,
        gauge_fee_amount: u64,
        steps: u64,
    }

    public struct FlashSwapReceipt<phantom CoinTypeA, phantom CoinTypeB> {
        pool_id: ID,
        a2b: bool,
        partner_id: ID,
        pay_amount: u64,
        fee_amount: u64,
        protocol_fee_amount: u64,
        ref_fee_amount: u64,
        gauge_fee_amount: u64,
    }

    public struct AddLiquidityReceipt<phantom CoinTypeA, phantom CoinTypeB> {
        pool_id: ID,
        amount_a: u64,
        amount_b: u64,
    }

    public struct CalculatedSwapResult has copy, drop, store {
        amount_in: u64,
        amount_out: u64,
        fee_amount: u64,
        fee_rate: u64,
        ref_fee_amount: u64,
        gauge_fee_amount: u64,
        protocol_fee_amount: u64,
        after_sqrt_price: u128,
        is_exceed: bool,
        step_results: vector<SwapStepResult>,
    }

    public struct SwapStepResult has copy, drop, store {
        current_sqrt_price: u128,
        target_sqrt_price: u128,
        current_liquidity: u128,
        amount_in: u64,
        amount_out: u64,
        fee_amount: u64,
        remainder_amount: u64,
    }

    public struct OpenPositionEvent has copy, drop, store {
        pool: ID,
        tick_lower: I32,
        tick_upper: I32,
        position: ID,
    }

    public struct ClosePositionEvent has copy, drop, store {
        pool: ID,
        position: ID,
    }

    public struct AddLiquidityEvent has copy, drop, store {
        pool: ID,
        position: ID,
        tick_lower: I32,
        tick_upper: I32,
        liquidity: u128,
        after_liquidity: u128,
        amount_a: u64,
        amount_b: u64,
    }

    public struct RemoveLiquidityEvent has copy, drop, store {
        pool: ID,
        position: ID,
        tick_lower: I32,
        tick_upper: I32,
        liquidity: u128,
        after_liquidity: u128,
        amount_a: u64,
        amount_b: u64,
    }

    public struct SwapEvent has copy, drop, store {
        atob: bool,
        pool: ID,
        partner: ID,
        amount_in: u64,
        amount_out: u64,
        magma_fee_amount: u64,
        protocol_fee_amount: u64,
        ref_fee_amount: u64,
        fee_amount: u64,
        vault_a_amount: u64,
        vault_b_amount: u64,
        before_sqrt_price: u128,
        after_sqrt_price: u128,
        steps: u64,
    }

    public struct CollectProtocolFeeEvent has copy, drop, store {
        pool: ID,
        amount_a: u64,
        amount_b: u64,
    }

    public struct CollectFeeEvent has copy, drop, store {
        position: ID,
        pool: ID,
        amount_a: u64,
        amount_b: u64,
    }

    public struct UpdateFeeRateEvent has copy, drop, store {
        pool: ID,
        old_fee_rate: u64,
        new_fee_rate: u64,
    }

    public struct UpdateEmissionEvent has copy, drop, store {
        pool: ID,
        rewarder_type: TypeName,
        emissions_per_second: u128,
    }

    public struct AddRewarderEvent has copy, drop, store {
        pool: ID,
        rewarder_type: TypeName,
    }

    public struct CollectRewardEvent has copy, drop, store {
        position: ID,
        pool: ID,
        amount: u64,
    }

    public struct CollectGaugeFeeEvent has copy, drop, store {
        pool: ID,
        amount_a: u64,
        amount_b: u64,
    }

    public struct UpdateUnstakedLiquidityFeeRateEvent has copy, drop, store {
        pool: ID,
        old_fee_rate: u64,
        new_fee_rate: u64,
    }

    public fun get_amount_by_liquidity(
        _tick_lower_index: I32,
        _tick_upper_index: I32,
        _current_tick_index: I32,
        _current_sqrt_price: u128,
        _liquidity: u128,
        _round_up: bool,
    ): (u64, u64) {
        abort (0)
    }

    public fun borrow_position_info<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID,
    ): &position::PositionInfo {
        abort (0)
    }

    public fun close_position<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position: position::Position,
    ) {
        abort (0)
    }

    public fun fetch_positions<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _start: vector<ID>,
        _limit: u64,
    ): vector<position::PositionInfo> {
        abort (0)
    }

    public fun is_position_exist<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID,
    ): bool {
        abort (0)
    }

    public fun liquidity<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): u128 {
        abort (0)
    }

    public fun open_position<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _tick_lower: u32,
        _tick_upper: u32,
        _ctx: &mut TxContext,
    ): position::Position {
        abort (0)
    }

    public fun update_emission<CoinTypeA, CoinTypeB, RewardType>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _vault: &rewarder::RewarderGlobalVault,
        _emissions_per_sec_q64: u128,
        _clock: &clock::Clock,
        _ctx: &mut TxContext,
    ) {
        abort (0)
    }

    public fun borrow_tick<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _tick_index: I32,
    ): &tick::Tick {
        abort (0)
    }

    public fun fetch_ticks<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _start: vector<u32>,
        _limit: u64,
    ): vector<tick::Tick> {
        abort (0)
    }

    public fun index<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): u64 {
        abort (0)
    }

    public fun add_liquidity<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position: &mut position::Position,
        _liquidity: u128,
        _clock: &clock::Clock,
        _ctx: &mut TxContext,
    ): AddLiquidityReceipt<CoinTypeA, CoinTypeB> {
        abort (0)
    }

    public fun add_liquidity_fix_coin<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position: &mut position::Position,
        _amount: u64,
        _fix_amount_a: bool,
        _clock: &clock::Clock,
        _ctx: &mut TxContext,
    ): AddLiquidityReceipt<CoinTypeA, CoinTypeB> {
        abort (0)
    }

    public fun add_liquidity_pay_amount<CoinTypeA, CoinTypeB>(
        _recp: &AddLiquidityReceipt<CoinTypeA, CoinTypeB>,
    ): (u64, u64) {
        abort (0)
    }

    public fun balances<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): (u64, u64) {
        abort (0)
    }

    public fun calculate_and_update_fee<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID,
    ): (u64, u64) {
        abort (0)
    }

    public fun calculate_and_update_points<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID,
        _clock: &clock::Clock,
    ): u128 {
        abort (0)
    }

    public fun calculate_and_update_reward<CoinTypeA, CoinTypeB, T2>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID,
        _clock: &clock::Clock,
    ): u64 {
        abort (0)
    }

    public fun calculate_and_update_rewards<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID,
        _clock: &clock::Clock,
    ): vector<u64> {
        abort (0)
    }

    public fun calculate_and_update_magma_distribution<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID,
    ): u64 {
        abort (0)
    }

    public fun calculate_swap_result<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _a2b: bool,
        _by_amount_in: bool,
        _amount: u64,
    ): CalculatedSwapResult {
        abort (0)
    }

    public fun calculate_swap_result_with_partner<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _a2b: bool,
        _by_amount_in: bool,
        _amount: u64,
        _protocol_ref_fee_rate: u64,
    ): CalculatedSwapResult {
        abort (0)
    }

    public fun calculate_swap_result_step_results(
        _res: &CalculatedSwapResult,
    ): &vector<SwapStepResult> {
        abort (0)
    }

    public fun calculated_swap_result_after_sqrt_price(_res: &CalculatedSwapResult): u128 {
        abort (0)
    }

    public fun calculated_swap_result_amount_in(_res: &CalculatedSwapResult): u64 {
        abort (0)
    }

    public fun calculated_swap_result_amount_out(_res: &CalculatedSwapResult): u64 {
        abort (0)
    }

    public fun calculated_swap_result_fees_amount(
        _res: &CalculatedSwapResult,
    ): (u64, u64, u64, u64) {
        abort (0)
    }

    public fun calculated_swap_result_is_exceed(_res: &CalculatedSwapResult): bool {
        abort (0)
    }

    public fun calculated_swap_result_step_swap_result(
        _res: &CalculatedSwapResult,
        _step: u64,
    ): &SwapStepResult {
        abort (0)
    }

    public fun calculated_swap_result_steps_length(_res: &CalculatedSwapResult): u64 {
        abort (0)
    }

    public fun collect_fee<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position: &position::Position,
        _recalculate: bool,
    ): (Balance<CoinTypeA>, Balance<CoinTypeB>) {
        abort (0)
    }

    public fun collect_protocol_fee<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _ctx: &mut TxContext,
    ): (Balance<CoinTypeA>, Balance<CoinTypeB>) {
        abort (0)
    }

    public fun collect_reward<CoinTypeA, CoinTypeB, RewardType>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position: &position::Position,
        _vault: &mut rewarder::RewarderGlobalVault,
        _recalculate: bool,
        _clock: &clock::Clock,
    ): Balance<RewardType> {
        abort (0)
    }

    public fun current_sqrt_price<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): u128 {
        abort (0)
    }

    public fun current_tick_index<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): I32 {
        abort (0)
    }

    public fun fee_rate<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): u64 {
        abort (0)
    }

    public fun fees_growth_global<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
    ): (u128, u128) {
        abort (0)
    }

    public fun flash_swap<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _a2b: bool,
        _by_amount_in: bool,
        _amount: u64,
        _target_sqrt_price: u128,
        _clock: &clock::Clock,
    ): (Balance<CoinTypeA>, Balance<CoinTypeB>, FlashSwapReceipt<CoinTypeA, CoinTypeB>) {
        abort (0)
    }

    public fun flash_swap_with_partner<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _partner: &partner::Partner,
        _a2b: bool,
        _by_amount_in: bool,
        _amount: u64,
        _target_sqrt_price: u128,
        _clock: &clock::Clock,
    ): (Balance<CoinTypeA>, Balance<CoinTypeB>, FlashSwapReceipt<CoinTypeA, CoinTypeB>) {
        abort (0)
    }

    public fun get_fee_in_tick_range<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _tick_lower_index: I32,
        _tick_upper_index: I32,
    ): (u128, u128) {
        abort (0)
    }

    public fun get_all_growths_in_tick_range<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _tick_lower_index: I32,
        _tick_upper_index: I32,
    ): (u128, u128, vector<u128>, u128, u128) {
        abort (0)
    }

    public fun get_liquidity_from_amount(
        _tick_lower_index: I32,
        _tick_upper_index: I32,
        _current_tick_index: I32,
        _current_sqrt_price: u128,
        _amount: u64,
        _by_amount_a: bool,
    ): (u128, u64, u64) {
        abort (0)
    }

    public fun get_points_in_tick_range<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _tick_lower_index: I32,
        _tick_upper_index: I32,
    ): u128 {
        abort (0)
    }

    public fun get_position_amounts<CoinTypeA, CoinTypeB>(
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID,
    ): (u64, u64) {
        abort (0)
    }

    public fun get_position_fee<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID,
    ): (u64, u64) {
        abort (0)
    }

    public fun get_position_points<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID,
    ): u128 {
        abort (0)
    }

    public fun get_position_reward<CoinTypeA, CoinTypeB, RewardType>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID,
    ): u64 {
        abort (0)
    }

    public fun get_position_rewards<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID,
    ): vector<u64> {
        abort (0)
    }

    public fun get_rewards_in_tick_range<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _tick_lower_index: I32,
        _tick_upper_index: i32::I32,
    ): vector<u128> {
        abort (0)
    }

    public fun initialize_rewarder<CoinTypeA, CoinTypeB, RewardType>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _ctx: &mut TxContext,
    ) {
        abort (0)
    }

    public fun is_pause<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): bool {
        abort (0)
    }

    public fun pause<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _ctx: &mut TxContext,
    ) {
        abort (0)
    }

    public fun position_manager<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
    ): &position::PositionManager {
        abort (0)
    }

    public fun protocol_fee<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): (u64, u64) {
        abort (0)
    }

    public fun unstaked_liquidity_fee_rate<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
    ): u64 {
        abort (0)
    }

    public fun fees_amount<CoinTypeA, CoinTypeB>(
        _recp: &FlashSwapReceipt<CoinTypeA, CoinTypeB>,
    ): (u64, u64, u64, u64) {
        abort (0)
    }

    public fun remove_liquidity<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position: &mut position::Position,
        _liquidity: u128,
        _clock: &clock::Clock,
    ): (Balance<CoinTypeA>, Balance<CoinTypeB>) {
        abort (0)
    }

    public fun repay_add_liquidity<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _balance_a: Balance<CoinTypeA>,
        _balance_b: Balance<CoinTypeB>,
        _add_liquidity_receipt: AddLiquidityReceipt<CoinTypeA, CoinTypeB>,
    ) {
        abort (0)
    }

    public fun repay_flash_swap<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _balance_a: Balance<CoinTypeA>,
        _balance_b: Balance<CoinTypeB>,
        _flash_swap_receipt: FlashSwapReceipt<CoinTypeA, CoinTypeB>,
    ) {
        abort (0)
    }

    public fun repay_flash_swap_with_partner<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _partner: &mut partner::Partner,
        mut _balance_a: Balance<CoinTypeA>,
        mut _balance_b: Balance<CoinTypeB>,
        _flash_swap_receipt: FlashSwapReceipt<CoinTypeA, CoinTypeB>,
    ) {
        abort (0)
    }

    public fun rewarder_manager<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
    ): &rewarder::RewarderManager {
        abort (0)
    }

    #[allow(lint(self_transfer))]
    public fun set_display<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _publisher: &package::Publisher,
        _name: String,
        _description: String,
        _image_url: String,
        _link: String,
        _project_url: String,
        _creator: String,
        _ctx: &mut TxContext,
    ) {
        abort (0)
    }

    public fun step_swap_result_amount_in(_result: &SwapStepResult): u64 {
        abort (0)
    }

    public fun step_swap_result_amount_out(_result: &SwapStepResult): u64 {
        abort (0)
    }

    public fun step_swap_result_current_liquidity(_result: &SwapStepResult): u128 {
        abort (0)
    }

    public fun step_swap_result_current_sqrt_price(_result: &SwapStepResult): u128 {
        abort (0)
    }

    public fun step_swap_result_fee_amount(_result: &SwapStepResult): u64 {
        abort (0)
    }

    public fun step_swap_result_remainder_amount(_result: &SwapStepResult): u64 {
        abort (0)
    }

    public fun step_swap_result_target_sqrt_price(_result: &SwapStepResult): u128 {
        abort (0)
    }

    public fun swap_pay_amount<CoinTypeA, CoinTypeB>(
        _flash_swap_receipt: &FlashSwapReceipt<CoinTypeA, CoinTypeB>,
    ): u64 {
        abort (0)
    }

    public fun tick_manager<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
    ): &tick::TickManager {
        abort (0)
    }

    public fun tick_spacing<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): u32 {
        abort (0)
    }

    public fun unpause<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _ctx: &mut TxContext,
    ) {
        abort (0)
    }

    public fun update_unstaked_liquidity_fee_rate<A, B>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<A, B>,
        _fee_rate: u64,
        _ctx: &mut TxContext,
    ) {
        abort (0)
    }

    public fun update_fee_rate<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _new_fee_rate: u64,
        _ctx: &mut TxContext,
    ) {
        abort (0)
    }

    public fun update_pool_url<CoinTypeA, CoinTypeB>(
        _cfg: &config::GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _url: String,
        _ctx: &mut TxContext,
    ) {
        abort (0)
    }

    public fun url<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): String {
        abort (0)
    }

    public fun mark_position_staked<CoinTypeA, CoinTypeB>(
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _gauge_cap: &GaugeCap,
        _position_id: ID,
    ) {
        abort (0)
    }

    public fun mark_position_unstaked<CoinTypeA, CoinTypeB>(
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _gauge_cap: &GaugeCap,
        _position_id: ID,
    ) {
        abort (0)
    }

    public fun update_magma_distribution_growth_global<CoinTypeA, CoinTypeB>(
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _gauge_cap: &GaugeCap,
        _clock: &clock::Clock,
    ) {
        abort (0)
    }

    public fun get_magma_distribution_growth_inside<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _tick_lower_index: I32,
        _tick_upper_index: I32,
        mut _global_growth: u128,
    ): u128 {
        abort (0)
    }

    public fun stake_in_magma_distribution<CoinTypeA, CoinTypeB>(
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _gauge_cap: &GaugeCap,
        _liquidity_delta: u128,
        _tick_lower_index: I32,
        _tick_upper_index: I32,
        _clock: &clock::Clock,
    ) {
        abort (0)
    }

    public fun unstake_from_magma_distribution<CoinTypeA, CoinTypeB>(
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _gauge_cap: &GaugeCap,
        _liquidity_delta: u128,
        _tick_lower_index: I32,
        _tick_upper_index: I32,
        _clock: &clock::Clock,
    ) {
        abort (0)
    }

    public fun get_magma_distribution_last_updated<A, B>(_pool: &Pool<A, B>): u64 {
        abort (0)
    }

    public fun get_magma_distribution_growth_global<A, B>(_pool: &Pool<A, B>): u128 {
        abort (0)
    }

    public fun get_magma_distribution_reserve<A, B>(_pool: &Pool<A, B>): u64 {
        abort (0)
    }

    public fun get_magma_distribution_staked_liquidity<A, B>(_pool: &Pool<A, B>): u128 {
        abort (0)
    }

    public fun get_magma_distribution_gauger_id<A, B>(_pool: &Pool<A, B>): ID {
        abort (0)
    }

    public fun get_magma_distribution_rollover<A, B>(_pool: &Pool<A, B>): u64 {
        abort (0)
    }

    public fun init_magma_distribution_gauge<A, B>(_pool: &mut Pool<A, B>, _gauge_cap: &GaugeCap) {
        abort (0)
    }

    public fun sync_magma_distribution_reward<A, B>(
        _pool: &mut Pool<A, B>,
        _gauge_cap: &GaugeCap,
        _reward_rate: u128,
        _reward_reserves: u64,
        _period_finish: u64,
    ) {
        abort (0)
    }

    public fun collect_magma_distribution_gauger_fees<A, B>(
        _pool: &mut Pool<A, B>,
        _gauge_cap: &GaugeCap,
    ): (Balance<A>, Balance<B>) {
        abort (0)
    }
}

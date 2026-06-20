#[allow(unused_const)]

module magma_clmm::clmm_math {
    use integer_mate::{full_math_u128, full_math_u64, i32::{Self, I32}, math_u128, math_u256};
    use magma_clmm::tick_math;

    const ErrTokenAmountMaxExceed: u64 = 0;
    const ErrTokenAmountMinSubceeded: u64 = 1;
    const ErrMultiplicationOverflow: u64 = 2;
    const ErrIntegerDowncastOverflow: u64 = 3;
    const ErrInvalidSqrtPriceInput: u64 = 4;
    const ErrInvalidFixedTokenType: u64 = 5;
    const ErrInvalidTickIndex: u64 = 3018;

    const Q64: u256 = 18446744073709551615;

    // return: (amount_in, amount_out, sqrt_price, fee)
    // the amount_in returned is the total amount involved in the swap, it has non info about fee or anything else.
    public fun compute_swap_step(
        _from_price: u128,
        _to_price: u128,
        _current_liquidity: u128,
        _amount: u64,
        _fee_rate: u64,
        _a2b: bool,
        _by_amount_in: bool,
    ): (u64, u64, u128, u64) {
        abort (0)
    }

    public fun fee_rate_denominator(): u64 {
        1000000
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

    public fun get_delta_a(_price1: u128, _price2: u128, _liquidity: u128, _round_up: bool): u64 {
        abort (0)
    }

    public fun get_delta_b(_price1: u128, _price2: u128, _liquidity: u128, _round_up: bool): u64 {
        abort (0)
    }

    public fun get_delta_down_from_output(
        _from_price: u128,
        _to_price: u128,
        _liquidity: u128,
        _a2b: bool,
    ): u256 {
        abort (0)
    }

    public fun get_delta_up_from_input(
        _from_price: u128,
        _to_price: u128,
        _liquidity: u128,
        _a2b: bool,
    ): u256 {
        abort (0)
    }

    public fun get_liquidity_by_amount(
        _tick_lower_index: I32,
        _tick_upper_index: I32,
        _current_tick_index: I32,
        _current_sqrt_price: u128,
        _amount: u64,
        _fix_amount_a: bool,
    ): (u128, u64, u64) {
        abort (0)
    }

    public fun get_liquidity_from_a(
        _from_sqrt_price: u128,
        _to_sqrt_price: u128,
        _amount: u64,
        _round_up: bool,
    ): u128 {
        abort (0)
    }

    public fun get_liquidity_from_b(
        _from_sqrt_price: u128,
        _to_sqrt_price: u128,
        _amount: u64,
        _round_up: bool,
    ): u128 {
        abort (0)
    }

    public fun get_next_sqrt_price_a_up(
        _from_price: u128,
        _liquidity: u128,
        _amount: u64,
        _round_up: bool,
    ): u128 {
        abort (0)
    }

    public fun get_next_sqrt_price_b_down(
        _from_price: u128,
        _liquidity: u128,
        _amount: u64,
        _round_up: bool,
    ): u128 {
        abort (0)
    }

    public fun get_next_sqrt_price_from_input(
        _from_price: u128,
        _liquidity: u128,
        _amount_in: u64,
        _a2b: bool,
    ): u128 {
        abort (0)
    }

    public fun get_next_sqrt_price_from_output(
        _from_price: u128,
        _liquidity: u128,
        _amount_out: u64,
        _a2b: bool,
    ): u128 {
        abort (0)
    }
}

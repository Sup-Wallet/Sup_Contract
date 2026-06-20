module magma_clmm::tick_math {
    use integer_mate::{full_math_u128, i128, i32::{Self, I32}};

    const TICK_BOUND: u32 = 443636;
    const MAX_SQRT_PRICE_X64: u128 = 79226673515401279992447579055;
    const MIN_SQRT_PRICE_X64: u128 = 4295048016;

    const ErrInvalidTick: u64 = 1;
    const ErrInvalidSqrtPrice: u64 = 2;

    public fun get_sqrt_price_at_tick(_tick_index: I32): u128 {
        abort (0)
    }

    public fun get_tick_at_sqrt_price(_sqrt_price: u128): i32::I32 {
        abort (0)
    }

    public fun is_valid_index(index: I32, tick_spacing: u32): bool {
        abort (0)
    }

    public fun max_sqrt_price(): u128 {
        MAX_SQRT_PRICE_X64
    }

    public fun max_tick(): I32 {
        i32::from(TICK_BOUND)
    }

    public fun min_sqrt_price(): u128 {
        MIN_SQRT_PRICE_X64
    }

    public fun min_tick(): I32 {
        i32::neg_from(TICK_BOUND)
    }

    public fun tick_bound(): u32 {
        TICK_BOUND
    }
}

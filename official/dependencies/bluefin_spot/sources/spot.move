// Copyright (c) ZZYZX Labs
// SPDX-License-Identifier: BUSL-1.1

// INTERFACE STUB for Bluefin Spot CLMM — type shapes + signatures only, bodies
// abort. Signatures are taken from the OFFICIAL interface
// (github.com/fireflyprotocol/bluefin-spot-contract-interface @ mainnet-v1.35.2:
// sources/pool.move + config.move + position.move), and the mainnet package id is
// set in Move.toml (bluefin_spot = 0x3492…c267). Only the surface the Sup adaptor
// calls is reproduced — open_position, the fixed-amount add, remove, collect_fee,
// close. (A real deploy may swap this stub for the full BluefinSpot git dependency.)

module bluefin_spot::config {
    public struct GlobalConfig has key, store { id: UID }
}

module bluefin_spot::position {
    public struct Position has key, store { id: UID }
}

module bluefin_spot::pool {
    use sui::balance::Balance;
    use sui::clock::Clock;
    use bluefin_spot::config::GlobalConfig;
    use bluefin_spot::position::Position;

    public struct Pool<phantom CoinTypeA, phantom CoinTypeB> has key, store { id: UID }

    public fun open_position<CoinTypeA, CoinTypeB>(
        _protocol_config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _lower_tick_bits: u32,
        _upper_tick_bits: u32,
        _ctx: &mut TxContext,
    ): Position { abort 0 }

    /// add_liquidity_with_fixed_amount -> (amount_a_used, amount_b_used, residual_a, residual_b).
    public fun add_liquidity_with_fixed_amount<CoinTypeA, CoinTypeB>(
        _clock: &Clock,
        _protocol_config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position: &mut Position,
        _balance_a: Balance<CoinTypeA>,
        _balance_b: Balance<CoinTypeB>,
        _amount: u64,
        _is_fixed_a: bool,
    ): (u64, u64, Balance<CoinTypeA>, Balance<CoinTypeB>) { abort 0 }

    /// remove_liquidity -> (amount_a, amount_b, balance_a, balance_b).
    public fun remove_liquidity<CoinTypeA, CoinTypeB>(
        _protocol_config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position: &mut Position,
        _liquidity: u128,
        _clock: &Clock,
    ): (u64, u64, Balance<CoinTypeA>, Balance<CoinTypeB>) { abort 0 }

    /// collect_fee -> (amount_a, amount_b, balance_a, balance_b).
    public fun collect_fee<CoinTypeA, CoinTypeB>(
        _clock: &Clock,
        _protocol_config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position: &mut Position,
    ): (u64, u64, Balance<CoinTypeA>, Balance<CoinTypeB>) { abort 0 }

    public fun close_position_v2<CoinTypeA, CoinTypeB>(
        _clock: &Clock,
        _protocol_config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position: Position,
    ) { abort 0 }
}

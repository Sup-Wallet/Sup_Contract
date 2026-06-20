module magma_clmm::factory {
    use magma_clmm::{config, pool::{Self, Pool}, position, tick_math};
    use move_stl::linked_table::{Self, LinkedTable};
    use std::{string::{Self, String}, type_name::{Self, TypeName}};
    use sui::{bcs, clock, coin::Coin, event, hash, package};

    const ErrPoolAlreadyExisted: u64 = 1;
    const ErrInvalidSqrtPrice: u64 = 2;
    const ErrSameCoinType: u64 = 3;
    const ErrAmountInAboveMaxLimit: u64 = 4;
    const ErrAmountOutBelowMinLimit: u64 = 5;
    const ErrInvalidCoinTypeSequence: u64 = 6;

    public struct FACTORY has drop {}

    public struct PoolSimpleInfo has copy, drop, store {
        pool_id: ID,
        pool_key: ID,
        coin_type_a: TypeName,
        coin_type_b: TypeName,
        tick_spacing: u32,
    }

    public struct Pools has key, store {
        id: UID,
        list: LinkedTable<ID, PoolSimpleInfo>,
        index: u64,
    }

    public struct InitFactoryEvent has copy, drop {
        pools_id: ID,
    }

    public struct CreatePoolEvent has copy, drop {
        pool_id: ID,
        coin_type_a: String,
        coin_type_b: String,
        tick_spacing: u32,
    }

    #[allow(lint(share_owned))]
    public fun create_pool<CoinTypeA, CoinTypeB>(
        _pools: &mut Pools,
        _cfg: &config::GlobalConfig,
        _tick_spacing: u32,
        _initialize_price: u128,
        _name: String,
        _clock: &clock::Clock,
        _ctx: &mut TxContext,
    ): ID {
        abort (0)
    }

    public fun create_pool_<A, B>(
        _pools: &mut Pools,
        _cfg: &config::GlobalConfig,
        _tick_spacing: u32,
        _initialize_price: u128,
        _name: String,
        _clock: &clock::Clock,
        _ctx: &mut TxContext,
    ): Pool<A, B> {
        abort (0)
    }

    #[allow(lint(share_owned))]
    public fun create_pool_with_liquidity<CoinTypeA, CoinTypeB>(
        _pools: &mut Pools,
        _cfg: &config::GlobalConfig,
        _tick_spacing: u32,
        _initialize_price: u128,
        _name: String,
        _tick_lower: u32,
        _tick_upper: u32,
        mut _coin_a: Coin<CoinTypeA>,
        mut _coin_b: Coin<CoinTypeB>,
        _amount_a: u64,
        _amount_b: u64,
        _fix_amount_a: bool,
        _clock: &clock::Clock,
        _ctx: &mut TxContext,
    ): (position::Position, Coin<CoinTypeA>, Coin<CoinTypeB>) {
        abort (0)
    }

    public fun fetch_pools(
        _pools: &Pools,
        _start: vector<ID>,
        _limit: u64,
    ): vector<PoolSimpleInfo> {
        abort (0)
    }

    public fun index(_pools: &Pools): u64 {
        abort (0)
    }

    public fun new_pool_key<CoinTypeA, CoinTypeB>(_tick_spacing: u32): ID {
        abort (0)
    }

    public fun pool_id(_pool_info: &PoolSimpleInfo): ID {
        abort (0)
    }

    public fun pool_key(_pool_info: &PoolSimpleInfo): ID {
        abort (0)
    }

    public fun pool_simple_info(_pools: &Pools, _id: ID): &PoolSimpleInfo {
        abort (0)
    }

    public fun tick_spacing(_pool_info: &PoolSimpleInfo): u32 {
        abort (0)
    }

    public fun coin_types(_pool_info: &PoolSimpleInfo): (TypeName, TypeName) {
        abort (0)
    }
}

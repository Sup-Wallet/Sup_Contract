module magma_clmm::config;

// use sui::object::{Self, UID, ID};
// use sui::tx_context::{Self, TxContext};
use sui::vec_map;
use sui::vec_set;
use sui::event;

use magma_clmm::acl;

const ErrFeeTierAlreadyExist: u64 = 1;
const ErrFeeTierNotFound: u64 = 2;
const ErrInvalidFeeRate: u64 = 3;
const ErrInvalidProtocolFeeRate: u64 = 4;
const ErrNoPoolManagePermission: u64 = 5;
const ErrNoFeeTierManagePermission: u64 = 6;
const ErrNoPartnerManagePermission: u64 = 7;
const ErrNoRewardManagePermission: u64 = 8;
const ErrNoProtocolFeeClaimPermission: u64 = 9;
const ErrPackageVersionDeprecated: u64 = 10;
const ErrInvalidUnstakedLiquidityFeeRate: u64 = 11;


const FEE_TIER_MANAGER_ROLE: u8 = 1;
const PARTNER_MANAGER_ROLE: u8 = 3;
const POOL_MANAGER_ROLE: u8 = 0;
const PROTOCOL_FEE_CLAIM_ROLE: u8 = 2;
const REWARDER_MANAGER_ROLE: u8 = 4;

const WEEK: u64 = 86400 * 7;

const DEFAULT_UNSTAKED_FEE_RATE: u64 = 0xFFFFFFFFFFFFFF;

public fun week(): u64 {
    WEEK
}

public fun default_unstaked_fee_rate(): u64 {
    DEFAULT_UNSTAKED_FEE_RATE
}

public struct AdminCap has store, key {
    id: UID,
}

public struct ProtocolFeeClaimCap has store, key {
    id: UID,
}

public struct FeeTier has copy, drop, store {
    tick_spacing: u32,
    fee_rate: u64,
}

public struct GlobalConfig has store, key {
    id: UID,
    protocol_fee_rate: u64,
    unstaked_liquidity_fee_rate: u64,
    fee_tiers: vec_map::VecMap<u32, FeeTier>,
    acl: acl::ACL,
    package_version: u64,

    alive_gauges: vec_set::VecSet<ID>,
}

public fun epoch_next(ts: u64): u64 {
    ts - (ts % WEEK) + WEEK
}

public fun epoch_start(ts: u64): u64 {
    ts - (ts % WEEK)
}

public fun epoch(ts: u64): u64 {
    ts / WEEK
}

public struct InitConfigEvent has copy, drop {
    admin_cap_id: ID,
    global_config_id: ID,
}

public struct UpdateFeeRateEvent has copy, drop {
    old_fee_rate: u64,
    new_fee_rate: u64,
}

public struct UpdateUnstakedLiquidityFeeRateEvent has copy, drop {
    old_fee_rate: u64,
    new_fee_rate: u64,
}

public struct AddFeeTierEvent has copy, drop {
    tick_spacing: u32,
    fee_rate: u64,
}

public struct UpdateFeeTierEvent has copy, drop {
    tick_spacing: u32,
    old_fee_rate: u64,
    new_fee_rate: u64,
}

public struct DeleteFeeTierEvent has copy, drop {
    tick_spacing: u32,
    fee_rate: u64,
}

public struct SetRolesEvent has copy, drop {
    member: address,
    roles: u128,
}

public struct AddRoleEvent has copy, drop {
    member: address,
    role: u8,
}

public struct RemoveRoleEvent has copy, drop {
    member: address,
    role: u8,
}

public struct RemoveMemberEvent has copy, drop {
    member: address,
}

public struct SetPackageVersion has copy, drop {
    new_version: u64,
    old_version: u64,
}

public fun acl(cfg: &GlobalConfig) : &acl::ACL {
    &cfg.acl
}

public fun add_role(_admin_cap: &AdminCap, cfg: &mut GlobalConfig, member: address, role: u8) {
    cfg.checked_package_version();
    cfg.acl.add_role(member, role);
    event::emit(AddRoleEvent{member, role});
}

public fun get_members(cfg: &GlobalConfig) : vector<acl::Member> {
    cfg.acl.get_members()
}

public fun remove_member(_admin_cap: &AdminCap, cfg: &mut GlobalConfig, member: address) {
    cfg.checked_package_version();
    cfg.acl.remove_member(member);
    event::emit(RemoveMemberEvent{member});
}

public fun remove_role(_admin_cap: &AdminCap, cfg: &mut GlobalConfig, member: address, role: u8) {
    cfg.checked_package_version();
    cfg.acl.remove_role(member, role);
    event::emit(RemoveRoleEvent{member, role});
}

public fun set_roles(_admin_cap: &AdminCap, cfg: &mut GlobalConfig, member: address, roles: u128) {
    cfg.checked_package_version();
    cfg.acl.set_roles(member, roles);
    event::emit(SetRolesEvent{member, roles});
}

public fun add_fee_tier(cfg: &mut GlobalConfig, tick_spacing: u32, fee_rate: u64, ctx: &mut TxContext) {
    assert!(fee_rate <= max_fee_rate(), ErrInvalidFeeRate);
    assert!(!cfg.fee_tiers.contains(&tick_spacing), ErrFeeTierAlreadyExist);
    cfg.checked_package_version();
    cfg.check_fee_tier_manager_role(ctx.sender());
    cfg.fee_tiers.insert(tick_spacing, FeeTier{
        tick_spacing,
        fee_rate,
    });
    event::emit(AddFeeTierEvent{tick_spacing, fee_rate});
}

public fun check_fee_tier_manager_role(cfg: &GlobalConfig, addr: address) {
    assert!(cfg.acl.has_role(addr, FEE_TIER_MANAGER_ROLE), ErrNoFeeTierManagePermission);
}

public fun check_partner_manager_role(cfg: &GlobalConfig, addr: address) {
    assert!(cfg.acl.has_role(addr, PARTNER_MANAGER_ROLE), ErrNoPartnerManagePermission);
}

public fun check_pool_manager_role(cfg: &GlobalConfig, addr: address) {
    assert!(cfg.acl.has_role(addr, POOL_MANAGER_ROLE), ErrNoPoolManagePermission);
}

public fun check_protocol_fee_claim_role(cfg: &GlobalConfig, addr: address) {
    assert!(cfg.acl.has_role(addr, PROTOCOL_FEE_CLAIM_ROLE), ErrNoProtocolFeeClaimPermission);
}

public fun check_rewarder_manager_role(cfg: &GlobalConfig, addr: address) {
    assert!(cfg.acl.has_role(addr, REWARDER_MANAGER_ROLE), ErrNoRewardManagePermission);
}

public fun checked_package_version(cfg: &GlobalConfig) {
    assert!(cfg.package_version == 1, ErrPackageVersionDeprecated);
}

public fun delete_fee_tier(cfg: &mut GlobalConfig, tick_spacing: u32, ctx: &mut TxContext) {
    assert!(cfg.fee_tiers.contains(&tick_spacing), ErrFeeTierNotFound);
    cfg.checked_package_version();
    cfg.check_fee_tier_manager_role(ctx.sender());
    let (_, fee_tier) = cfg.fee_tiers.remove(&tick_spacing);
    event::emit(DeleteFeeTierEvent{
        tick_spacing,
        fee_rate: fee_tier.fee_rate,
    });
}

public fun fee_rate(ft: &FeeTier) : u64 {
    ft.fee_rate
}

public fun fee_tiers(cfg: &GlobalConfig) : &vec_map::VecMap<u32, FeeTier> {
    &cfg.fee_tiers
}

public fun get_fee_rate(tick_spacing: u32, cfg: &GlobalConfig) : u64 {
    assert!(cfg.fee_tiers.contains(&tick_spacing), ErrFeeTierNotFound);
    cfg.fee_tiers.get(&tick_spacing).fee_rate
}

public fun get_protocol_fee_rate(cfg: &GlobalConfig) : u64 {
    cfg.protocol_fee_rate
}

// By default the protocol_fee_rate is set to 0.
// All unstaked liquidity will be charge fee by
fun init(ctx: &mut TxContext) {
    let mut cfg = GlobalConfig{
        id                : object::new(ctx),
        unstaked_liquidity_fee_rate: 0,
        protocol_fee_rate : 2000,
        fee_tiers         : vec_map::empty(),
        acl               : acl::new(ctx),
        package_version   : 1,
        alive_gauges     : vec_set::empty(),
    };
    let admin_cap = AdminCap{id: object::new(ctx)};
    set_roles(&admin_cap, &mut cfg, ctx.sender(), 0 | 1 << 0 | 1 << 1 | 1 << 4 | 1 << 3);
    let init_config_event = InitConfigEvent{
        admin_cap_id     : object::id(&admin_cap),
        global_config_id : object::id(&cfg),
    };
    transfer::transfer(admin_cap, ctx.sender());
    transfer::share_object(cfg);
    event::emit<InitConfigEvent>(init_config_event);
}

public fun fee_rate_denom(): u64 {
    1000000
}

public fun max_fee_rate(): u64 {
    200000
}

public fun max_protocol_fee_rate(): u64 {
    3000
}

public fun protocol_fee_rate_denom(): u64 {
    10000
}

public fun max_unstaked_liquidity_fee_rate(): u64 {
    10000
}

public fun unstaked_liquidity_fee_rate_denom(): u64 {
    10000
}

public fun protocol_fee_rate(cfg: &GlobalConfig): u64 {
    cfg.protocol_fee_rate
}

public fun unstaked_liquidity_fee_rate(cfg: &GlobalConfig): u64 {
    cfg.unstaked_liquidity_fee_rate
}

public fun tick_spacing(ft: &FeeTier): u32 {
    ft.tick_spacing
}

public fun is_gauge_alive(cfg: &GlobalConfig, gauge_id: ID): bool {
    cfg.alive_gauges.contains(&gauge_id)
}

public fun update_gauge_liveness(cfg: &mut GlobalConfig, ids: vector<ID>, alive: bool, ctx: &mut TxContext) {
    let mut i = 0;
    let ll = ids.length();
    cfg.checked_package_version();
    cfg.check_pool_manager_role(ctx.sender());
    assert!(ll > 0);
    if (alive) {
        while (i < ll) {
            if (!cfg.alive_gauges.contains(ids.borrow(i))) {
                cfg.alive_gauges.insert(ids[i]);
            };
            i = i + 1;
        };
    } else {
        while (i < ll) {
            if (cfg.alive_gauges.contains(ids.borrow(i))) {
                cfg.alive_gauges.remove(ids.borrow(i));
            };
            i = i + 1;
        };
    };
}

public fun update_fee_tier(cfg: &mut GlobalConfig, tick_spacing: u32, new_fee_rate: u64, ctx: &mut TxContext) {
    assert!(cfg.fee_tiers.contains(&tick_spacing), ErrFeeTierNotFound);
    assert!(new_fee_rate <= max_fee_rate(), ErrInvalidFeeRate);
    cfg.checked_package_version();
    cfg.check_fee_tier_manager_role(ctx.sender());
    let fee_tier = cfg.fee_tiers.get_mut(&tick_spacing);
    let old_fee_rate = fee_tier.fee_rate;
    fee_tier.fee_rate = new_fee_rate;
    event::emit(UpdateFeeTierEvent{tick_spacing, new_fee_rate, old_fee_rate});
}

public fun update_package_version(_admin_cap: &AdminCap, cfg: &mut GlobalConfig, new_version: u64) {
    let old_version = cfg.package_version;
    cfg.package_version = new_version;
    event::emit(SetPackageVersion{new_version, old_version});
}

public fun update_protocol_fee_rate(cfg: &mut GlobalConfig, new_fee_rate: u64, ctx: &mut TxContext) {
    assert!(new_fee_rate <= 3000, ErrInvalidProtocolFeeRate);
    cfg.checked_package_version();
    cfg.check_pool_manager_role(ctx.sender());
    let old_fee_rate = cfg.protocol_fee_rate;
    cfg.protocol_fee_rate = new_fee_rate;
    event::emit(UpdateFeeRateEvent{old_fee_rate, new_fee_rate});
}

public fun update_unstaked_liquidity_fee_rate(cfg: &mut GlobalConfig, new_fee_rate: u64, ctx: &mut TxContext) {
    assert!(new_fee_rate <= max_unstaked_liquidity_fee_rate(), ErrInvalidUnstakedLiquidityFeeRate);
    cfg.checked_package_version();
    cfg.check_pool_manager_role(ctx.sender());
    let old_fee_rate = cfg.unstaked_liquidity_fee_rate;
    cfg.unstaked_liquidity_fee_rate = new_fee_rate;
    event::emit(UpdateUnstakedLiquidityFeeRateEvent{old_fee_rate, new_fee_rate});
}

#[test_only]
public fun create_config(ctx: &mut TxContext): (GlobalConfig, AdminCap) {
    let mut cfg = GlobalConfig{
        id: object::new(ctx),
        unstaked_liquidity_fee_rate: 1000, // default: 10%
        protocol_fee_rate: 0,
        fee_tiers: vec_map::empty(),
        acl: acl::new(ctx),
        package_version: 1,
        alive_gauges: vec_set::empty(),
    };
    cfg.fee_tiers.insert(10, FeeTier{tick_spacing: 10, fee_rate: 200000});
    let admin_cap = AdminCap{id: object::new(ctx)};
    set_roles(&admin_cap, &mut cfg, ctx.sender(), 0 | 1 << 0 | 1 << 1 | 1 << 4 | 1 << 3);
    let init_config_event = InitConfigEvent{
        admin_cap_id     : object::id(&admin_cap),
        global_config_id : object::id(&cfg),
    };
    event::emit<InitConfigEvent>(init_config_event);
    (cfg, admin_cap)
}

#[test_only]
public fun create_config_with_fee_rates(
    unstaked_liquidity_fee_rate: u64,
    protocol_fee_rate: u64,
    fee_tiers: vector<FeeTier>,
    ctx: &mut TxContext
): (GlobalConfig, AdminCap) {
    let mut cfg = GlobalConfig{
        id: object::new(ctx),
        unstaked_liquidity_fee_rate,
        protocol_fee_rate,
        fee_tiers: vec_map::empty(),
        acl: acl::new(ctx),
        package_version: 1,
        alive_gauges: vec_set::empty(),
    };
    let mut i = 0;
    while (i < vector::length(&fee_tiers)) {
        let fee_tier = vector::borrow(&fee_tiers, i);
        cfg.fee_tiers.insert(fee_tier.tick_spacing, *fee_tier);
        i = i + 1;
    };
    let admin_cap = AdminCap{id: object::new(ctx)};
    set_roles(&admin_cap, &mut cfg, ctx.sender(), 0 | 1 << 0 | 1 << 1 | 1 << 4 | 1 << 3);
    let init_config_event = InitConfigEvent{
        admin_cap_id     : object::id(&admin_cap),
        global_config_id : object::id(&cfg),
    };
    event::emit<InitConfigEvent>(init_config_event);
    (cfg, admin_cap)
}

#[test_only]
public fun create_fee_tier(tick_spacing: u32, fee_rate: u64): FeeTier {
    FeeTier { tick_spacing, fee_rate }
}

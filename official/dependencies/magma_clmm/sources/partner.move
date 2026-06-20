#[allow(unused_const)]

module magma_clmm::partner {
    use magma_clmm::config;
    use std::{string::{Self, String}, type_name};
    use sui::{bag, balance::Balance, clock, coin, event, vec_map};

    const ErrPartnerAlreadyExist: u64 = 1;
    const ErrInvalidPartnerRefFeeRate: u64 = 2;
    const ErrInvalidPartnerCap: u64 = 3;
    const ErrInvalidCoinType: u64 = 4;
    const ErrInvalidPartnerName: u64 = 5;
    const ErrInvalidEndTime: u64 = 6;
    const ErrInvalidStartTime: u64 = 7;

    public struct Partners has key {
        id: UID,
        partners: vec_map::VecMap<String, ID>,
    }

    public struct PartnerCap has key, store {
        id: UID,
        name: String,
        partner_id: ID,
    }

    public struct Partner has key, store {
        id: UID,
        name: String,
        ref_fee_rate: u64,
        start_time: u64,
        end_time: u64,
        balances: bag::Bag,
    }

    public struct InitPartnerEvent has copy, drop {
        partners_id: ID,
    }

    public struct CreatePartnerEvent has copy, drop {
        recipient: address,
        partner_id: ID,
        partner_cap_id: ID,
        ref_fee_rate: u64,
        name: String,
        start_time: u64,
        end_time: u64,
    }

    public struct UpdateRefFeeRateEvent has copy, drop {
        partner_id: ID,
        old_fee_rate: u64,
        new_fee_rate: u64,
    }

    public struct UpdateTimeRangeEvent has copy, drop {
        partner_id: ID,
        start_time: u64,
        end_time: u64,
    }

    public struct ReceiveRefFeeEvent has copy, drop {
        partner_id: ID,
        amount: u64,
        type_name: String,
    }

    public struct ClaimRefFeeEvent has copy, drop {
        partner_id: ID,
        amount: u64,
        type_name: String,
    }

    public fun balances(_partner: &Partner): &bag::Bag {
        abort (0)
    }

    #[allow(lint(self_transfer))]
    public fun claim_ref_fee<FeeType>(
        _cfg: &config::GlobalConfig,
        _partner_cap: &PartnerCap,
        _partner: &mut Partner,
        _ctx: &mut TxContext,
    ) {
        abort (0)
    }

    public fun create_partner(
        _cfg: &config::GlobalConfig,
        _partners: &mut Partners,
        _name: String,
        _ref_fee_rate: u64,
        _start_time: u64,
        _end_time: u64,
        _recipient: address,
        _clock: &clock::Clock,
        _ctx: &mut TxContext,
    ) {
        abort (0)
    }

    public fun current_ref_fee_rate(_partner: &Partner, _now: u64): u64 {
        abort (0)
    }

    public fun end_time(_partner: &Partner): u64 {
        abort (0)
    }

    public fun name(_partner: &Partner): String {
        abort (0)
    }

    public fun receive_ref_fee<CoinType>(_partner: &mut Partner, _fee: Balance<CoinType>) {
        abort (0)
    }

    public fun ref_fee_rate(_partner: &Partner): u64 {
        abort (0)
    }

    public fun start_time(_partner: &Partner): u64 {
        abort (0)
    }

    public fun update_ref_fee_rate(
        _cfg: &config::GlobalConfig,
        _partner: &mut Partner,
        _fee_rate: u64,
        _ctx: &mut TxContext,
    ) {
        abort (0)
    }

    public fun update_time_range(
        _cfg: &config::GlobalConfig,
        _partner: &mut Partner,
        _start_time: u64,
        _end_time: u64,
        _clock: &clock::Clock,
        _ctx: &mut TxContext,
    ) {
        abort (0)
    }
}

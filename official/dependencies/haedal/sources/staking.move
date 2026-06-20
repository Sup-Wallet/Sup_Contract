module haedal::staking;

use haedal::hasui::HASUI;
use sui::coin::Coin;
use sui::sui::SUI;
use sui_system::sui_system::SuiSystemState;

public struct Staking has key {
    id: UID,
}

public struct UnstakeTicket has key, store {
    id: UID,
}

public fun request_stake_coin(
    _system_state: &mut SuiSystemState,
    _staking: &mut Staking,
    _coin: Coin<SUI>,
    _validator: address,
    _ctx: &mut TxContext,
): Coin<HASUI> {
    abort 0
}

public fun request_unstake_instant_coin(
    _system_state: &mut SuiSystemState,
    _staking: &mut Staking,
    _hasui: Coin<HASUI>,
    _ctx: &mut TxContext,
): Coin<SUI> {
    abort 0
}

public fun claim_coin_v2(
    _system_state: &mut SuiSystemState,
    _staking: &mut Staking,
    _ticket: UnstakeTicket,
    _ctx: &mut TxContext,
): Coin<SUI> {
    abort 0
}

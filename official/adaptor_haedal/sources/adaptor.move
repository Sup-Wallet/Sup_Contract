module adaptor_haedal::adaptor;

use SupWallet::intent;
use SupWallet::wallet::Wallet;
use haedal::hasui::HASUI;
use haedal::staking::{Self, Staking};
use sui::coin;
use sui::event;
use sui::sui::SUI;
use sui_system::sui_system::SuiSystemState;

const EZeroAmount: u64 = 0;

/// Service witness for Haedal liquid staking.
///
/// Users grant this adaptor on SUI for staking and on HASUI for instant unstake.
public struct HaedalAdaptor has drop {}

public struct HaedalStaked has copy, drop {
    validator: address,
    sui_in: u64,
    hasui_out: u64,
}

public struct HaedalInstantUnstaked has copy, drop {
    hasui_in: u64,
    sui_out: u64,
}

public fun stake(
    wallet: &mut Wallet,
    system_state: &mut SuiSystemState,
    staking_obj: &mut Staking,
    amount_in: u64,
    min_hasui_out: u64,
    validator: address,
    ctx: &mut TxContext,
) {
    assert!(amount_in > 0, EZeroAmount);

    let sig = intent::request_swap<HaedalAdaptor, SUI, HASUI>(
        HaedalAdaptor {},
        amount_in,
        min_hasui_out,
    );
    let (sui_in, wallet_swap_witness) =
        intent::validate_and_swap_out<HaedalAdaptor, SUI, HASUI>(
            wallet,
            sig,
            ctx,
        );

    let hasui_out = staking::request_stake_coin(
        system_state,
        staking_obj,
        sui_in,
        validator,
        ctx,
    );
    let amount_out = coin::value(&hasui_out);
    let receipt = intent::create_swap_receipt<HaedalAdaptor, SUI, HASUI>(
        HaedalAdaptor {},
        amount_in,
        amount_out,
    );

    intent::verify_swap_and_credit<HaedalAdaptor, SUI, HASUI>(
        wallet,
        wallet_swap_witness,
        receipt,
        hasui_out,
    );

    event::emit(HaedalStaked {
        validator,
        sui_in: amount_in,
        hasui_out: amount_out,
    });
}

public fun unstake_instant(
    wallet: &mut Wallet,
    system_state: &mut SuiSystemState,
    staking_obj: &mut Staking,
    amount_in: u64,
    min_sui_out: u64,
    ctx: &mut TxContext,
) {
    assert!(amount_in > 0, EZeroAmount);

    let sig = intent::request_swap<HaedalAdaptor, HASUI, SUI>(
        HaedalAdaptor {},
        amount_in,
        min_sui_out,
    );
    let (hasui_in, wallet_swap_witness) =
        intent::validate_and_swap_out<HaedalAdaptor, HASUI, SUI>(
            wallet,
            sig,
            ctx,
        );

    let sui_out = staking::request_unstake_instant_coin(
        system_state,
        staking_obj,
        hasui_in,
        ctx,
    );
    let amount_out = coin::value(&sui_out);
    let receipt = intent::create_swap_receipt<HaedalAdaptor, HASUI, SUI>(
        HaedalAdaptor {},
        amount_in,
        amount_out,
    );

    intent::verify_swap_and_credit<HaedalAdaptor, HASUI, SUI>(
        wallet,
        wallet_swap_witness,
        receipt,
        sui_out,
    );

    event::emit(HaedalInstantUnstaked {
        hasui_in: amount_in,
        sui_out: amount_out,
    });
}

#[test_only]
public fun zero_amount_error(): u64 {
    EZeroAmount
}

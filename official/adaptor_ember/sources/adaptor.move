module adaptor_ember::adaptor;

use SupWallet::intent::{Self, WalletSwapWitness};
use SupWallet::wallet::Wallet;
use sui::coin::{Self, Coin};
use sui::event;

const EZeroAmount: u64 = 0;

/// Ember structured-vault adaptor witness.
///
/// Ember vaults are SDK/PTB-driven and may route across several underlying
/// strategies. This adaptor only owns Sup custody accounting; Ember's live SDK
/// commands sit between begin_* and finish_* in the PTB.
public struct EmberAdaptor has drop {}

public struct EmberDepositBegan has copy, drop {
    amount_in: u64,
    min_share_out: u64,
}

public struct EmberDepositFinished has copy, drop {
    amount_in: u64,
    share_out: u64,
}

public struct EmberRedeemBegan has copy, drop {
    share_in: u64,
    min_amount_out: u64,
}

public struct EmberRedeemFinished has copy, drop {
    share_in: u64,
    amount_out: u64,
}

public fun begin_deposit<Asset, Share>(
    wallet: &mut Wallet,
    amount_in: u64,
    min_share_out: u64,
    ctx: &mut TxContext,
): (Coin<Asset>, WalletSwapWitness<EmberAdaptor, Asset, Share>) {
    assert!(amount_in > 0, EZeroAmount);

    let sig = intent::request_swap<EmberAdaptor, Asset, Share>(
        EmberAdaptor {},
        amount_in,
        min_share_out,
    );
    let (asset_in, wallet_swap_witness) =
        intent::validate_and_swap_out<EmberAdaptor, Asset, Share>(
            wallet,
            sig,
            ctx,
        );

    event::emit(EmberDepositBegan { amount_in, min_share_out });

    (asset_in, wallet_swap_witness)
}

public fun finish_deposit<Asset, Share>(
    wallet: &mut Wallet,
    wallet_swap_witness: WalletSwapWitness<EmberAdaptor, Asset, Share>,
    share_out: Coin<Share>,
) {
    let amount_in =
        intent::wallet_swap_witness_amount_in<EmberAdaptor, Asset, Share>(
            &wallet_swap_witness,
        );
    let amount_out = coin::value(&share_out);
    let receipt = intent::create_swap_receipt<EmberAdaptor, Asset, Share>(
        EmberAdaptor {},
        amount_in,
        amount_out,
    );

    intent::verify_swap_and_credit<EmberAdaptor, Asset, Share>(
        wallet,
        wallet_swap_witness,
        receipt,
        share_out,
    );

    event::emit(EmberDepositFinished { amount_in, share_out: amount_out });
}

public fun begin_redeem<Share, Asset>(
    wallet: &mut Wallet,
    share_in: u64,
    min_amount_out: u64,
    ctx: &mut TxContext,
): (Coin<Share>, WalletSwapWitness<EmberAdaptor, Share, Asset>) {
    assert!(share_in > 0, EZeroAmount);

    let sig = intent::request_swap<EmberAdaptor, Share, Asset>(
        EmberAdaptor {},
        share_in,
        min_amount_out,
    );
    let (share_coin, wallet_swap_witness) =
        intent::validate_and_swap_out<EmberAdaptor, Share, Asset>(
            wallet,
            sig,
            ctx,
        );

    event::emit(EmberRedeemBegan { share_in, min_amount_out });

    (share_coin, wallet_swap_witness)
}

public fun finish_redeem<Share, Asset>(
    wallet: &mut Wallet,
    wallet_swap_witness: WalletSwapWitness<EmberAdaptor, Share, Asset>,
    asset_out: Coin<Asset>,
) {
    let share_in =
        intent::wallet_swap_witness_amount_in<EmberAdaptor, Share, Asset>(
            &wallet_swap_witness,
        );
    let amount_out = coin::value(&asset_out);
    let receipt = intent::create_swap_receipt<EmberAdaptor, Share, Asset>(
        EmberAdaptor {},
        share_in,
        amount_out,
    );

    intent::verify_swap_and_credit<EmberAdaptor, Share, Asset>(
        wallet,
        wallet_swap_witness,
        receipt,
        asset_out,
    );

    event::emit(EmberRedeemFinished { share_in, amount_out });
}

#[test_only]
public fun zero_amount_error(): u64 {
    EZeroAmount
}

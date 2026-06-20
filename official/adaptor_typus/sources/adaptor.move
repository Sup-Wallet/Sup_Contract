module adaptor_typus::adaptor;

use SupWallet::intent::{Self, WalletSwapWitness};
use SupWallet::wallet::Wallet;
use sui::coin::{Self, Coin};
use sui::event;

const EZeroAmount: u64 = 0;

/// Typus PTB-native adaptor witness.
///
/// Typus products include DOV/SAFU/TLP/perps surfaces that can change package
/// versions independently. This adaptor keeps Sup custody policy stable:
///   1. begin_deposit/redeem debits the granted coin from the Sup Wallet.
///   2. The Typus SDK or hand-built PTB executes the live protocol call.
///   3. finish_deposit/redeem verifies min output and credits the result.
public struct TypusAdaptor has drop {}

public struct TypusDepositBegan has copy, drop {
    amount_in: u64,
    min_share_out: u64,
}

public struct TypusDepositFinished has copy, drop {
    amount_in: u64,
    share_out: u64,
}

public struct TypusRedeemBegan has copy, drop {
    share_in: u64,
    min_amount_out: u64,
}

public struct TypusRedeemFinished has copy, drop {
    share_in: u64,
    amount_out: u64,
}

public fun begin_deposit<Asset, Share>(
    wallet: &mut Wallet,
    amount_in: u64,
    min_share_out: u64,
    ctx: &mut TxContext,
): (Coin<Asset>, WalletSwapWitness<TypusAdaptor, Asset, Share>) {
    assert!(amount_in > 0, EZeroAmount);

    let sig = intent::request_swap<TypusAdaptor, Asset, Share>(
        TypusAdaptor {},
        amount_in,
        min_share_out,
    );
    let (asset_in, wallet_swap_witness) =
        intent::validate_and_swap_out<TypusAdaptor, Asset, Share>(
            wallet,
            sig,
            ctx,
        );

    event::emit(TypusDepositBegan {
        amount_in,
        min_share_out,
    });

    (asset_in, wallet_swap_witness)
}

public fun finish_deposit<Asset, Share>(
    wallet: &mut Wallet,
    wallet_swap_witness: WalletSwapWitness<TypusAdaptor, Asset, Share>,
    share_out: Coin<Share>,
) {
    let amount_in =
        intent::wallet_swap_witness_amount_in<TypusAdaptor, Asset, Share>(
            &wallet_swap_witness,
        );
    let amount_out = coin::value(&share_out);
    let receipt = intent::create_swap_receipt<TypusAdaptor, Asset, Share>(
        TypusAdaptor {},
        amount_in,
        amount_out,
    );

    intent::verify_swap_and_credit<TypusAdaptor, Asset, Share>(
        wallet,
        wallet_swap_witness,
        receipt,
        share_out,
    );

    event::emit(TypusDepositFinished {
        amount_in,
        share_out: amount_out,
    });
}

public fun begin_redeem<Share, Asset>(
    wallet: &mut Wallet,
    share_in: u64,
    min_amount_out: u64,
    ctx: &mut TxContext,
): (Coin<Share>, WalletSwapWitness<TypusAdaptor, Share, Asset>) {
    assert!(share_in > 0, EZeroAmount);

    let sig = intent::request_swap<TypusAdaptor, Share, Asset>(
        TypusAdaptor {},
        share_in,
        min_amount_out,
    );
    let (share_coin, wallet_swap_witness) =
        intent::validate_and_swap_out<TypusAdaptor, Share, Asset>(
            wallet,
            sig,
            ctx,
        );

    event::emit(TypusRedeemBegan {
        share_in,
        min_amount_out,
    });

    (share_coin, wallet_swap_witness)
}

public fun finish_redeem<Share, Asset>(
    wallet: &mut Wallet,
    wallet_swap_witness: WalletSwapWitness<TypusAdaptor, Share, Asset>,
    asset_out: Coin<Asset>,
) {
    let share_in =
        intent::wallet_swap_witness_amount_in<TypusAdaptor, Share, Asset>(
            &wallet_swap_witness,
        );
    let amount_out = coin::value(&asset_out);
    let receipt = intent::create_swap_receipt<TypusAdaptor, Share, Asset>(
        TypusAdaptor {},
        share_in,
        amount_out,
    );

    intent::verify_swap_and_credit<TypusAdaptor, Share, Asset>(
        wallet,
        wallet_swap_witness,
        receipt,
        asset_out,
    );

    event::emit(TypusRedeemFinished {
        share_in,
        amount_out,
    });
}

#[test_only]
public fun zero_amount_error(): u64 {
    EZeroAmount
}

module adaptor_aftermath::adaptor;

use SupWallet::intent::{Self, WalletSwapWitness};
use SupWallet::wallet::Wallet;
use sui::coin::{Self, Coin};
use sui::event;

const EZeroAmount: u64 = 0;

/// Aftermath Perpetuals / vault adaptor witness.
///
/// Safe PTB-native surfaces:
/// - vault deposit/redeem where the protocol returns LP/asset coins
/// - account/vault withdrawals that return a coin to Sup Wallet
///
/// Collateral deposits into an Aftermath account are intentionally not exposed
/// here unless the protocol call is linked directly, because a finish-without-
/// output helper would not prove the external account received the collateral.
public struct AftermathAdaptor has drop {}

public struct AftermathVaultDepositBegan has copy, drop {
    amount_in: u64,
    min_lp_out: u64,
}

public struct AftermathVaultDepositFinished has copy, drop {
    amount_in: u64,
    lp_out: u64,
}

public struct AftermathVaultRedeemBegan has copy, drop {
    lp_in: u64,
    min_amount_out: u64,
}

public struct AftermathVaultRedeemFinished has copy, drop {
    lp_in: u64,
    amount_out: u64,
}

public fun begin_vault_deposit<Collateral, Lp>(
    wallet: &mut Wallet,
    amount_in: u64,
    min_lp_out: u64,
    ctx: &mut TxContext,
): (Coin<Collateral>, WalletSwapWitness<AftermathAdaptor, Collateral, Lp>) {
    assert!(amount_in > 0, EZeroAmount);

    let sig = intent::request_swap<AftermathAdaptor, Collateral, Lp>(
        AftermathAdaptor {},
        amount_in,
        min_lp_out,
    );
    let (collateral, wallet_swap_witness) =
        intent::validate_and_swap_out<AftermathAdaptor, Collateral, Lp>(
            wallet,
            sig,
            ctx,
        );

    event::emit(AftermathVaultDepositBegan {
        amount_in,
        min_lp_out,
    });

    (collateral, wallet_swap_witness)
}

public fun finish_vault_deposit<Collateral, Lp>(
    wallet: &mut Wallet,
    wallet_swap_witness: WalletSwapWitness<AftermathAdaptor, Collateral, Lp>,
    lp_out: Coin<Lp>,
) {
    let amount_in =
        intent::wallet_swap_witness_amount_in<AftermathAdaptor, Collateral, Lp>(
            &wallet_swap_witness,
        );
    let amount_out = coin::value(&lp_out);
    let receipt = intent::create_swap_receipt<AftermathAdaptor, Collateral, Lp>(
        AftermathAdaptor {},
        amount_in,
        amount_out,
    );

    intent::verify_swap_and_credit<AftermathAdaptor, Collateral, Lp>(
        wallet,
        wallet_swap_witness,
        receipt,
        lp_out,
    );

    event::emit(AftermathVaultDepositFinished {
        amount_in,
        lp_out: amount_out,
    });
}

public fun begin_vault_redeem<Lp, Collateral>(
    wallet: &mut Wallet,
    lp_in: u64,
    min_amount_out: u64,
    ctx: &mut TxContext,
): (Coin<Lp>, WalletSwapWitness<AftermathAdaptor, Lp, Collateral>) {
    assert!(lp_in > 0, EZeroAmount);

    let sig = intent::request_swap<AftermathAdaptor, Lp, Collateral>(
        AftermathAdaptor {},
        lp_in,
        min_amount_out,
    );
    let (lp_coin, wallet_swap_witness) =
        intent::validate_and_swap_out<AftermathAdaptor, Lp, Collateral>(
            wallet,
            sig,
            ctx,
        );

    event::emit(AftermathVaultRedeemBegan {
        lp_in,
        min_amount_out,
    });

    (lp_coin, wallet_swap_witness)
}

public fun finish_vault_redeem<Lp, Collateral>(
    wallet: &mut Wallet,
    wallet_swap_witness: WalletSwapWitness<AftermathAdaptor, Lp, Collateral>,
    collateral_out: Coin<Collateral>,
) {
    let lp_in =
        intent::wallet_swap_witness_amount_in<AftermathAdaptor, Lp, Collateral>(
            &wallet_swap_witness,
        );
    let amount_out = coin::value(&collateral_out);
    let receipt = intent::create_swap_receipt<AftermathAdaptor, Lp, Collateral>(
        AftermathAdaptor {},
        lp_in,
        amount_out,
    );

    intent::verify_swap_and_credit<AftermathAdaptor, Lp, Collateral>(
        wallet,
        wallet_swap_witness,
        receipt,
        collateral_out,
    );

    event::emit(AftermathVaultRedeemFinished {
        lp_in,
        amount_out,
    });
}

#[test_only]
public fun zero_amount_error(): u64 {
    EZeroAmount
}

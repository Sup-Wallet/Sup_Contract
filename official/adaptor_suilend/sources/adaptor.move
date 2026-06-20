module adaptor_suilend::adaptor;

use SupWallet::intent::{Self, WalletSwapWitness};
use SupWallet::wallet::Wallet;
use sui::coin::{Self, Coin};
use sui::event;

const EZeroAmount: u64 = 0;

/// Suilend PTB-native adaptor witness.
///
/// This package intentionally avoids linking to Suilend's frequently-upgraded
/// protocol package. The PTB pattern is:
///   1. begin_deposit: debit Underlying from Sup Wallet
///   2. Suilend SDK commands deposit liquidity and return CToken
///   3. finish_deposit: verify min CToken output and credit it to Sup Wallet
///
/// Withdraw mirrors the same shape with CToken -> Underlying.
public struct SuilendAdaptor has drop {}

public struct SuilendDepositBegan has copy, drop {
    amount_in: u64,
    min_ctoken_out: u64,
}

public struct SuilendDepositFinished has copy, drop {
    amount_in: u64,
    ctoken_out: u64,
}

public struct SuilendWithdrawBegan has copy, drop {
    ctoken_in: u64,
    min_amount_out: u64,
}

public struct SuilendWithdrawFinished has copy, drop {
    ctoken_in: u64,
    amount_out: u64,
}

public fun begin_deposit<Underlying, CToken>(
    wallet: &mut Wallet,
    amount_in: u64,
    min_ctoken_out: u64,
    ctx: &mut TxContext,
): (Coin<Underlying>, WalletSwapWitness<SuilendAdaptor, Underlying, CToken>) {
    assert!(amount_in > 0, EZeroAmount);

    let sig = intent::request_swap<SuilendAdaptor, Underlying, CToken>(
        SuilendAdaptor {},
        amount_in,
        min_ctoken_out,
    );
    let (coin_in, wallet_swap_witness) =
        intent::validate_and_swap_out<SuilendAdaptor, Underlying, CToken>(
            wallet,
            sig,
            ctx,
        );

    event::emit(SuilendDepositBegan {
        amount_in,
        min_ctoken_out,
    });

    (coin_in, wallet_swap_witness)
}

public fun finish_deposit<Underlying, CToken>(
    wallet: &mut Wallet,
    wallet_swap_witness: WalletSwapWitness<SuilendAdaptor, Underlying, CToken>,
    ctoken_out: Coin<CToken>,
) {
    let amount_in =
        intent::wallet_swap_witness_amount_in<SuilendAdaptor, Underlying, CToken>(
            &wallet_swap_witness,
        );
    let amount_out = coin::value(&ctoken_out);
    let receipt = intent::create_swap_receipt<SuilendAdaptor, Underlying, CToken>(
        SuilendAdaptor {},
        amount_in,
        amount_out,
    );

    intent::verify_swap_and_credit<SuilendAdaptor, Underlying, CToken>(
        wallet,
        wallet_swap_witness,
        receipt,
        ctoken_out,
    );

    event::emit(SuilendDepositFinished {
        amount_in,
        ctoken_out: amount_out,
    });
}

public fun begin_withdraw<CToken, Underlying>(
    wallet: &mut Wallet,
    ctoken_in: u64,
    min_amount_out: u64,
    ctx: &mut TxContext,
): (Coin<CToken>, WalletSwapWitness<SuilendAdaptor, CToken, Underlying>) {
    assert!(ctoken_in > 0, EZeroAmount);

    let sig = intent::request_swap<SuilendAdaptor, CToken, Underlying>(
        SuilendAdaptor {},
        ctoken_in,
        min_amount_out,
    );
    let (coin_in, wallet_swap_witness) =
        intent::validate_and_swap_out<SuilendAdaptor, CToken, Underlying>(
            wallet,
            sig,
            ctx,
        );

    event::emit(SuilendWithdrawBegan {
        ctoken_in,
        min_amount_out,
    });

    (coin_in, wallet_swap_witness)
}

public fun finish_withdraw<CToken, Underlying>(
    wallet: &mut Wallet,
    wallet_swap_witness: WalletSwapWitness<SuilendAdaptor, CToken, Underlying>,
    coin_out: Coin<Underlying>,
) {
    let ctoken_in =
        intent::wallet_swap_witness_amount_in<SuilendAdaptor, CToken, Underlying>(
            &wallet_swap_witness,
        );
    let amount_out = coin::value(&coin_out);
    let receipt = intent::create_swap_receipt<SuilendAdaptor, CToken, Underlying>(
        SuilendAdaptor {},
        ctoken_in,
        amount_out,
    );

    intent::verify_swap_and_credit<SuilendAdaptor, CToken, Underlying>(
        wallet,
        wallet_swap_witness,
        receipt,
        coin_out,
    );

    event::emit(SuilendWithdrawFinished {
        ctoken_in,
        amount_out,
    });
}

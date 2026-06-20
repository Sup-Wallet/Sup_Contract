module adaptor_swap_aggregator::adaptor;

use SupWallet::intent::{Self, WalletSwapWitness};
use SupWallet::wallet::Wallet;
use sui::coin::{Self, Coin};
use sui::event;

const EZeroAmount: u64 = 0;

/// Generic swap-routing service witness.
///
/// This adaptor intentionally does not call any DEX itself. It lets a PTB do:
///   1. begin_swap: debit CoinIn from Sup Wallet and return a hot-potato witness
///   2. aggregator SDK commands: Cetus / 7k / FlowX / Aftermath / Astros route
///   3. finish_swap: verify min_out and credit CoinOut back to Sup Wallet
///
/// Keeping route execution in the PTB preserves aggregator flexibility without
/// needing to mirror every provider-specific router in Move.
public struct SwapAggregatorAdaptor has drop {}

public struct AggregatorSwapBegan has copy, drop {
    amount_in: u64,
    min_amount_out: u64,
}

public struct AggregatorSwapFinished has copy, drop {
    amount_in: u64,
    amount_out: u64,
}

public fun begin_swap<CoinIn, CoinOut>(
    wallet: &mut Wallet,
    amount_in: u64,
    min_amount_out: u64,
    ctx: &mut TxContext,
): (Coin<CoinIn>, WalletSwapWitness<SwapAggregatorAdaptor, CoinIn, CoinOut>) {
    assert!(amount_in > 0, EZeroAmount);

    let sig = intent::request_swap<SwapAggregatorAdaptor, CoinIn, CoinOut>(
        SwapAggregatorAdaptor {},
        amount_in,
        min_amount_out,
    );
    let (coin_in, wallet_swap_witness) =
        intent::validate_and_swap_out<SwapAggregatorAdaptor, CoinIn, CoinOut>(
            wallet,
            sig,
            ctx,
        );

    event::emit(AggregatorSwapBegan {
        amount_in,
        min_amount_out,
    });

    (coin_in, wallet_swap_witness)
}

public fun finish_swap<CoinIn, CoinOut>(
    wallet: &mut Wallet,
    wallet_swap_witness: WalletSwapWitness<SwapAggregatorAdaptor, CoinIn, CoinOut>,
    coin_out: Coin<CoinOut>,
) {
    let amount_in =
        intent::wallet_swap_witness_amount_in<SwapAggregatorAdaptor, CoinIn, CoinOut>(
            &wallet_swap_witness,
        );
    let amount_out = coin::value(&coin_out);
    let receipt = intent::create_swap_receipt<SwapAggregatorAdaptor, CoinIn, CoinOut>(
        SwapAggregatorAdaptor {},
        amount_in,
        amount_out,
    );

    intent::verify_swap_and_credit<SwapAggregatorAdaptor, CoinIn, CoinOut>(
        wallet,
        wallet_swap_witness,
        receipt,
        coin_out,
    );

    event::emit(AggregatorSwapFinished {
        amount_in,
        amount_out,
    });
}

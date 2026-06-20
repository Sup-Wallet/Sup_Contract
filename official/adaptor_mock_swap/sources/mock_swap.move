/// **Canonical reference adaptor** demonstrating how to wire a third-party
/// protocol into Sup Wallet. Copy this file as a starting template — replace
/// `swap_external` with a real DEX call (Cetus / Bucket PSM / etc.).
///
/// This adaptor uses Mode D (internal swap) — `Coin<CoinIn>` pulled from the
/// wallet, swapped externally, `Coin<CoinOut>` pushed back into the same
/// wallet. The 4-step intent flow is documented inline.
///
/// User setup before this adaptor can pull funds:
///   1. `wallet::grant_service_coin<MockSwap, CoinIn>(wallet, ctx)`
///      — owner allowlists this adaptor against the input coin type
///   2. (delegate-flow only — main_owner bypasses)
///      `delegate::set_service_allowance<MockSwap>(wallet, delegate, qty, ctx)`
///   3. (delegate-flow only)
///      `delegate::set_coin_allowance<CoinIn>(wallet, delegate, qty, ctx)`
///
/// Auth model recap (4 gates traversed during `do_swap`):
///   Gate 1 — witness privacy: only this module can construct `MockSwap{}`.
///   Gate 2 — `wallet.auth[MockSwap]` contains `CoinIn` (step 1 above).
///   Gate 3 — sender has per-service `MockSwap` allowance ≥ amount_in.
///   Gate 4 — sender has per-coin `CoinIn` allowance ≥ amount_in.
/// `main_owner` short-circuits gates 3+4 to UNLIMITED.
#[test_only]
module AdaptorMockSwap::mock_swap {
    use sui::{
        coin::{Self, Coin},
        tx_context::TxContext,
    };
    use SupWallet::wallet::Wallet;
    use SupWallet::intent;

    // ===== Witness =====

    /// Service witness. `has drop` ONLY — no `key` / `store`. If this type
    /// could be stored or transferred, other modules could obtain an
    /// instance and impersonate this adaptor (spoofing auth).
    public struct MockSwap has drop {}

    // ===== Errors =====

    const EZeroAmount: u64 = 0;
    const EInvalidRate: u64 = 1;

    // ===== Mock external DEX =====

    /// Stub for a real DEX call. Given `coin_in`, "swaps" at `rate_num /
    /// rate_den` ratio. In a real adaptor (e.g. Cetus) this would be a
    /// `cetus_pool::swap_a_for_b(coin_in, ctx)` call.
    #[allow(lint(self_transfer))]
    fun swap_external<CoinIn, CoinOut>(
        coin_in: Coin<CoinIn>,
        rate_num: u64,
        rate_den: u64,
        ctx: &mut TxContext,
    ): Coin<CoinOut> {
        assert!(rate_den > 0, EInvalidRate);
        let amount_in = coin::value(&coin_in);
        let amount_out = amount_in * rate_num / rate_den;
        coin::burn_for_testing(coin_in);
        coin::mint_for_testing<CoinOut>(amount_out, ctx)
    }

    // ===== User-facing entry =====

    /// Full Mode D round-trip in one PTB:
    ///   pull `amount_in` of CoinIn → external swap → push CoinOut back.
    ///
    /// Aborts with `intent::EAuthMissing` if user didn't grant_service_coin.
    /// Aborts with `intent::ESwapSlippageExceeded` if swap returned less
    /// than `min_amount_out`. Aborts with `intent::ESwapAmountMismatch` if
    /// the receipt amount diverges from the actual coin_out value.
    public fun do_swap<CoinIn, CoinOut>(
        wallet: &mut Wallet,
        amount_in: u64,
        min_amount_out: u64,
        rate_num: u64,
        rate_den: u64,
        ctx: &mut TxContext,
    ) {
        assert!(amount_in > 0, EZeroAmount);

        // ----- Step 1 — issue SwapSig (signed by service witness) -----
        // Only this module can construct `MockSwap{}` → only this module can
        // produce a SwapSig keyed by MockSwap. The intent module accepts any
        // adaptor that can sign its own witness.
        let sig = intent::request_swap<MockSwap, CoinIn, CoinOut>(
            MockSwap {},
            amount_in,
            min_amount_out,
        );

        // ----- Step 2 — wallet validates + releases Coin<CoinIn> -----
        // Inside validate_and_swap_out:
        //   - asserts wallet.auth[MockSwap] contains CoinIn   (Gate 2)
        //   - debits ctx.sender's per-service MockSwap allowance   (Gate 3)
        //   - debits ctx.sender's per-coin CoinIn allowance         (Gate 4)
        //   - withdraws `amount_in` of CoinIn from the wallet's SIP-58
        //     accumulator at wallet.signer.id.to_address()
        //   - returns Coin<CoinIn> + WalletSwapWitness for receipt pairing
        let (coin_in, wallet_swap_witness) =
            intent::validate_and_swap_out<MockSwap, CoinIn, CoinOut>(
                wallet, sig, ctx,
            );

        // ----- Step 3 — external swap (the adaptor's real work) -----
        // In a real adaptor: cetus_pool::swap(coin_in, ctx).
        // Here: mocked at fixed rate.
        let coin_out = swap_external<CoinIn, CoinOut>(
            coin_in, rate_num, rate_den, ctx,
        );
        let amount_out = coin::value(&coin_out);

        // ----- Step 4 — issue ServiceSwapReceipt (signed by witness) -----
        // The receipt carries amount_out (what we actually got from the
        // external swap). Step 5 will assert this matches both the wallet's
        // expectation (wallet_swap_witness.amount_in == receipt.amount_in)
        // and the on-PTB Coin object value.
        let receipt = intent::create_swap_receipt<MockSwap, CoinIn, CoinOut>(
            MockSwap {},
            amount_in,
            amount_out,
        );

        // ----- Step 5 — wallet credits Coin<CoinOut> back -----
        // Inside verify_swap_and_credit:
        //   - asserts wallet_swap_witness.amount_in == receipt.amount_in
        //   - asserts coin_out.value() == receipt.amount_out
        //   - asserts receipt.amount_out >= wallet_swap_witness.min_amount_out
        //   - pushes coin_out into wallet.signer's SIP-58 address balance
        //   - emits SwapVerified event
        intent::verify_swap_and_credit<MockSwap, CoinIn, CoinOut>(
            wallet,
            wallet_swap_witness,
            receipt,
            coin_out,
        );
    }
}

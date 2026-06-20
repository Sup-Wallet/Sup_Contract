module SupWallet::intent {
    use std::type_name::{Self, TypeName};
    use sui::{
        coin::{Self, Coin},
        event,
    };
    use SupWallet::wallet::{Self, Wallet};
    use SupWallet::delegate;

    const EAuthMissing: u64 = 0;
    const EAmountMismatch: u64 = 1;
    const ERecipientMismatch: u64 = 2;
    const ESwapAmountMismatch: u64 = 3;
    const ESwapSlippageExceeded: u64 = 4;

    /// Mode discriminator carried on `PaymentValidated` / `SwapValidated`. The
    /// hot-potato types themselves are already distinct, so this is just for
    /// event consumers.
    const MODE_SELF: u8 = 0;        // sender (delegate or main_owner) pays from own allowances
    const MODE_FOR_PAYER: u8 = 1;   // service designates which spender's allowances to debit
    const MODE_UNMETERED: u8 = 2;   // no allowance debit; only is_authorized gate
    const MODE_SWAP: u8 = 3;        // internal swap: CoinIn out → CoinOut back, no recipient

    /// ===== events =====

    public struct PaymentValidated has copy, drop {
        wallet_id: ID,
        service: TypeName,
        mode: u8,
        payer: Option<address>,
        recipient: address,
        amount: u64,
    }

    public struct PaymentVerified has copy, drop {
        service: TypeName,
        amount: u64,
        recipient: address,
    }

    /// Mode D — internal swap. CoinIn flowed out of the wallet, CoinOut
    /// flowed back in. Emitted at both validate and verify steps so indexers
    /// can pair them by wallet_id + spender + amount_in.
    public struct SwapValidated has copy, drop {
        wallet_id: ID,
        service: TypeName,
        coin_in: TypeName,
        coin_out: TypeName,
        spender: address,
        amount_in: u64,
        min_amount_out: u64,
    }

    public struct SwapVerified has copy, drop {
        wallet_id: ID,
        service: TypeName,
        coin_in: TypeName,
        coin_out: TypeName,
        amount_in: u64,
        amount_out: u64,
    }

    /// ===== hot-potato request types =====
    ///
    /// Each `request_payment_*` produces a distinct hot-potato so the validate side is
    /// paired by type. All three converge on the same `WalletWitness` / `ServiceReceiptSig`
    /// for the receipt-side flow.

    /// Mode A: sender spends their own per-service + per-coin allowances. Sender is the payer.
    /// Sender may be a registered delegate (allowances debited) or `main_owner` (unlimited).
    public struct ServiceSig<phantom ServiceT, phantom CoinType> {
        amount: u64,
        recipient: address,
    }

    /// Mode B: service module designates `payer`; that payer's allowances are debited.
    /// Used by pull-payment models where the charger (sender) differs from the payer.
    public struct ServiceSigForPayer<phantom ServiceT, phantom CoinType> {
        amount: u64,
        recipient: address,
        payer: address,
    }

    /// Mode C: no allowance debit. Authorisation comes solely from `wallet::is_authorized`.
    /// The service module is expected to enforce its own access logic (caps, time windows, etc).
    public struct ServiceSigUnmetered<phantom ServiceT, phantom CoinType> {
        amount: u64,
        recipient: address,
    }

    /// Hot potato issued by the wallet on payment. Must be consumed by `verify_and_clear`.
    public struct WalletWitness<phantom ServiceT, phantom CoinType> {
        amount: u64,
        recipient: address,
    }

    /// Hot potato issued by the service after accepting the coin. Consumed by `verify_and_clear`.
    public struct ServiceReceiptSig<phantom ServiceT, phantom CoinType> {
        amount: u64,
        recipient: address,
    }

    /// ===== getters (WalletWitness — read by service modules) =====

    public fun wallet_witness_amount<ServiceT, CoinType>(w: &WalletWitness<ServiceT, CoinType>): u64 {
        w.amount
    }

    public fun wallet_witness_recipient<ServiceT, CoinType>(w: &WalletWitness<ServiceT, CoinType>): address {
        w.recipient
    }

    /// ===== Mode A: sender spends own allowance =====

    public fun request_payment<ServiceT: drop, CoinType>(
        _witness: ServiceT,
        amount: u64,
        recipient: address,
    ): ServiceSig<ServiceT, CoinType> {
        ServiceSig { amount, recipient }
    }

    /// Three-layer authorization:
    ///   1. `wallet.auth[ServiceT]` must contain `CoinType` (owner allowlisted)
    ///   2. sender must be `main_owner` (unlimited) or a delegate with per-service allowance
    ///   3. delegate must also have per-coin universal allowance for `CoinType`
    /// main_owner bypasses (2) and (3).
    public fun validate_and_pay<ServiceT, CoinType>(
        wallet: &mut Wallet,
        service_sig: ServiceSig<ServiceT, CoinType>,
        ctx: &mut TxContext,
    ): (Coin<CoinType>, WalletWitness<ServiceT, CoinType>) {
        assert!(wallet::is_authorized<ServiceT, CoinType>(wallet), EAuthMissing);

        let ServiceSig { amount, recipient } = service_sig;
        let spender = ctx.sender();
        delegate::debit_service_allowance<ServiceT>(wallet, spender, amount);
        delegate::debit_coin_allowance<CoinType>(wallet, spender, amount);

        let coin = wallet::pay_by_service<ServiceT, CoinType>(wallet, amount, ctx);
        let wallet_witness = WalletWitness<ServiceT, CoinType> { amount, recipient };

        event::emit(PaymentValidated {
            wallet_id: wallet::id(wallet),
            service: type_name::with_defining_ids<ServiceT>(),
            mode: MODE_SELF,
            payer: option::some(spender),
            recipient,
            amount,
        });

        (coin, wallet_witness)
    }

    /// ===== Mode B: service designates payer =====

    public fun request_payment_for_payer<ServiceT: drop, CoinType>(
        _witness: ServiceT,
        amount: u64,
        recipient: address,
        payer: address,
    ): ServiceSigForPayer<ServiceT, CoinType> {
        ServiceSigForPayer { amount, recipient, payer }
    }

    /// Same auth gates as Mode A, but the allowance debits target the service-designated
    /// `payer` rather than `ctx.sender()`. The owner's prior `set_*_allowance(payer, N)`
    /// is the consent: it authorises the service to pull up to `N` from that payer.
    public fun validate_and_pay_for_payer<ServiceT, CoinType>(
        wallet: &mut Wallet,
        service_sig: ServiceSigForPayer<ServiceT, CoinType>,
        ctx: &mut TxContext,
    ): (Coin<CoinType>, WalletWitness<ServiceT, CoinType>) {
        assert!(wallet::is_authorized<ServiceT, CoinType>(wallet), EAuthMissing);

        let ServiceSigForPayer { amount, recipient, payer } = service_sig;
        delegate::debit_service_allowance<ServiceT>(wallet, payer, amount);
        delegate::debit_coin_allowance<CoinType>(wallet, payer, amount);

        let coin = wallet::pay_by_service<ServiceT, CoinType>(wallet, amount, ctx);
        let wallet_witness = WalletWitness<ServiceT, CoinType> { amount, recipient };

        event::emit(PaymentValidated {
            wallet_id: wallet::id(wallet),
            service: type_name::with_defining_ids<ServiceT>(),
            mode: MODE_FOR_PAYER,
            payer: option::some(payer),
            recipient,
            amount,
        });

        (coin, wallet_witness)
    }

    /// ===== Mode C: unmetered (auth-grant-only) =====

    public fun request_payment_unmetered<ServiceT: drop, CoinType>(
        _witness: ServiceT,
        amount: u64,
        recipient: address,
    ): ServiceSigUnmetered<ServiceT, CoinType> {
        ServiceSigUnmetered { amount, recipient }
    }

    /// No allowance debit. Routes through the hot-potato flow so the receipt-side check
    /// still runs and a `PaymentValidated` event is always emitted. The service module
    /// is the sole gatekeeper of *when* a Mode-C payment is appropriate — typical use is
    /// inheritance / cap-gated payouts.
    public fun validate_and_pay_unmetered<ServiceT, CoinType>(
        wallet: &mut Wallet,
        service_sig: ServiceSigUnmetered<ServiceT, CoinType>,
        ctx: &mut TxContext,
    ): (Coin<CoinType>, WalletWitness<ServiceT, CoinType>) {
        assert!(wallet::is_authorized<ServiceT, CoinType>(wallet), EAuthMissing);

        let ServiceSigUnmetered { amount, recipient } = service_sig;

        let coin = wallet::pay_by_service<ServiceT, CoinType>(wallet, amount, ctx);
        let wallet_witness = WalletWitness<ServiceT, CoinType> { amount, recipient };

        event::emit(PaymentValidated {
            wallet_id: wallet::id(wallet),
            service: type_name::with_defining_ids<ServiceT>(),
            mode: MODE_UNMETERED,
            payer: option::none(),
            recipient,
            amount,
        });

        (coin, wallet_witness)
    }

    /// ===== shared receipt verification =====

    /// Service module, after accepting the paid coin, issues a receipt signature.
    /// Witness-gated like `request_payment_*` — only the defining module can produce one.
    public fun create_receipt_sig<ServiceT: drop, CoinType>(
        _witness: ServiceT,
        amount: u64,
        recipient: address,
    ): ServiceReceiptSig<ServiceT, CoinType> {
        ServiceReceiptSig { amount, recipient }
    }

    /// Wallet verifies the receipt against its witness and clears both hot potatoes.
    /// Aborts if amount or recipient disagree.
    public fun verify_and_clear<ServiceT, CoinType>(
        wallet_witness: WalletWitness<ServiceT, CoinType>,
        receipt_sig: ServiceReceiptSig<ServiceT, CoinType>,
    ) {
        let WalletWitness { amount: w_amount, recipient: w_recipient } = wallet_witness;
        let ServiceReceiptSig { amount: r_amount, recipient: r_recipient } = receipt_sig;
        assert!(w_amount == r_amount, EAmountMismatch);
        assert!(w_recipient == r_recipient, ERecipientMismatch);

        event::emit(PaymentVerified {
            service: type_name::with_defining_ids<ServiceT>(),
            amount: w_amount,
            recipient: w_recipient,
        });
    }

    /// ===== Mode D: internal swap (CoinIn → CoinOut, no recipient) =====
    ///
    /// Use case: adaptor pulls `CoinIn` from the wallet, performs an
    /// external swap (e.g. Cetus / Bucket PSM), and pushes the resulting
    /// `CoinOut` back into the same wallet. There is no third-party
    /// recipient — the wallet pays itself in a different coin type.
    ///
    /// Flow:
    ///   1. adaptor: `request_swap(witness, amount_in, min_amount_out)` → `SwapSig`
    ///   2. adaptor: `validate_and_swap_out(wallet, sig, ctx)`
    ///        → `(Coin<CoinIn>, WalletSwapWitness)` (CoinIn debited; allowances
    ///        consumed against CoinIn side only — CoinOut crediting is
    ///        unrestricted symmetrically with normal deposit semantics)
    ///   3. adaptor performs external swap → `Coin<CoinOut>`
    ///   4. adaptor: `create_swap_receipt(witness, amount_in, amount_out)`
    ///        → `ServiceSwapReceipt`
    ///   5. adaptor: `verify_swap_and_credit(wallet, ww, receipt, coin_out)`
    ///        → asserts amount_out matches `coin_out.value()` and
    ///        ≥ `min_amount_out`; pushes `coin_out` back into wallet via
    ///        `wallet::receive_from_service_internal`.

    public struct SwapSig<phantom ServiceT, phantom CoinIn, phantom CoinOut> {
        amount_in: u64,
        min_amount_out: u64,
    }

    public struct WalletSwapWitness<phantom ServiceT, phantom CoinIn, phantom CoinOut> {
        amount_in: u64,
        min_amount_out: u64,
    }

    public struct ServiceSwapReceipt<phantom ServiceT, phantom CoinIn, phantom CoinOut> {
        amount_in: u64,
        amount_out: u64,
    }

    public fun wallet_swap_witness_amount_in<ServiceT, CoinIn, CoinOut>(
        w: &WalletSwapWitness<ServiceT, CoinIn, CoinOut>,
    ): u64 {
        w.amount_in
    }

    public fun wallet_swap_witness_min_amount_out<ServiceT, CoinIn, CoinOut>(
        w: &WalletSwapWitness<ServiceT, CoinIn, CoinOut>,
    ): u64 {
        w.min_amount_out
    }

    /// Step 1: adaptor mints the swap intent.
    public fun request_swap<ServiceT: drop, CoinIn, CoinOut>(
        _witness: ServiceT,
        amount_in: u64,
        min_amount_out: u64,
    ): SwapSig<ServiceT, CoinIn, CoinOut> {
        SwapSig { amount_in, min_amount_out }
    }

    /// Step 2: wallet validates + releases `Coin<CoinIn>`.
    ///
    /// Auth gates (mirrors Mode A but only checks the CoinIn side, since
    /// CoinOut is being **credited**, not spent — symmetric with the
    /// principle that crediting an account never harms it):
    ///   1. `wallet.auth[ServiceT]` must contain `CoinIn`
    ///   2. sender must be `main_owner` (unlimited) or a delegate with
    ///      per-service + per-CoinIn allowance
    public fun validate_and_swap_out<ServiceT, CoinIn, CoinOut>(
        wallet: &mut Wallet,
        swap_sig: SwapSig<ServiceT, CoinIn, CoinOut>,
        ctx: &mut TxContext,
    ): (Coin<CoinIn>, WalletSwapWitness<ServiceT, CoinIn, CoinOut>) {
        assert!(wallet::is_authorized<ServiceT, CoinIn>(wallet), EAuthMissing);

        let SwapSig { amount_in, min_amount_out } = swap_sig;
        let spender = ctx.sender();
        delegate::debit_service_allowance<ServiceT>(wallet, spender, amount_in);
        delegate::debit_coin_allowance<CoinIn>(wallet, spender, amount_in);

        let coin = wallet::pay_by_service<ServiceT, CoinIn>(wallet, amount_in, ctx);
        let wsw = WalletSwapWitness<ServiceT, CoinIn, CoinOut> { amount_in, min_amount_out };

        event::emit(SwapValidated {
            wallet_id: wallet::id(wallet),
            service: type_name::with_defining_ids<ServiceT>(),
            coin_in: type_name::with_defining_ids<CoinIn>(),
            coin_out: type_name::with_defining_ids<CoinOut>(),
            spender,
            amount_in,
            min_amount_out,
        });

        (coin, wsw)
    }

    /// Step 4: adaptor signs receipt after external swap.
    public fun create_swap_receipt<ServiceT: drop, CoinIn, CoinOut>(
        _witness: ServiceT,
        amount_in: u64,
        amount_out: u64,
    ): ServiceSwapReceipt<ServiceT, CoinIn, CoinOut> {
        ServiceSwapReceipt { amount_in, amount_out }
    }

    /// Step 5: wallet verifies + credits `Coin<CoinOut>` back.
    ///
    /// The typed `ServiceSwapReceipt<ServiceT, ...>` already proves the
    /// adaptor's authority (only the defining module of `ServiceT` could
    /// have constructed it via `create_swap_receipt`), so no separate
    /// runtime witness arg is needed. Credit lands via the package-internal
    /// `wallet::receive_from_service_internal`.
    public fun verify_swap_and_credit<ServiceT, CoinIn, CoinOut>(
        wallet: &mut Wallet,
        wallet_witness: WalletSwapWitness<ServiceT, CoinIn, CoinOut>,
        receipt: ServiceSwapReceipt<ServiceT, CoinIn, CoinOut>,
        coin_out: Coin<CoinOut>,
    ) {
        let WalletSwapWitness {
            amount_in: w_in,
            min_amount_out,
        } = wallet_witness;
        let ServiceSwapReceipt {
            amount_in: r_in,
            amount_out: r_out,
        } = receipt;
        assert!(w_in == r_in, ESwapAmountMismatch);
        assert!(coin::value(&coin_out) == r_out, ESwapAmountMismatch);
        assert!(r_out >= min_amount_out, ESwapSlippageExceeded);

        let wallet_id = wallet::id(wallet);
        wallet::receive_from_service_internal<ServiceT, CoinOut>(wallet, coin_out);

        event::emit(SwapVerified {
            wallet_id,
            service: type_name::with_defining_ids<ServiceT>(),
            coin_in: type_name::with_defining_ids<CoinIn>(),
            coin_out: type_name::with_defining_ids<CoinOut>(),
            amount_in: r_in,
            amount_out: r_out,
        });
    }
}

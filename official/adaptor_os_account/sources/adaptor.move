// Copyright (c) ZZYZX Labs
// SPDX-License-Identifier: BUSL-1.1

/// Sup Wallet bridge for `os_account`.
///
/// The adapter only moves funds between Sup and an OS trading account. Trading
/// operations call `os_margin` / `os_perp` directly with `&mut OsAccount`.
module adaptor_os_account::adaptor {
    use std::string::String;
    use sui::clock::Clock;
    use sui::coin;
    use SupWallet::intent;
    use SupWallet::wallet::{Self, Wallet};
    use os_account::account::{Self, OsAccount};
    use os_account::registry::WalletAccountRegistry;

    /// Service witness. Users grant this service per coin type on Sup Wallet.
    public struct OsAccountAdaptor has drop {}

    const EWrongParent: u64 = 0;

    /// Create a new OsAccount owned by `sup_wallet`. Registers it under the
    /// wallet's identity in `WalletAccountRegistry` so off-chain (and other
    /// on-chain helpers) can `list_accounts(wallet_identity)` to enumerate
    /// all sub-accounts of this Sup Wallet (Batch 5c sub-accounts).
    ///
    /// If `initial_deposit_amount > 0`, the funded path is taken: account
    /// is built by-value, deposit happens, then register + share. If 0,
    /// we delegate to `account::create_and_share_for` for the simple path.
    public fun create_os_account<T>(
        sup_wallet: &mut Wallet,
        registry: &mut WalletAccountRegistry,
        name: Option<String>,
        max_leverage_bps: u64,
        initial_deposit_amount: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): ID {
        let wallet_identity = wallet::identity(sup_wallet);

        if (initial_deposit_amount == 0) {
            // No deposit — clean path via account module helper.
            return account::create_and_share_for(
                registry,
                wallet_identity,
                name,
                max_leverage_bps,
                clock,
                ctx,
            )
        };

        // Funded path: account must be built by-value so we can deposit
        // BEFORE sharing. Sharing consumes the by-value handle.
        let acc = account::new(
            wallet_identity,
            name,
            max_leverage_bps,
            clock,
            ctx,
        );
        let acc_id = account::id(&acc);
        let signer_addr = account::signer_address(&acc);

        let sig = intent::request_payment<OsAccountAdaptor, T>(
            OsAccountAdaptor {},
            initial_deposit_amount,
            signer_addr,
        );
        let (coin, ww) = intent::validate_and_pay<OsAccountAdaptor, T>(sup_wallet, sig, ctx);
        account::deposit_for_protocol<OsAccountAdaptor, T>(&acc, OsAccountAdaptor {}, coin);
        let receipt = intent::create_receipt_sig<OsAccountAdaptor, T>(
            OsAccountAdaptor {},
            initial_deposit_amount,
            signer_addr,
        );
        intent::verify_and_clear<OsAccountAdaptor, T>(ww, receipt);

        // Register-then-share via the account module's package-internal
        // path. We can't call `registry::register` directly (it's
        // public(package)) so the account module wraps it.
        account::register_and_share(registry, acc, wallet_identity);
        acc_id
    }

    public fun deposit<T>(
        sup_wallet: &mut Wallet,
        os_account: &OsAccount,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        assert_parent(sup_wallet, os_account);

        let signer_addr = account::signer_address(os_account);
        let sig = intent::request_payment<OsAccountAdaptor, T>(
            OsAccountAdaptor {},
            amount,
            signer_addr,
        );
        let (coin, ww) = intent::validate_and_pay<OsAccountAdaptor, T>(sup_wallet, sig, ctx);
        account::deposit_for_protocol<OsAccountAdaptor, T>(os_account, OsAccountAdaptor {}, coin);
        let receipt = intent::create_receipt_sig<OsAccountAdaptor, T>(
            OsAccountAdaptor {},
            amount,
            signer_addr,
        );
        intent::verify_and_clear<OsAccountAdaptor, T>(ww, receipt);
    }

    public fun withdraw<T>(
        sup_wallet: &mut Wallet,
        os_account: &mut OsAccount,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        assert_parent(sup_wallet, os_account);

        let sender = ctx.sender();
        if (!account::has_permission(os_account, sender, account::perm_withdraw())) {
            let req = wallet::sign(sup_wallet, ctx);
            account::assert_request(os_account, &req, account::perm_withdraw());
        };

        let bal = account::withdraw_for_protocol<OsAccountAdaptor, T>(
            os_account,
            OsAccountAdaptor {},
            amount,
        );
        let coin = coin::from_balance(bal, ctx);
        wallet::receive_from_service<OsAccountAdaptor, T>(sup_wallet, coin, OsAccountAdaptor {});
    }

    public fun assert_parent(sup_wallet: &Wallet, os_account: &OsAccount) {
        assert!(
            account::parent_wallet_identity(os_account) == wallet::identity(sup_wallet),
            EWrongParent,
        );
    }

    #[test_only]
    public fun wrong_parent_error(): u64 { EWrongParent }
}

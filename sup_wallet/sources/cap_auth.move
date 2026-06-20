/// # Cap-based principal — make a delegate "anything that can hold an object"
///
/// An **official auth rule** for `SupWallet::policy`. Instead of the principal
/// being an address (`ctx.sender()`), it is *whoever holds a `DelegateCap`
/// object*. Because `DelegateCap` has `store`, the holder can be:
///   - a plain address (owner mints + transfers it),
///   - a smart contract (the cap lives inside another object's field),
///   - a machine / agent (holds the key that owns the cap),
///   - a zkSend link or a hashlock escrow (the cap is wrapped, claimed later).
///
/// The cap proves *who*; the wallet's caveat rules (budget / recipient / time /
/// ...) still gate *what / how much*. This module is just one accepted entry in
/// a wallet's `auth_rules` (OR-gated), added by the owner via
/// `policy::add_auth_rule<CapAuth>`.
///
/// ## Revocation
/// A cap is bound to the policy `version` at mint time. `policy::revoke_all`
/// bumps the version, so every outstanding cap stops authenticating at once
/// (its `policy_version` no longer matches the request's snapshot). Per-cap
/// selective revocation is future work (a revocation set keyed by cap id).
///
/// ## Spend flow
/// ```move
/// let mut req = policy::begin_spend<CoinT>(&wallet, amount, recipient);
/// cap_auth::prove(&cap, &mut req);     // stamps CapAuth if cap is valid + current
/// // ... caveat rules stamp ...
/// policy::confirm_spend<CoinT>(&mut wallet, req, ctx);
/// ```
module SupWallet::cap_auth {
    use sui::{
        event,
    };
    use SupWallet::wallet::{Self, Wallet};
    use SupWallet::policy::{Self, SpendRequest};

    /// Cap was presented against a different wallet than it was minted for.
    const EWrongWallet: u64 = 1;
    /// Cap's policy version is stale — the owner revoked (bumped version) since mint.
    const ECapRevoked: u64 = 2;

    /// Transferable, storable bearer capability. Holding it = being the principal.
    /// Carries no spending limits itself; those are the wallet's caveat rules.
    public struct DelegateCap has key, store {
        id: UID,
        /// Wallet this cap authenticates against.
        wallet_id: ID,
        /// Policy version at mint. Must equal the request's snapshot to be valid.
        policy_version: u64,
    }

    /// Auth-rule witness. Only this module can build it, so only `prove` can
    /// stamp `CapAuth` onto a request.
    public struct CapAuth has drop {}

    public struct DelegateCapMinted has copy, drop {
        wallet_id: ID,
        cap_id: ID,
        policy_version: u64,
    }

    public struct DelegateCapBurned has copy, drop {
        wallet_id: ID,
        cap_id: ID,
    }

    /// ===== owner: mint =====

    /// Owner mints a cap bound to the wallet's current policy version and returns
    /// it for the caller's PTB to route (transfer to a delegate, wrap into a
    /// zkSend link, escrow under a hashlock, store inside a contract, ...).
    /// Requires the policy to be initialized.
    public fun mint(wallet: &Wallet, ctx: &mut TxContext): DelegateCap {
        wallet::assert_owner(wallet, ctx);
        let wallet_id = wallet::id(wallet);
        let policy_version = policy::version(wallet);
        let cap = DelegateCap { id: object::new(ctx), wallet_id, policy_version };
        event::emit(DelegateCapMinted { wallet_id, cap_id: object::id(&cap), policy_version });
        cap
    }

    /// Owner mints a cap and transfers it straight to `recipient`.
    public fun mint_and_transfer(wallet: &Wallet, recipient: address, ctx: &mut TxContext) {
        transfer::public_transfer(mint(wallet, ctx), recipient);
    }

    /// Holder discards their own cap. (Owner-side mass revocation is
    /// `policy::revoke_all`; this is just bearer cleanup.)
    public fun burn(cap: DelegateCap) {
        let DelegateCap { id, wallet_id, policy_version: _ } = cap;
        let cap_id = id.to_inner();
        event::emit(DelegateCapBurned { wallet_id, cap_id });
        id.delete();
    }

    /// ===== rule: prove principal =====

    /// Stamp `CapAuth` onto the request iff the cap targets the request's wallet
    /// and its version is still current. `prove` needs no `&Wallet`: the request's
    /// `policy_version` snapshot already equals the live version (otherwise
    /// `confirm_spend` aborts with stale-version), so matching against it both
    /// authenticates and enforces revocation.
    public fun prove(cap: &DelegateCap, req: &mut SpendRequest) {
        assert!(cap.wallet_id == policy::spend_wallet_id(req), EWrongWallet);
        assert!(cap.policy_version == policy::spend_policy_version(req), ECapRevoked);
        policy::add_auth_receipt(CapAuth {}, req);
    }

    /// ===== reads =====

    public fun cap_wallet_id(cap: &DelegateCap): ID { cap.wallet_id }

    public fun cap_policy_version(cap: &DelegateCap): u64 { cap.policy_version }

    /// True if this cap would still authenticate against `wallet` right now.
    public fun is_current(cap: &DelegateCap, wallet: &Wallet): bool {
        cap.wallet_id == wallet::id(wallet) && cap.policy_version == policy::version(wallet)
    }
}

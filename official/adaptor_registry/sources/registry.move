/// # Adaptor Registry — minimal on-chain discovery anchor (ERC-8004 style)
///
/// This is the **open-protocol discovery layer** for Sup Wallet adaptors. It is
/// deliberately *thin*: the chain stores only the **anchor** for each listing —
/// who published it, which package it points at, its witness service-type, and a
/// content-addressed pointer (`manifest_uri` + `manifest_hash`) to the rich
/// metadata that lives **off-chain** (Walrus / HTTP).
///
/// What is intentionally NOT on-chain (mirrors ERC-8004's hybrid model):
///   - the manifest body (docs, ops, fee, category, supported coins) → off-chain
///     at `manifest_uri`; integrity guaranteed by `manifest_hash`.
///   - reviews / star ratings → off-chain (subjective, sybil-prone, must iterate).
///   - usage / volume / unique-user reputation → DERIVED off-chain by indexing the
///     `SupWallet::intent` events (objective, hard to fake), not stored here.
///
/// Why on-chain at all (vs a DB): listings become **self-sovereign, portable, and
/// censorship-resistant** — any frontend can read the same registry by indexing
/// `Registered` / `Updated` / `Unlisted` events; the Sup team is not a gatekeeper;
/// publishers own their own entries. Security of *using* an adaptor is unchanged —
/// it is still enforced at runtime by `wallet` / `intent` (witness + typed
/// allowance). This registry is a directory, not a trust authority.
///
/// Anti-spoof: `service_type` is the adaptor's witness `TypeName` string, which is
/// namespaced by the defining package id (`type_name::with_defining_ids`). Nobody
/// can register another publisher's witness type and have it resolve to their
/// package. Listing keys are therefore globally unique by construction.
module adaptor_registry::registry {
    use std::string::String;
    use sui::{
        object::{Self, UID},
        tx_context::{Self, TxContext},
        transfer,
        table::{Self, Table},
        clock::{Self, Clock},
        event,
    };

    /// A `service_type` already has a live listing.
    const EAlreadyListed: u64 = 0;
    /// No listing exists for this `service_type`.
    const ENotListed: u64 = 1;
    /// Caller is not the publisher of this listing.
    const ENotPublisher: u64 = 2;
    /// Attestation score out of the 1..=5 range.
    const EBadScore: u64 = 3;

    /// Shared discovery object. Keyed by the adaptor's witness `service_type`
    /// (e.g. `0xPKG::adaptor::CetusAdaptor`). The table exists only to enforce
    /// publisher-gated updates and de-duplication — discovery itself is done by
    /// indexing events off-chain.
    public struct Registry has key {
        id: UID,
        entries: Table<String, Listing>,
    }

    /// Per-listing anchor. `store` only (lives inside the `entries` table).
    public struct Listing has store {
        /// Address that registered (and may update / unlist) this entry.
        publisher: address,
        /// The deployed adaptor Move package id this listing points at.
        package_id: address,
        /// Pointer to the off-chain manifest (Walrus blob id or URL).
        manifest_uri: String,
        /// Content hash of the manifest body — integrity for the off-chain blob.
        manifest_hash: vector<u8>,
        /// Bumped on each `update`.
        version: u64,
        updated_at_ms: u64,
    }

    /// ===== events (the discovery surface) =====

    public struct Registered has copy, drop {
        service_type: String,
        package_id: address,
        publisher: address,
        manifest_uri: String,
        manifest_hash: vector<u8>,
        version: u64,
        timestamp_ms: u64,
    }

    public struct Updated has copy, drop {
        service_type: String,
        package_id: address,
        publisher: address,
        manifest_uri: String,
        manifest_hash: vector<u8>,
        version: u64,
        timestamp_ms: u64,
    }

    public struct Unlisted has copy, drop {
        service_type: String,
        publisher: address,
        timestamp_ms: u64,
    }

    /// Lightweight reputation HOOK (ERC-8004 reputation-registry style). The
    /// score/comment carry no on-chain weight and are NOT stored — off-chain
    /// indexers decide how to weight an attestation (e.g. only count attesters
    /// that have real on-chain usage of `service_type`, recognise audit signers,
    /// etc.). Keeping it event-only avoids putting sybil-prone data into state.
    public struct Attested has copy, drop {
        service_type: String,
        attester: address,
        score: u8,
        comment_uri: String,
        timestamp_ms: u64,
    }

    /// Share the singleton registry at publish time.
    fun init(ctx: &mut TxContext) {
        transfer::share_object(Registry {
            id: object::new(ctx),
            entries: table::new<String, Listing>(ctx),
        });
    }

    /// ===== publisher: lifecycle =====

    /// Permissionless. Anyone who has deployed an adaptor package can list it.
    /// `service_type` must be the adaptor's witness type string; it is the unique
    /// key, so a given witness can be listed once (re-list via `update`).
    public fun register(
        registry: &mut Registry,
        package_id: address,
        service_type: String,
        manifest_uri: String,
        manifest_hash: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(!registry.entries.contains(service_type), EAlreadyListed);
        let publisher = ctx.sender();
        let now = clock.timestamp_ms();
        registry.entries.add(service_type, Listing {
            publisher,
            package_id,
            manifest_uri,
            manifest_hash,
            version: 1,
            updated_at_ms: now,
        });
        event::emit(Registered {
            service_type,
            package_id,
            publisher,
            manifest_uri,
            manifest_hash,
            version: 1,
            timestamp_ms: now,
        });
    }

    /// Publisher-gated. Re-point the package / refresh the manifest; bumps version.
    public fun update(
        registry: &mut Registry,
        service_type: String,
        package_id: address,
        manifest_uri: String,
        manifest_hash: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(registry.entries.contains(service_type), ENotListed);
        let listing = registry.entries.borrow_mut(service_type);
        assert!(listing.publisher == ctx.sender(), ENotPublisher);
        let now = clock.timestamp_ms();
        listing.package_id = package_id;
        listing.manifest_uri = manifest_uri;
        listing.manifest_hash = manifest_hash;
        listing.version = listing.version + 1;
        listing.updated_at_ms = now;
        event::emit(Updated {
            service_type,
            package_id,
            publisher: listing.publisher,
            manifest_uri,
            manifest_hash,
            version: listing.version,
            timestamp_ms: now,
        });
    }

    /// Publisher-gated removal.
    public fun unlist(
        registry: &mut Registry,
        service_type: String,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(registry.entries.contains(service_type), ENotListed);
        let publisher = registry.entries.borrow(service_type).publisher;
        assert!(publisher == ctx.sender(), ENotPublisher);
        let Listing { publisher: _, package_id: _, manifest_uri: _, manifest_hash: _, version: _, updated_at_ms: _ } =
            registry.entries.remove(service_type);
        event::emit(Unlisted { service_type, publisher, timestamp_ms: clock.timestamp_ms() });
    }

    /// ===== reputation hook =====

    /// Anyone may attest; weighting/sybil-resistance is an off-chain concern.
    /// Emits only — no state written.
    public fun attest(
        registry: &Registry,
        service_type: String,
        score: u8,
        comment_uri: String,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        assert!(registry.entries.contains(service_type), ENotListed);
        assert!(score >= 1 && score <= 5, EBadScore);
        event::emit(Attested {
            service_type,
            attester: ctx.sender(),
            score,
            comment_uri,
            timestamp_ms: clock.timestamp_ms(),
        });
    }

    /// ===== read-only views =====

    public fun is_listed(registry: &Registry, service_type: String): bool {
        registry.entries.contains(service_type)
    }

    /// Returns (publisher, package_id, manifest_uri, manifest_hash, version, updated_at_ms).
    public fun listing(
        registry: &Registry,
        service_type: String,
    ): (address, address, String, vector<u8>, u64, u64) {
        let l = registry.entries.borrow(service_type);
        (l.publisher, l.package_id, l.manifest_uri, l.manifest_hash, l.version, l.updated_at_ms)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}

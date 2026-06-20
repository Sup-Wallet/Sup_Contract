/// # Policy Rule Registry — open discovery for delegation-policy rules
///
/// The marketplace anchor for `SupWallet::policy` rules, the sibling of
/// `adaptor_registry` (ERC-8004-style). Anyone who deploys a rule package — an
/// auth rule (a principal proof) or a caveat rule (a spending condition) — lists
/// it here permissionlessly: deploy, then `register` the rule's witness type +
/// package id + an off-chain manifest pointer. No PR, no gatekeeper.
///
/// Only the **anchor** is on-chain; the rich metadata (docs, params schema,
/// supported coins, audits) lives off-chain at `manifest_uri`, integrity-checked
/// by `manifest_hash`. Discovery is done by indexing the events. Using a rule is
/// still gated at runtime by the wallet owner: a rule has zero power until the
/// owner calls `policy::add_auth_rule<R>` / `policy::add_caveat_rule<R>` on their
/// own wallet. This registry is a directory, not a trust authority.
///
/// Anti-spoof: `rule_type` is the witness `TypeName` string, namespaced by its
/// defining package id (`type_name::with_defining_ids`), so nobody can register
/// another publisher's witness and have it resolve to their package.
module policy_rule_registry::registry {
    use std::string::String;
    use sui::{
        object::{Self, UID},
        tx_context::{Self, TxContext},
        transfer,
        table::{Self, Table},
        clock::{Self, Clock},
        event,
    };

    /// `kind` discriminator: where the owner should slot this rule.
    const KIND_AUTH: u8 = 0;
    const KIND_CAVEAT: u8 = 1;

    /// A `rule_type` already has a live listing.
    const EAlreadyListed: u64 = 0;
    /// No listing exists for this `rule_type`.
    const ENotListed: u64 = 1;
    /// Caller is not the publisher of this listing.
    const ENotPublisher: u64 = 2;
    /// `kind` outside the known set.
    const EBadKind: u64 = 3;
    /// Attestation score outside 1..=5.
    const EBadScore: u64 = 4;

    /// Shared discovery object, keyed by the rule's witness `rule_type` string.
    public struct Registry has key {
        id: UID,
        entries: Table<String, Listing>,
    }

    public struct Listing has store {
        publisher: address,
        package_id: address,
        /// KIND_AUTH or KIND_CAVEAT — tells a UI which policy set it belongs in.
        kind: u8,
        manifest_uri: String,
        manifest_hash: vector<u8>,
        version: u64,
        updated_at_ms: u64,
    }

    /// ===== events (the discovery surface) =====

    public struct Registered has copy, drop {
        rule_type: String,
        package_id: address,
        publisher: address,
        kind: u8,
        manifest_uri: String,
        manifest_hash: vector<u8>,
        version: u64,
        timestamp_ms: u64,
    }

    public struct Updated has copy, drop {
        rule_type: String,
        package_id: address,
        publisher: address,
        kind: u8,
        manifest_uri: String,
        manifest_hash: vector<u8>,
        version: u64,
        timestamp_ms: u64,
    }

    public struct Unlisted has copy, drop {
        rule_type: String,
        publisher: address,
        timestamp_ms: u64,
    }

    public struct Attested has copy, drop {
        rule_type: String,
        attester: address,
        score: u8,
        comment_uri: String,
        timestamp_ms: u64,
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(Registry {
            id: object::new(ctx),
            entries: table::new<String, Listing>(ctx),
        });
    }

    /// ===== publisher: lifecycle =====

    /// Permissionless. `rule_type` must be the rule's witness type string and is
    /// the unique key (re-list via `update`). `kind` is KIND_AUTH or KIND_CAVEAT.
    public fun register(
        registry: &mut Registry,
        package_id: address,
        rule_type: String,
        kind: u8,
        manifest_uri: String,
        manifest_hash: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(kind == KIND_AUTH || kind == KIND_CAVEAT, EBadKind);
        assert!(!registry.entries.contains(rule_type), EAlreadyListed);
        let publisher = ctx.sender();
        let now = clock.timestamp_ms();
        registry.entries.add(rule_type, Listing {
            publisher,
            package_id,
            kind,
            manifest_uri,
            manifest_hash,
            version: 1,
            updated_at_ms: now,
        });
        event::emit(Registered {
            rule_type,
            package_id,
            publisher,
            kind,
            manifest_uri,
            manifest_hash,
            version: 1,
            timestamp_ms: now,
        });
    }

    /// Publisher-gated. Re-point the package / refresh the manifest; bumps version.
    public fun update(
        registry: &mut Registry,
        rule_type: String,
        package_id: address,
        manifest_uri: String,
        manifest_hash: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(registry.entries.contains(rule_type), ENotListed);
        let listing = registry.entries.borrow_mut(rule_type);
        assert!(listing.publisher == ctx.sender(), ENotPublisher);
        let now = clock.timestamp_ms();
        listing.package_id = package_id;
        listing.manifest_uri = manifest_uri;
        listing.manifest_hash = manifest_hash;
        listing.version = listing.version + 1;
        listing.updated_at_ms = now;
        event::emit(Updated {
            rule_type,
            package_id,
            publisher: listing.publisher,
            kind: listing.kind,
            manifest_uri,
            manifest_hash,
            version: listing.version,
            timestamp_ms: now,
        });
    }

    /// Publisher-gated removal.
    public fun unlist(
        registry: &mut Registry,
        rule_type: String,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(registry.entries.contains(rule_type), ENotListed);
        let publisher = registry.entries.borrow(rule_type).publisher;
        assert!(publisher == ctx.sender(), ENotPublisher);
        let Listing { publisher: _, package_id: _, kind: _, manifest_uri: _, manifest_hash: _, version: _, updated_at_ms: _ } =
            registry.entries.remove(rule_type);
        event::emit(Unlisted { rule_type, publisher, timestamp_ms: clock.timestamp_ms() });
    }

    /// ===== reputation hook (event-only; weighting is off-chain) =====

    public fun attest(
        registry: &Registry,
        rule_type: String,
        score: u8,
        comment_uri: String,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        assert!(registry.entries.contains(rule_type), ENotListed);
        assert!(score >= 1 && score <= 5, EBadScore);
        event::emit(Attested {
            rule_type,
            attester: ctx.sender(),
            score,
            comment_uri,
            timestamp_ms: clock.timestamp_ms(),
        });
    }

    /// ===== read-only views =====

    public fun is_listed(registry: &Registry, rule_type: String): bool {
        registry.entries.contains(rule_type)
    }

    /// Returns (publisher, package_id, kind, manifest_uri, manifest_hash, version, updated_at_ms).
    public fun listing(
        registry: &Registry,
        rule_type: String,
    ): (address, address, u8, String, vector<u8>, u64, u64) {
        let l = registry.entries.borrow(rule_type);
        (l.publisher, l.package_id, l.kind, l.manifest_uri, l.manifest_hash, l.version, l.updated_at_ms)
    }

    public fun kind_auth(): u8 { KIND_AUTH }
    public fun kind_caveat(): u8 { KIND_CAVEAT }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}

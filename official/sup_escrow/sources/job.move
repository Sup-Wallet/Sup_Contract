/// # sup_escrow::job — assessor-gated escrow for agent-to-agent commerce (ERC-8183)
///
/// A `Job<CoinT>` holds funds until an **assessor** judges delivery. It is the
/// settlement leg of "the wallet for the agent economy": an owner's agent can
/// *hire and pay another agent*, but the payment only releases when a condition
/// (delivery) is provably met — and the funds are escrowed *through* the wallet's
/// delegation policy, so the amount is bounded by the owner's allowance.
///
/// ## Two policy-shaped moments
///   1. **Fund** — the coin comes from `SupWallet::policy::confirm_spend_into`
///      (a policy-gated spend that RETURNS the coin), so funding a job can never
///      exceed the owner's caps. `fund` just deposits that coin.
///   2. **Release** — gated exactly like the delegation policy: `begin_release`
///      emits a `ReleaseRequest` hot potato carrying the job's facts; an
///      **assessor rule** stamps it (witness-gated, like an auth rule) and sets
///      the outcome; `confirm_release` pays the provider (approve) or refunds the
///      payer (reject) iff the trusted assessor stamped.
///
/// **The assessor is just another rule.** Which assessor a job trusts is its
/// `assessor_type` (a witness `TypeName`, chosen by the owner at `create`). Only
/// the module defining that witness can stamp, so "who may release escrow" is as
/// pluggable as "who may delegate": an owner, a bearer cap, an oracle, a ZK
/// proof, another agent — each is a tiny rule package. `cap_assessor` is the
/// reference one.
module sup_escrow::job {
    use std::type_name::{Self, TypeName};
    use std::string::{Self, String};
    use sui::{
        balance::{Self, Balance},
        coin::{Self, Coin},
        object::{Self, ID, UID},
        tx_context::{Self, TxContext},
        transfer,
        vec_set::{Self, VecSet},
        event,
    };
    use SupWallet::wallet::{Self, Wallet};

    /// Job lifecycle states.
    const S_OPEN: u8 = 0;       // created, not yet funded
    const S_FUNDED: u8 = 1;     // coin escrowed, awaiting delivery
    const S_SUBMITTED: u8 = 2;  // provider marked delivered, awaiting assessment
    const S_RELEASED: u8 = 3;   // paid to provider (terminal)
    const S_REFUNDED: u8 = 4;   // returned to payer (terminal)

    /// Action attempted from the wrong state.
    const EWrongState: u64 = 1;
    /// Caller is not the wallet owner / payer.
    const ENotOwner: u64 = 2;
    /// Caller is not the provider.
    const ENotProvider: u64 = 3;
    /// The trusted assessor did not stamp the release request.
    const EAssessorNotProven: u64 = 4;
    /// The release request belongs to a different job.
    const EWrongJob: u64 = 5;
    /// Funding coin has zero value.
    const EZeroAmount: u64 = 6;

    /// Escrowed job. Shared so the provider and the assessor can act on it.
    public struct Job<phantom CoinT> has key {
        id: UID,
        /// Wallet that funded the job (for audit / refund routing).
        wallet_id: ID,
        /// Owner address — refunds return here.
        payer: address,
        /// Provider address — paid on approval.
        provider: address,
        /// Witness `TypeName` of the assessor the owner trusts to settle.
        assessor_type: TypeName,
        amount: u64,
        state: u8,
        funds: Balance<CoinT>,
        /// Provider's delivery note / URI, set at submit — tamper-proof evidence
        /// for the assessor to judge against.
        note: String,
    }

    /// Hot potato carrying the facts an assessor judges. No abilities: a
    /// `ReleaseRequest` must reach `confirm_release` or the tx aborts. Mirrors
    /// `SupWallet::policy::SpendRequest`.
    public struct ReleaseRequest {
        job_id: ID,
        provider: address,
        amount: u64,
        /// Set by the assessor via `judge`: true = pay provider, false = refund payer.
        approve: bool,
        /// Assessor witnesses that stamped (the trusted one must be present).
        stamps: VecSet<TypeName>,
    }

    public struct JobCreated has copy, drop { job_id: ID, wallet_id: ID, provider: address, assessor_type: TypeName }
    public struct JobFunded has copy, drop { job_id: ID, amount: u64 }
    public struct JobSubmitted has copy, drop { job_id: ID, note: String }
    public struct JobReleased has copy, drop { job_id: ID, provider: address, amount: u64 }
    public struct JobRefunded has copy, drop { job_id: ID, payer: address, amount: u64 }

    /// ===== owner: create =====

    /// Owner opens a job for `provider`, trusting assessor witness `AssessorT`.
    /// Funded separately via `fund` (typically with a `confirm_spend_into` coin).
    public fun create<CoinT, AssessorT>(
        wallet: &Wallet,
        provider: address,
        ctx: &mut TxContext,
    ): Job<CoinT> {
        assert!(tx_context::sender(ctx) == wallet::owner(wallet), ENotOwner);
        let job = Job<CoinT> {
            id: object::new(ctx),
            wallet_id: wallet::id(wallet),
            payer: wallet::owner(wallet),
            provider,
            assessor_type: type_name::with_defining_ids<AssessorT>(),
            amount: 0,
            state: S_OPEN,
            funds: balance::zero<CoinT>(),
            note: string::utf8(b""),
        };
        event::emit(JobCreated {
            job_id: object::id(&job),
            wallet_id: job.wallet_id,
            provider,
            assessor_type: job.assessor_type,
        });
        job
    }

    #[allow(lint(share_owned))]
    public fun create_and_share<CoinT, AssessorT>(wallet: &Wallet, provider: address, ctx: &mut TxContext) {
        transfer::share_object(create<CoinT, AssessorT>(wallet, provider, ctx));
    }

    /// ===== fund =====

    /// Deposit the escrow coin. Permissionless to *call* — the coin itself is the
    /// authority, and in practice it comes from `policy::confirm_spend_into`, so
    /// the amount is already bounded by the owner's delegation caps.
    public fun fund<CoinT>(job: &mut Job<CoinT>, coin: Coin<CoinT>) {
        assert!(job.state == S_OPEN, EWrongState);
        let v = coin::value(&coin);
        assert!(v > 0, EZeroAmount);
        balance::join(&mut job.funds, coin::into_balance(coin));
        job.amount = v;
        job.state = S_FUNDED;
        event::emit(JobFunded { job_id: object::id(job), amount: v });
    }

    /// ===== provider: submit delivery =====

    public fun submit<CoinT>(job: &mut Job<CoinT>, note: String, ctx: &TxContext) {
        assert!(tx_context::sender(ctx) == job.provider, ENotProvider);
        assert!(job.state == S_FUNDED, EWrongState);
        job.note = note;
        job.state = S_SUBMITTED;
        event::emit(JobSubmitted { job_id: object::id(job), note });
    }

    /// ===== payer: cancel before delivery =====

    /// Owner pulls funds back while the provider has not yet delivered.
    public fun cancel<CoinT>(job: &mut Job<CoinT>, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == job.payer, ENotOwner);
        assert!(job.state == S_FUNDED, EWrongState);
        let to = job.payer;
        let amt = job.amount;
        let jid = object::id(job);
        payout(job, to, ctx);
        job.state = S_REFUNDED;
        event::emit(JobRefunded { job_id: jid, payer: to, amount: amt });
    }

    /// ===== release flow (assessor-gated, mirrors the delegation policy) =====

    /// Begin assessment. Permissionless to *call*; inert until the trusted
    /// assessor stamps it. Only valid once the provider has submitted.
    public fun begin_release<CoinT>(job: &Job<CoinT>): ReleaseRequest {
        assert!(job.state == S_SUBMITTED, EWrongState);
        ReleaseRequest {
            job_id: object::id(job),
            provider: job.provider,
            amount: job.amount,
            approve: false,
            stamps: vec_set::empty<TypeName>(),
        }
    }

    /// Witness-gated. An assessor module stamps its own `AssessorT` after judging
    /// delivery, and sets the outcome (`approve` = pay provider, else refund).
    /// Only the module defining `AssessorT` can build it, so it cannot be forged.
    public fun judge<AssessorT: drop>(_witness: AssessorT, req: &mut ReleaseRequest, approve: bool) {
        let key = type_name::with_defining_ids<AssessorT>();
        if (!req.stamps.contains(&key)) { req.stamps.insert(key); };
        req.approve = approve;
    }

    /// Settle the job: aborts unless the request is for this job and the job's
    /// trusted assessor stamped. Pays the provider (approve) or refunds the payer.
    public fun confirm_release<CoinT>(job: &mut Job<CoinT>, req: ReleaseRequest, ctx: &mut TxContext) {
        let ReleaseRequest { job_id, provider: _, amount: _, approve, stamps } = req;
        assert!(job_id == object::id(job), EWrongJob);
        assert!(job.state == S_SUBMITTED, EWrongState);
        assert!(stamps.contains(&job.assessor_type), EAssessorNotProven);

        let amt = job.amount;
        if (approve) {
            let to = job.provider;
            payout(job, to, ctx);
            job.state = S_RELEASED;
            event::emit(JobReleased { job_id, provider: to, amount: amt });
        } else {
            let to = job.payer;
            payout(job, to, ctx);
            job.state = S_REFUNDED;
            event::emit(JobRefunded { job_id, payer: to, amount: amt });
        }
    }

    /// ===== reads (for assessor rules) =====

    public fun request_job_id(req: &ReleaseRequest): ID { req.job_id }
    public fun request_provider(req: &ReleaseRequest): address { req.provider }
    public fun request_amount(req: &ReleaseRequest): u64 { req.amount }

    public fun job_state<CoinT>(job: &Job<CoinT>): u8 { job.state }
    public fun job_amount<CoinT>(job: &Job<CoinT>): u64 { job.amount }
    public fun job_provider<CoinT>(job: &Job<CoinT>): address { job.provider }
    public fun job_payer<CoinT>(job: &Job<CoinT>): address { job.payer }
    public fun job_assessor_type<CoinT>(job: &Job<CoinT>): TypeName { job.assessor_type }
    public fun job_note<CoinT>(job: &Job<CoinT>): String { job.note }

    /// ===== internal =====

    fun payout<CoinT>(job: &mut Job<CoinT>, to: address, ctx: &mut TxContext) {
        let b = balance::withdraw_all(&mut job.funds);
        transfer::public_transfer(coin::from_balance(b, ctx), to);
    }
}

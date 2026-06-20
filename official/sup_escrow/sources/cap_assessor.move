/// # sup_escrow::cap_assessor — a reference assessor rule (bearer cap)
///
/// The simplest worked **assessor**: whoever holds the `AssessorCap` bound to a
/// job may settle it (approve → pay provider, reject → refund payer). It mirrors
/// `SupWallet::cap_auth` exactly — the cap proves *who may assess*, the witness
/// stamps the release request — proving the point that **an assessor is just
/// another rule**. Swap this module for an oracle / ZK / multi-sig assessor and
/// the `job` core is unchanged; only `assessor_type` (chosen at `create`) differs.
///
/// The owner (the job's payer) mints the cap and hands it to whoever judges
/// delivery — themselves, a human reviewer, or another agent.
module sup_escrow::cap_assessor {
    use sui::{
        event,
        object::{Self, ID, UID},
        tx_context::{Self, TxContext},
        transfer,
    };
    use sup_escrow::job::{Self, Job, ReleaseRequest};

    /// This cap is bound to a different job than the request being settled.
    const EWrongJob: u64 = 1;
    /// Only the job's payer (owner) may mint an assessor cap for it.
    const ENotOwner: u64 = 2;

    /// Bearer cap: holding it (bound to `job_id`) grants the right to assess.
    public struct AssessorCap has key, store { id: UID, job_id: ID }

    /// Assessor-rule witness. Only this module can build it.
    public struct CapAssessor has drop {}

    public struct AssessorCapMinted has copy, drop { cap_id: ID, job_id: ID }

    /// Owner mints a cap bound to their job. Gated to the payer so nobody can mint
    /// an assessor cap for someone else's job.
    public fun mint<CoinT>(job: &Job<CoinT>, ctx: &mut TxContext): AssessorCap {
        assert!(tx_context::sender(ctx) == job::job_payer(job), ENotOwner);
        let cap = AssessorCap { id: object::new(ctx), job_id: object::id(job) };
        event::emit(AssessorCapMinted { cap_id: object::id(&cap), job_id: cap.job_id });
        cap
    }

    public fun mint_and_transfer<CoinT>(job: &Job<CoinT>, recipient: address, ctx: &mut TxContext) {
        transfer::public_transfer(mint(job, ctx), recipient);
    }

    /// Stamp the release request as `CapAssessor` iff this cap is bound to its
    /// job. `approve` = pay the provider; otherwise refund the payer.
    public fun assess(cap: &AssessorCap, req: &mut ReleaseRequest, approve: bool) {
        assert!(cap.job_id == job::request_job_id(req), EWrongJob);
        job::judge(CapAssessor {}, req, approve);
    }

    public fun cap_job_id(cap: &AssessorCap): ID { cap.job_id }
}

#[test_only]
module sup_escrow::escrow_tests;

use sup_escrow::job::{Self, Job};
use sup_escrow::cap_assessor::{Self, AssessorCap, CapAssessor};
use SupWallet::wallet::{Self, Wallet};
use SupWallet::policy;
use SupWallet::cap_auth::{Self, DelegateCap, CapAuth};
use sui::{
    coin::{Self, Coin},
    sui::SUI,
    test_scenario::{Self as ts, Scenario},
};

const ALICE: address = @0xA;    // owner / payer
const PROVIDER: address = @0xB; // paid on delivery
const ASSESSOR: address = @0xC; // holds the assessor cap (judges delivery)
const BOB: address = @0xD;      // policy delegate (for the policy-funded test)

fun test_sui(ts: &mut Scenario, amount: u64): Coin<SUI> {
    coin::mint_for_testing(amount, ts.ctx())
}

fun deposit(w: &Wallet, coin: Coin<SUI>) {
    coin::send_funds(coin, wallet::identity(w));
}

/// Open a funded, submitted job (assessor = CapAssessor) with the cap minted to
/// ASSESSOR. Funds with a plain test coin (focus on escrow mechanics). Returns id.
fun funded_submitted_job(scenario: &mut Scenario, amount: u64): ID {
    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    let wid = ts::most_recent_id_shared<Wallet>().destroy_some();
    let w = ts::take_shared_by_id<Wallet>(scenario, wid);
    job::create_and_share<SUI, CapAssessor>(&w, PROVIDER, scenario.ctx());
    ts::return_shared(w);

    // Owner funds the job and mints the assessor cap to ASSESSOR.
    scenario.next_tx(ALICE);
    let jid = ts::most_recent_id_shared<Job<SUI>>().destroy_some();
    let mut j = ts::take_shared_by_id<Job<SUI>>(scenario, jid);
    job::fund(&mut j, test_sui(scenario, amount));
    cap_assessor::mint_and_transfer(&j, ASSESSOR, scenario.ctx());
    ts::return_shared(j);

    // Provider marks delivery.
    scenario.next_tx(PROVIDER);
    let mut j2 = ts::take_shared_by_id<Job<SUI>>(scenario, jid);
    job::submit(&mut j2, std::string::utf8(b"walrus://deliverable"), scenario.ctx());
    ts::return_shared(j2);

    jid
}

#[test]
fun approve_pays_provider() {
    let mut scenario = ts::begin(ALICE);
    let jid = funded_submitted_job(&mut scenario, 60);

    scenario.next_tx(ASSESSOR);
    {
        let mut j = ts::take_shared_by_id<Job<SUI>>(&scenario, jid);
        let cap: AssessorCap = scenario.take_from_address(ASSESSOR);
        let mut req = job::begin_release(&j);
        cap_assessor::assess(&cap, &mut req, true); // approve
        job::confirm_release(&mut j, req, scenario.ctx());
        assert!(job::job_state(&j) == 3, 0); // S_RELEASED
        ts::return_to_sender(&scenario, cap);
        ts::return_shared(j);
    };

    scenario.next_tx(PROVIDER);
    {
        let paid: Coin<SUI> = scenario.take_from_address(PROVIDER);
        assert!(coin::value(&paid) == 60, 0);
        ts::return_to_sender(&scenario, paid);
    };

    ts::end(scenario);
}

#[test]
fun reject_refunds_payer() {
    let mut scenario = ts::begin(ALICE);
    let jid = funded_submitted_job(&mut scenario, 45);

    scenario.next_tx(ASSESSOR);
    {
        let mut j = ts::take_shared_by_id<Job<SUI>>(&scenario, jid);
        let cap: AssessorCap = scenario.take_from_address(ASSESSOR);
        let mut req = job::begin_release(&j);
        cap_assessor::assess(&cap, &mut req, false); // reject
        job::confirm_release(&mut j, req, scenario.ctx());
        assert!(job::job_state(&j) == 4, 0); // S_REFUNDED
        ts::return_to_sender(&scenario, cap);
        ts::return_shared(j);
    };

    // Refund went to ALICE (payer).
    scenario.next_tx(ALICE);
    {
        let refunded: Coin<SUI> = scenario.take_from_address(ALICE);
        assert!(coin::value(&refunded) == 45, 0);
        ts::return_to_sender(&scenario, refunded);
    };

    ts::end(scenario);
}

/// Without the trusted assessor stamping, settlement aborts (EAssessorNotProven).
#[test]
#[expected_failure(abort_code = 4, location = sup_escrow::job)]
fun unassessed_release_aborts() {
    let mut scenario = ts::begin(ALICE);
    let jid = funded_submitted_job(&mut scenario, 10);

    scenario.next_tx(ASSESSOR);
    {
        let mut j = ts::take_shared_by_id<Job<SUI>>(&scenario, jid);
        let req = job::begin_release(&j);
        // never assessed -> EAssessorNotProven (4)
        job::confirm_release(&mut j, req, scenario.ctx());
        ts::return_shared(j);
    };

    ts::end(scenario);
}

/// The headline: a job funded *through the delegation policy* — the escrow
/// amount is bounded by the owner's allowance via `confirm_spend_into`.
#[test]
fun funded_through_policy_spend() {
    let mut scenario = ts::begin(ALICE);

    // Wallet with a balance + a cap-based policy; BOB holds the delegate cap; a
    // job is opened for PROVIDER.
    wallet::create(scenario.ctx());
    scenario.next_tx(ALICE);
    let wid = ts::most_recent_id_shared<Wallet>().destroy_some();
    let mut w = ts::take_shared_by_id<Wallet>(&scenario, wid);
    deposit(&w, test_sui(&mut scenario, 100));
    policy::initialize(&mut w, scenario.ctx());
    policy::add_auth_rule<CapAuth>(&mut w, scenario.ctx());
    cap_auth::mint_and_transfer(&w, BOB, scenario.ctx());
    job::create_and_share<SUI, CapAssessor>(&w, PROVIDER, scenario.ctx());
    ts::return_shared(w);

    scenario.next_tx(ALICE);
    let jid = ts::most_recent_id_shared<Job<SUI>>().destroy_some();

    // BOB (delegate) funds the job from the vault, bounded by policy: the coin
    // comes back from confirm_spend_into and is deposited into the job.
    scenario.next_tx(BOB);
    {
        let mut w2 = ts::take_shared_by_id<Wallet>(&scenario, wid);
        let mut j = ts::take_shared_by_id<Job<SUI>>(&scenario, jid);
        let cap: DelegateCap = scenario.take_from_address(BOB);
        let mut req = policy::begin_spend<SUI>(&w2, 70, PROVIDER);
        cap_auth::prove(&cap, &mut req);
        let escrow_coin = policy::confirm_spend_into<SUI>(&mut w2, req, scenario.ctx());
        job::fund(&mut j, escrow_coin);
        assert!(job::job_state(&j) == 1, 0);   // S_FUNDED
        assert!(job::job_amount(&j) == 70, 0);
        ts::return_to_sender(&scenario, cap);
        ts::return_shared(j);
        ts::return_shared(w2);
    };

    ts::end(scenario);
}

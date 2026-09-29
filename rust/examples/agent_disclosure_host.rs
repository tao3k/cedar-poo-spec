//! Offline, process-local Host execution of the Lean-composed disclosure policy.

use cedar_poo_bridge::ValidatedManifest;
use cedar_poo_bridge::authority_consumption::{AuthorityGrant, AuthorityId, AuthorityLedger};
use cedar_poo_bridge::disclosure_host::{
    Effect, Evidence, Grant, InMemoryDisclosureHost, ValidatedDisclosurePolicy,
};
use cedar_poo_bridge::operation_identity::OperationId;
use serde_json::json;
use std::{env, fs, process, sync::Arc, thread};

const HOSPITAL: &str = "Dataset::\"hospital-patients\"";
const RESEARCH: &str = "Dataset::\"research-patients\"";
const SINK: &str = "DisclosureSink::\"study-workspace\"";
const STEWARD: &str = "Actor::\"clinical-steward\"";
const AGENT: &str = "Actor::\"analytics-agent\"";
const ACTION: &str = "Action::\"publish-derived-result\"";

fn grant(source: &str) -> Grant {
    Grant {
        issuer: STEWARD.into(),
        grantee: AGENT.into(),
        action: ACTION.into(),
        source: source.into(),
        destination: SINK.into(),
        purpose: "study-one".into(),
        revision: 0,
        expires_at: 10,
    }
}

fn evidence() -> Evidence {
    Evidence {
        epoch: 0,
        policy_revision: 0,
        approval_revision: 0,
        delegation_revision: 0,
        now: 1,
        budget: 2,
        trusted_sources: vec![HOSPITAL.into(), RESEARCH.into()],
        trusted_owner: STEWARD.into(),
        allowed_destinations: vec![SINK.into()],
        observed_digest: "cohort-first".into(),
        observed_candidate_ids: ["p1", "p2", "p3", "p4"].map(str::to_owned).to_vec(),
        approvals: vec![grant(HOSPITAL), grant(RESEARCH)],
        delegations: vec![grant(HOSPITAL), grant(RESEARCH)],
        possible_ids: (1..=6).map(|n| format!("p{n}")).collect(),
        minimum_cohort: 3,
        audit_ready: true,
    }
}

fn effect(operation_id: &str, digest: &str, channel: &str, candidates: &[&str]) -> Effect {
    Effect {
        operation_id: OperationId::from(operation_id),
        sources: vec![HOSPITAL.into(), RESEARCH.into()],
        destination: SINK.into(),
        purpose: "study-one".into(),
        channel: channel.into(),
        payload_digest: digest.into(),
        candidate_ids: candidates.iter().map(|id| (*id).into()).collect(),
    }
}

fn authority(first: &Effect, independent: &Effect, second: &Effect) -> AuthorityLedger<Effect> {
    AuthorityLedger {
        grants: [
            ("approval-first", first),
            ("approval-retry", first),
            ("approval-independent", independent),
            ("approval-second", second),
        ]
        .into_iter()
        .map(|(id, effect)| AuthorityGrant {
            id: AuthorityId::from(id),
            effect: effect.clone(),
            max_uses: 1,
            used: 0,
        })
        .collect(),
    }
}

fn run() -> Result<(), String> {
    let path = env::args().nth(1).ok_or("expected Lean manifest path")?;
    let manifest: ValidatedManifest =
        serde_json::from_slice(&fs::read(path).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
    let policy = ValidatedDisclosurePolicy::from_manifest(&manifest)?;
    let first = effect(
        "release-one",
        "cohort-first",
        "workspace",
        &["p1", "p2", "p3", "p4"],
    );
    let independent = effect(
        "release-independent",
        "cohort-first",
        "workspace",
        &["p1", "p2", "p3", "p4"],
    );
    let second = effect(
        "release-two",
        "cohort-second",
        "message",
        &["p3", "p4", "p5", "p6"],
    );
    let host = InMemoryDisclosureHost::new(
        &policy,
        evidence(),
        authority(&first, &independent, &second),
    );
    let ticket = host
        .prepare(AuthorityId::from("approval-first"), first.clone())?
        .ok_or("first release was denied")?;
    let stale = host
        .prepare(AuthorityId::from("approval-first"), first.clone())?
        .ok_or("racing prepare was denied")?;
    let mut changed_channel = first.clone();
    changed_channel.channel = "message".into();
    if host.commit(ticket.clone(), &changed_channel)?.is_some() {
        return Err("changed channel consumed the ticket".into());
    }
    let receipt = host
        .commit(ticket, &first)?
        .ok_or("first commit was denied")?;
    if host.commit(stale, &first)?.is_some() {
        return Err("stale racing ticket committed".into());
    }
    let fresh_reissue_denied = host
        .prepare(AuthorityId::from("approval-first"), first.clone())?
        .is_none();
    if !fresh_reissue_denied
        || host.authority_used(&AuthorityId::from("approval-first"))? != Some(1)
    {
        return Err("a fresh ticket reused the consumed approval".into());
    }

    let cross_approval_replay_denied = host
        .prepare(AuthorityId::from("approval-retry"), first.clone())?
        .is_none()
        && host.authority_used(&AuthorityId::from("approval-retry"))? == Some(0)
        && host.operation_admitted(&OperationId::from("release-one"))?;
    if !cross_approval_replay_denied {
        return Err("a new approval replayed the same workflow operation".into());
    }

    let separate = InMemoryDisclosureHost::new(
        &policy,
        evidence(),
        authority(&first, &independent, &second),
    );
    let first_independent = separate
        .prepare(AuthorityId::from("approval-first"), first.clone())?
        .ok_or("first independent preparation denied")?;
    separate
        .commit(first_independent, &first)?
        .ok_or("first independent commit denied")?;
    let other_ticket = separate
        .prepare(
            AuthorityId::from("approval-independent"),
            independent.clone(),
        )?
        .ok_or("distinct approval preparation denied")?;
    let distinct_approval_accepted = separate.commit(other_ticket, &independent)?.is_some()
        && separate.authority_used(&AuthorityId::from("approval-independent"))? == Some(1);
    if !distinct_approval_accepted {
        return Err("distinct approval could not use remaining budget".into());
    }

    let concurrent = Arc::new(InMemoryDisclosureHost::new(
        &policy,
        evidence(),
        authority(&first, &independent, &second),
    ));
    let attempts = (0..2)
        .map(|_| {
            let host = Arc::clone(&concurrent);
            let effect = first.clone();
            let ticket = host
                .prepare(AuthorityId::from("approval-first"), effect.clone())?
                .ok_or("parallel prepare denied")?;
            Ok(thread::spawn(move || host.commit(ticket, &effect)))
        })
        .collect::<Result<Vec<_>, String>>()?;
    let mut committed_parallel = 0;
    for attempt in attempts {
        if attempt
            .join()
            .map_err(|_| "parallel commit panicked")??
            .is_some()
        {
            committed_parallel += 1;
        }
    }
    let concurrent_single_commit = committed_parallel == 1 && concurrent.audit()?.len() == 1;
    if !concurrent_single_commit {
        return Err("parallel commits were not serialized".into());
    }
    host.observe_output(
        "cohort-second".into(),
        ["p3", "p4", "p5", "p6"].map(str::to_owned).to_vec(),
    )?;
    let cumulative_denied = host
        .prepare(AuthorityId::from("approval-second"), second.clone())?
        .is_none();
    if !cumulative_denied || host.audit()?.len() != 1 {
        return Err("cross-channel cumulative release was not denied".into());
    }

    let alone = InMemoryDisclosureHost::new(
        &policy,
        Evidence {
            observed_digest: "cohort-second".into(),
            observed_candidate_ids: ["p3", "p4", "p5", "p6"].map(str::to_owned).to_vec(),
            ..evidence()
        },
        authority(&first, &independent, &second),
    );
    let second_alone_allowed = alone
        .prepare(AuthorityId::from("approval-second"), second.clone())?
        .is_some();
    if !second_alone_allowed {
        return Err("independent second release was denied".into());
    }

    let revoked = InMemoryDisclosureHost::new(
        &policy,
        evidence(),
        authority(&first, &independent, &second),
    );
    let before_revoke = revoked
        .prepare(AuthorityId::from("approval-first"), first.clone())?
        .ok_or("revoke prepare was denied")?;
    revoked.revoke_delegation()?;
    let revoke_denied = revoked.commit(before_revoke, &first)?.is_none();
    if !revoke_denied || !revoked.audit()?.is_empty() {
        return Err("revoked delegation committed".into());
    }

    let failed_audit = InMemoryDisclosureHost::new(
        &policy,
        evidence(),
        authority(&first, &independent, &second),
    );
    let before_failure = failed_audit
        .prepare(AuthorityId::from("approval-first"), first.clone())?
        .ok_or("audit prepare was denied")?;
    failed_audit.set_audit_ready(false)?;
    let audit_failure_denied = failed_audit.commit(before_failure, &first)?.is_none();
    if !audit_failure_denied
        || !failed_audit.audit()?.is_empty()
        || failed_audit.authority_used(&AuthorityId::from("approval-first"))? != Some(0)
    {
        return Err("audit failure committed".into());
    }

    let mut wrong_issuer = evidence();
    wrong_issuer.approvals[0].issuer = "Actor::\"other-steward\"".into();
    let wrong_issuer_denied = InMemoryDisclosureHost::new(
        &policy,
        wrong_issuer,
        authority(&first, &independent, &second),
    )
    .prepare(AuthorityId::from("approval-first"), first.clone())?
    .is_none();
    if !wrong_issuer_denied {
        return Err("wrong grant issuer was accepted".into());
    }

    let mut substituted_candidates = evidence();
    substituted_candidates.observed_candidate_ids = ["p1", "p2"].map(str::to_owned).to_vec();
    let candidate_substitution_denied = InMemoryDisclosureHost::new(
        &policy,
        substituted_candidates,
        authority(&first, &independent, &second),
    )
    .prepare(AuthorityId::from("approval-first"), first.clone())?
    .is_none();
    if !candidate_substitution_denied {
        return Err("proposed candidate set overrode observed output".into());
    }

    let mut duplicate_authority = authority(&first, &independent, &second);
    duplicate_authority
        .grants
        .push(duplicate_authority.grants[0].clone());
    let duplicate_approval_denied =
        InMemoryDisclosureHost::new(&policy, evidence(), duplicate_authority)
            .prepare(AuthorityId::from("approval-first"), first.clone())?
            .is_none();
    if !duplicate_approval_denied {
        return Err("duplicate approval ID was accepted".into());
    }

    println!(
        "{}",
        json!({
            "committed": receipt,
            "secondAloneAllowed": second_alone_allowed,
            "cumulativeSecondDenied": cumulative_denied,
            "concurrentSingleCommit": concurrent_single_commit,
            "freshReissueDenied": fresh_reissue_denied,
            "crossApprovalReplayDenied": cross_approval_replay_denied,
            "distinctApprovalAccepted": distinct_approval_accepted,
            "duplicateApprovalDenied": duplicate_approval_denied,
            "revokedDenied": revoke_denied,
            "auditFailureDenied": audit_failure_denied,
            "wrongIssuerDenied": wrong_issuer_denied,
            "candidateSubstitutionDenied": candidate_substitution_denied,
            "auditEntries": host.audit()?.len(),
        })
    );
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        process::exit(1);
    }
}

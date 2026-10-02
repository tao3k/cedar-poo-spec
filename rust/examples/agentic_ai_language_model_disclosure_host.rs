//! Offline, process-local Host execution for a tool-using language-model system.

use cedar_poo_bridge::ValidatedManifest;
use cedar_poo_bridge::agentic_ai::boundary::SelectionDelta;
use cedar_poo_bridge::agentic_ai::language_model::disclosure_host::{
    Effect, Evidence, Grant, InMemoryDisclosureHost, RecipientGrant, ValidatedDisclosurePolicy,
};
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
        audience_revision: 0,
        now: 1,
        budget: 2,
        trusted_sources: vec![HOSPITAL.into(), RESEARCH.into()],
        trusted_owner: STEWARD.into(),
        allowed_destinations: vec![SINK.into()],
        current_recipients: vec!["researcher-a".into()],
        recipient_grants: [HOSPITAL, RESEARCH]
            .map(|source| RecipientGrant {
                source: source.into(),
                recipient: "researcher-a".into(),
            })
            .to_vec(),
        observed_digest: "cohort-first".into(),
        observed_candidate_ids: ["p1", "p2", "p3", "p4"].map(str::to_owned).to_vec(),
        observed_selection_delta: None,
        approvals: vec![grant(HOSPITAL), grant(RESEARCH)],
        delegations: vec![grant(HOSPITAL), grant(RESEARCH)],
        possible_ids: (1..=6).map(|n| format!("p{n}")).collect(),
        minimum_cohort: 3,
        audit_ready: true,
    }
}

fn effect(digest: &str, channel: &str, candidates: &[&str]) -> Effect {
    Effect {
        sources: vec![HOSPITAL.into(), RESEARCH.into()],
        destination: SINK.into(),
        purpose: "study-one".into(),
        channel: channel.into(),
        recipients: vec!["researcher-a".into()],
        payload_digest: digest.into(),
        candidate_ids: candidates.iter().map(|id| (*id).into()).collect(),
        selection_delta: None,
    }
}

fn run() -> Result<(), String> {
    let path = env::args().nth(1).ok_or("expected Lean manifest path")?;
    let manifest: ValidatedManifest =
        serde_json::from_slice(&fs::read(path).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
    let policy = ValidatedDisclosurePolicy::from_manifest(&manifest)?;
    let first = effect("cohort-first", "workspace", &["p1", "p2", "p3", "p4"]);
    let second = effect("cohort-second", "message", &["p3", "p4", "p5", "p6"]);
    let host = InMemoryDisclosureHost::new(&policy, evidence());
    let ticket = host
        .prepare(first.clone())?
        .ok_or("first release was denied")?;
    let stale = host
        .prepare(first.clone())?
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
    let concurrent = Arc::new(InMemoryDisclosureHost::new(&policy, evidence()));
    let attempts = (0..2)
        .map(|_| {
            let host = Arc::clone(&concurrent);
            let effect = first.clone();
            let ticket = host
                .prepare(effect.clone())?
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
    let concurrent_audit_count = concurrent.audit()?.len();
    let concurrent_single_commit = committed_parallel == 1 && concurrent_audit_count == 1;
    if !concurrent_single_commit {
        return Err(format!(
            "parallel commits were not serialized: committed={committed_parallel} audit={concurrent_audit_count}"
        ));
    }
    host.observe_output(
        "cohort-second".into(),
        ["p3", "p4", "p5", "p6"].map(str::to_owned).to_vec(),
    )?;
    let cumulative_denied = host.prepare(second.clone())?.is_none();
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
    );
    let second_alone_allowed = alone.prepare(second)?.is_some();
    if !second_alone_allowed {
        return Err("independent second release was denied".into());
    }

    let first_delta = SelectionDelta {
        before: (1..=6).map(|n| format!("p{n}")).collect(),
        after: ["p1", "p2", "p3", "p4"].map(str::to_owned).to_vec(),
    };
    let second_delta = SelectionDelta {
        before: (1..=6).map(|n| format!("p{n}")).collect(),
        after: ["p3", "p4", "p5", "p6"].map(str::to_owned).to_vec(),
    };
    let first_selection = Effect {
        selection_delta: Some(first_delta.clone()),
        ..effect("selection-first", "workspace", &["p1", "p2", "p3", "p4"])
    };
    let second_selection = Effect {
        selection_delta: Some(second_delta.clone()),
        ..effect("selection-second", "message", &["p3", "p4", "p5", "p6"])
    };
    let selection_host = InMemoryDisclosureHost::new(&policy, evidence());
    let unobserved_selection_denied = selection_host.prepare(first_selection.clone())?.is_none();
    selection_host.observe_selection("selection-first".into(), first_delta)?;
    let selection_ticket = selection_host
        .prepare(first_selection.clone())?
        .ok_or("observed selection was denied")?;
    let selection_receipt = selection_host
        .commit(selection_ticket, &first_selection)?
        .ok_or("observed selection commit was denied")?;
    selection_host.observe_selection("selection-second".into(), second_delta)?;
    let cumulative_selection_denied = selection_host.prepare(second_selection)?.is_none();
    if !unobserved_selection_denied
        || !selection_receipt.selection_mutation
        || !cumulative_selection_denied
        || selection_host.audit()?.len() != 1
    {
        return Err("selection mutation bypassed observation or cumulative state".into());
    }

    let revoked = InMemoryDisclosureHost::new(&policy, evidence());
    let before_revoke = revoked
        .prepare(first.clone())?
        .ok_or("revoke prepare was denied")?;
    revoked.revoke_delegation()?;
    let revoke_denied = revoked.commit(before_revoke, &first)?.is_none();
    if !revoke_denied || !revoked.audit()?.is_empty() {
        return Err("revoked delegation committed".into());
    }

    let changed_audience = InMemoryDisclosureHost::new(&policy, evidence());
    let audience_ticket = changed_audience
        .prepare(first.clone())?
        .ok_or("audience prepare was denied")?;
    changed_audience.replace_audience(vec!["researcher-a".into(), "outsider".into()])?;
    let audience_change_denied = changed_audience.commit(audience_ticket, &first)?.is_none()
        && changed_audience.prepare(first.clone())?.is_none()
        && changed_audience.audit()?.is_empty();
    if !audience_change_denied {
        return Err("expanded audience accepted an old or new ticket".into());
    }
    let revoked_recipient = InMemoryDisclosureHost::new(&policy, evidence());
    let recipient_ticket = revoked_recipient
        .prepare(first.clone())?
        .ok_or("recipient revocation prepare was denied")?;
    if !revoked_recipient.revoke_recipient_grant(RESEARCH, "researcher-a")? {
        return Err("research recipient grant was missing before revocation".into());
    }
    let recipient_revocation_denied = revoked_recipient
        .commit(recipient_ticket, &first)?
        .is_none()
        && revoked_recipient.prepare(first.clone())?.is_none()
        && revoked_recipient.audit()?.is_empty();
    if !recipient_revocation_denied {
        return Err("revoked source recipient grant accepted an old or new ticket".into());
    }
    let mut missing_recipient_grant = evidence();
    missing_recipient_grant.recipient_grants.pop();
    let missing_recipient_grant_denied =
        InMemoryDisclosureHost::new(&policy, missing_recipient_grant)
            .prepare(first.clone())?
            .is_none();
    if !missing_recipient_grant_denied {
        return Err("missing source recipient grant was accepted".into());
    }

    let failed_audit = InMemoryDisclosureHost::new(&policy, evidence());
    let before_failure = failed_audit
        .prepare(first.clone())?
        .ok_or("audit prepare was denied")?;
    failed_audit.set_audit_ready(false)?;
    let audit_failure_denied = failed_audit.commit(before_failure, &first)?.is_none();
    if !audit_failure_denied || !failed_audit.audit()?.is_empty() {
        return Err("audit failure committed".into());
    }

    let mut wrong_issuer = evidence();
    wrong_issuer.approvals[0].issuer = "Actor::\"other-steward\"".into();
    let wrong_issuer_denied = InMemoryDisclosureHost::new(&policy, wrong_issuer)
        .prepare(first.clone())?
        .is_none();
    if !wrong_issuer_denied {
        return Err("wrong grant issuer was accepted".into());
    }

    let mut substituted_candidates = evidence();
    substituted_candidates.observed_candidate_ids = ["p1", "p2"].map(str::to_owned).to_vec();
    let candidate_substitution_denied =
        InMemoryDisclosureHost::new(&policy, substituted_candidates)
            .prepare(first)?
            .is_none();
    if !candidate_substitution_denied {
        return Err("proposed candidate set overrode observed output".into());
    }

    println!(
        "{}",
        json!({
            "committed": receipt,
            "secondAloneAllowed": second_alone_allowed,
            "cumulativeSecondDenied": cumulative_denied,
            "concurrentSingleCommit": concurrent_single_commit,
            "revokedDenied": revoke_denied,
            "audienceChangeDenied": audience_change_denied,
            "recipientRevocationDenied": recipient_revocation_denied,
            "missingRecipientGrantDenied": missing_recipient_grant_denied,
            "auditFailureDenied": audit_failure_denied,
            "wrongIssuerDenied": wrong_issuer_denied,
            "candidateSubstitutionDenied": candidate_substitution_denied,
            "unobservedSelectionDenied": unobserved_selection_denied,
            "cumulativeSelectionDenied": cumulative_selection_denied,
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

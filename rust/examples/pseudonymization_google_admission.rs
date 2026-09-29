//! Offline Host admission and release with synthetic Google-shaped responses.

use cedar_poo_bridge::google_sdp::{SelectedTabularInput, WrappedKeyBinding};
use cedar_poo_bridge::google_sdp_host::{InMemoryGoogleSdpHost, TableEffect, TableEffectInput};
use cedar_poo_bridge::{ValidatedManifest, replay_validated_manifest};
use serde_json::{Value, json};
use std::{env, fs, process};

fn binding(selected: &SelectedTabularInput) -> WrappedKeyBinding {
    WrappedKeyBinding {
        key_domain: selected.key_domain.clone(),
        token_key_version: selected.token_key_version.clone(),
        wrapping_version: selected.wrapping_version.clone(),
        kms_key_name:
            "projects/synthetic-project/locations/us-central1/keyRings/test/cryptoKeys/dek".into(),
        wrapped_key_base64: "c3ludGhldGlj".into(),
    }
}

fn run() -> Result<(), String> {
    let paths = env::args().skip(1).collect::<Vec<_>>();
    if paths.len() != 4 {
        return Err("expected manifest, selected input, and two synthetic responses".into());
    }
    let manifest: ValidatedManifest =
        serde_json::from_slice(&fs::read(&paths[0]).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
    let selected_bytes = fs::read(&paths[1]).map_err(|e| e.to_string())?;
    let selected: SelectedTabularInput =
        serde_json::from_slice(&selected_bytes).map_err(|e| e.to_string())?;
    let deidentified = fs::read(&paths[2]).map_err(|e| e.to_string())?;
    let reidentified = fs::read(&paths[3]).map_err(|e| e.to_string())?;
    let policy = replay_validated_manifest(&manifest)?
        .into_iter()
        .find(|r| r.replay.case_name == "hospital-tokenize")
        .ok_or("missing tokenization replay")?
        .replay
        .policies_sha256;
    let mut host = InMemoryGoogleSdpHost::new(policy.clone(), 1);
    let parent = "projects/synthetic-project/locations/us-central1".to_owned();
    let prepare =
        |host: &InMemoryGoogleSdpHost, case: &str, effect: TableEffect, token: Option<String>| {
            host.prepare(
                &manifest,
                case,
                TableEffectInput {
                    selected: selected.clone(),
                    key: binding(&selected),
                    parent: parent.clone(),
                    effect,
                    token,
                },
            )
        };
    let (first, endpoint, request_bytes) =
        prepare(&host, "hospital-tokenize", TableEffect::Deidentify, None)?;
    let unissued_before_tokenization_rejected = prepare(
        &host,
        "steward-reidentify",
        TableEffect::Reidentify,
        Some("bG9uZy1zeW50aGV0aWMtY2lwaGVydGV4dA==".into()),
    )
    .is_err();
    let (racing, _, _) = prepare(&host, "hospital-tokenize", TableEffect::Deidentify, None)?;
    if !endpoint.ends_with("/content:deidentify") {
        return Err("wrong Google operation endpoint".into());
    }
    let request: Value = serde_json::from_slice(&request_bytes).map_err(|e| e.to_string())?;
    if request
        .pointer("/item/table/rows/0/values/0/stringValue")
        .and_then(Value::as_str)
        != Some(selected.value.as_str())
    {
        return Err("prepared request changed the selected input".into());
    }
    let checked = host.commit(first, &endpoint, &deidentified)?;
    let unissued_token_rejected = prepare(
        &host,
        "steward-reidentify",
        TableEffect::Reidentify,
        Some("bG9uZy1zeW50aGV0aWMtY2lwaGVydGV4dA==".into()),
    )
    .is_err();
    let stale_race_rejected = host.commit(racing, &endpoint, &deidentified).is_err();
    let denied_agent_rejected = prepare(
        &host,
        "agent-reidentify",
        TableEffect::Reidentify,
        Some(checked.value.clone()),
    )
    .is_err();
    let mut wrong_scope: SelectedTabularInput =
        serde_json::from_slice(&selected_bytes).map_err(|e| e.to_string())?;
    wrong_scope.context = "other-study".into();
    let wrong_scope_rejected = host
        .prepare(
            &manifest,
            "hospital-tokenize",
            TableEffectInput {
                selected: wrong_scope,
                key: binding(&selected),
                parent: parent.clone(),
                effect: TableEffect::Deidentify,
                token: None,
            },
        )
        .is_err();
    let (revoked, recovery_endpoint, _) = prepare(
        &host,
        "steward-reidentify",
        TableEffect::Reidentify,
        Some(checked.value.clone()),
    )?;
    host.revise_approval();
    let revoked_rejected = host
        .commit(revoked, &recovery_endpoint, &reidentified)
        .is_err();
    let (audit_fail, _, _) = prepare(
        &host,
        "steward-reidentify",
        TableEffect::Reidentify,
        Some(checked.value.clone()),
    )?;
    host.set_audit_ready(false);
    let audit_failure_rejected = host
        .commit(audit_fail, &recovery_endpoint, &reidentified)
        .is_err();
    host.set_audit_ready(true);
    let (tampered, _, _) = prepare(
        &host,
        "steward-reidentify",
        TableEffect::Reidentify,
        Some(checked.value.clone()),
    )?;
    let mut swapped: Value = serde_json::from_slice(&reidentified).map_err(|e| e.to_string())?;
    swapped["item"]["table"]["rows"][0]["values"][1]["stringValue"] = json!("other-study");
    let swapped_bytes = serde_json::to_vec(&swapped).map_err(|e| e.to_string())?;
    let response_swap_rejected = host
        .commit(tampered, &recovery_endpoint, &swapped_bytes)
        .is_err();
    let (wrong_endpoint, _, _) = prepare(
        &host,
        "steward-reidentify",
        TableEffect::Reidentify,
        Some(checked.value.clone()),
    )?;
    let endpoint_swap_rejected = host
        .commit(wrong_endpoint, &endpoint, &reidentified)
        .is_err();
    let (recovery, _, _) = prepare(
        &host,
        "steward-reidentify",
        TableEffect::Reidentify,
        Some(checked.value.clone()),
    )?;
    host.deploy_policy("superseded".into());
    let policy_change_rejected = host
        .commit(recovery, &recovery_endpoint, &reidentified)
        .is_err();
    host.deploy_policy(policy);
    let (recovery, endpoint, _) = prepare(
        &host,
        "steward-reidentify",
        TableEffect::Reidentify,
        Some(checked.value),
    )?;
    if !endpoint.ends_with("/content:reidentify") {
        return Err("wrong Google recovery endpoint".into());
    }
    let recovered = host.commit(recovery, &endpoint, &reidentified)?;
    if recovered.value != selected.value || host.audit().len() != 2 {
        return Err("offline recovery or digest audit differs".into());
    }
    if ![
        stale_race_rejected,
        unissued_before_tokenization_rejected,
        unissued_token_rejected,
        denied_agent_rejected,
        wrong_scope_rejected,
        revoked_rejected,
        audit_failure_rejected,
        response_swap_rejected,
        endpoint_swap_rejected,
        policy_change_rejected,
    ]
    .into_iter()
    .all(|rejected| rejected)
    {
        return Err("offline admission accepted a rejected scenario".into());
    }
    println!(
        "{}",
        json!({
            "kind": "offline-google-sdp-admission",
            "providerCalled": false,
            "staleRaceRejected": stale_race_rejected,
            "unissuedBeforeTokenizationRejected": unissued_before_tokenization_rejected,
            "unissuedTokenRejected": unissued_token_rejected,
            "deniedAgentRejected": denied_agent_rejected,
            "wrongScopeRejected": wrong_scope_rejected,
            "revokedRejected": revoked_rejected,
            "auditFailureRejected": audit_failure_rejected,
            "responseSwapRejected": response_swap_rejected,
            "endpointSwapRejected": endpoint_swap_rejected,
            "policyChangeRejected": policy_change_rejected,
            "auditEntries": host.audit().len(),
            "audits": host.audit(),
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

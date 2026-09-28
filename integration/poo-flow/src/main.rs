//! Fixed-revision parser and projection conformance. Synthetic Bootstrap
//! fields are test inputs and do not attest POO Flow ownership or Host effects.

use cedar_poo_bridge::{ValidatedManifest, load_policy_set, render_validated_policy_sources};
use poo_flow_cedar_authority::{
    canonical,
    projection::{Bootstrap, HandoffInput, Proposal, Snapshot},
};
use serde_json::json;
use std::{collections::BTreeMap, error::Error};

fn digest(byte: u8) -> String {
    format!("sha256:{}", format!("{byte:02x}").repeat(32))
}

fn proposal(case: &cedar_poo_bridge::Case) -> Result<Proposal, Box<dyn Error>> {
    Ok(serde_json::from_value(json!({
        "schema_id": "poo-flow.cedar-authorization-request.v1",
        "principal": case.request.principal,
        "action": case.request.action,
        "resource": case.request.resource,
        "context": case.request.context,
        "intent_digest": digest(8),
        "handoff": HandoffInput {
            sequence: 1,
            payload_hex: "00".into(),
            semantic_root: digest(9),
            before_execution_root: digest(10),
            after_execution_root: digest(11),
            observation_digest: digest(12),
        },
    }))?)
}

fn bootstrap(
    manifest: &ValidatedManifest,
    case: &cedar_poo_bridge::Case,
    sources: &BTreeMap<String, String>,
) -> Result<Bootstrap, Box<dyn Error>> {
    let policies = sources
        .iter()
        .map(|(identity, source)| json!({"identity": identity, "source": source}))
        .collect::<Vec<_>>();
    Ok(serde_json::from_value(json!({
        "schema_id": "poo-flow.cedar-authority-snapshot.v1",
        "producer": "poo-flow.scheme-control",
        "source": "modules/authorization/providers/cedar/objects.ss",
        "object_kind": "cedar-authority-snapshot",
        "provenance": {
            "composition_identity": "conformance.health.pseudonymization",
            "profile_identities": ["conformance.health"],
            "profile_origin_digest": digest(1),
            "governance_assessment_digest": digest(2),
            "subject_snapshot_digest": digest(3),
            "governance_admitted": true,
            "certification_names": ["PooFlowProof.Runtime.CedarNative"],
        },
        "authority_id": "conformance.authority",
        "runtime_context_id": "conformance.context",
        "runtime_generation": 1,
        "bundle_epoch": 1,
        "runtime_bundle_digest": digest(4),
        "profile_bundle_digest": digest(5),
        "independent_bundle_digest": digest(6),
        "capability_contract_digest": digest(7),
        "policy_revision": 1,
        "revocation_epoch": 0,
        "schema_json": manifest.schema.to_string(),
        "policies": policies,
        "entities_json": case.entities.to_string(),
        "capabilities": [
            {"action": "Action::\"tokenize\"", "event_kind": 1, "source_admission_required": false},
            {"action": "Action::\"join\"", "event_kind": 2, "source_admission_required": false},
            {"action": "Action::\"reidentify\"", "event_kind": 3, "source_admission_required": false},
        ],
    }))?)
}

/// Require the receiver input to name exactly the Lean-exported candidate.
/// Snapshot::new still owns Cedar parsing and reserved-context validation.
fn prepare_identified_candidate(
    bootstrap: Bootstrap,
    manifest: &ValidatedManifest,
    case: &cedar_poo_bridge::Case,
    sources: &BTreeMap<String, String>,
    expected_policy_digest: &str,
    proposal: &Proposal,
) -> Result<(), Box<dyn Error>> {
    if serde_json::from_str::<serde_json::Value>(&bootstrap.schema_json)? != manifest.schema
        || serde_json::from_str::<serde_json::Value>(&bootstrap.entities_json)? != case.entities
    {
        return Err("receiver schema or entities differ from the Lean artifact".into());
    }
    let mut projected = BTreeMap::new();
    for policy in &bootstrap.policies {
        if projected
            .insert(policy.identity.clone(), policy.source.clone())
            .is_some()
        {
            return Err("receiver contains a duplicate policy identity".into());
        }
    }
    if &projected != sources {
        return Err("receiver policies differ from the Lean artifact".into());
    }
    let prepared = Snapshot::new(bootstrap)?.prepare(proposal)?;
    if prepared.subject.policy_set_digest != expected_policy_digest {
        return Err("receiver changed the materialized Cedar policy set".into());
    }
    Ok(())
}

fn main() -> Result<(), Box<dyn Error>> {
    let path = std::env::args()
        .nth(1)
        .ok_or("usage: cedar-poo-flow-conformance MANIFEST")?;
    let manifest: ValidatedManifest = serde_json::from_str(&std::fs::read_to_string(path)?)?;
    let case = manifest
        .cases
        .iter()
        .find(|case| case.name == "hospital-tokenize")
        .ok_or("missing hospital-tokenize case")?;
    let sources = render_validated_policy_sources(&manifest, &case.name)?;
    let policies = load_policy_set(&case.policies)?;
    let mut by_id = BTreeMap::new();
    for policy in policies.policies() {
        by_id.insert(policy.id().to_string(), policy.to_json()?);
    }
    let expected_digest = canonical::digest("poo-flow/cedar/policy-set", &by_id)?;
    let base = bootstrap(&manifest, case, &sources)?;
    let request = proposal(case)?;
    prepare_identified_candidate(
        base.clone(),
        &manifest,
        case,
        &sources,
        &expected_digest,
        &request,
    )?;
    if sources.len() != 10 {
        return Err("expected ten materialized policies".into());
    }

    let mut changed_body = base.clone();
    let token = changed_body
        .policies
        .iter_mut()
        .find(|policy| policy.identity == "tokenize")
        .ok_or("missing tokenize source")?;
    token.source = token.source.replacen("permit", "forbid", 1);
    if token.source == sources["tokenize"] {
        return Err("policy-body mutation did not take effect".into());
    }
    let mut changed_id = base.clone();
    changed_id.policies[0].identity.push_str("-changed");
    let mut changed_entities = base.clone();
    changed_entities.entities_json = "[]".into();
    let mut changed_schema = base.clone();
    let mut schema: serde_json::Value = serde_json::from_str(&changed_schema.schema_json)?;
    schema["ConformanceOnly"] = json!({"entityTypes": {}, "actions": {}});
    changed_schema.schema_json = schema.to_string();

    let mut duplicate_id = base.clone();
    duplicate_id.policies.push(duplicate_id.policies[0].clone());
    for (label, candidate) in [
        ("policy body", changed_body),
        ("policy ID", changed_id),
        ("entities", changed_entities),
        ("schema", changed_schema),
        ("duplicate policy ID", duplicate_id),
    ] {
        if prepare_identified_candidate(
            candidate,
            &manifest,
            case,
            &sources,
            &expected_digest,
            &request,
        )
        .is_ok()
        {
            return Err(format!("{label} drift was accepted").into());
        }
    }

    let mut collided_schema = base;
    let mut schema: serde_json::Value = serde_json::from_str(&collided_schema.schema_json)?;
    schema[""]["actions"]["tokenize"]["appliesTo"]["context"]["attributes"]["poo_flow"] =
        json!({"type": "String"});
    collided_schema.schema_json = schema.to_string();
    if Snapshot::new(collided_schema).is_ok() {
        return Err("reserved context collision was admitted".into());
    }

    println!("POO-FLOW-CEDAR-PROJECTION-OK: {} policies", sources.len());
    Ok(())
}

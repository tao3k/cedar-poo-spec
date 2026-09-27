//! Parse official Cedar JSON and compare Rust authorization to Lean receipts.

use crate::CompiledPolicyJson;
use cedar_policy::{
    AuthorizationError, Authorizer, Context, Decision, Entities, EntityUid, PolicySet, Request,
};
use serde::Deserialize;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use std::str::FromStr;

/// Request fields emitted from the Lean Cedar model.
#[derive(Debug, Deserialize)]
pub struct RequestInput {
    pub principal: String,
    pub action: String,
    pub resource: String,
    pub context: Value,
}

/// One concrete authorization case and its Lean-computed receipt.
#[derive(Debug, Deserialize)]
pub struct Case {
    pub name: String,
    pub revision: String,
    pub policy_ids: Vec<String>,
    pub policies: CompiledPolicyJson,
    pub entities: Value,
    pub request: RequestInput,
    pub expected: String,
    pub expected_reasons: Vec<String>,
    pub expected_error_policies: Vec<String>,
}

/// Bundle of Lean-computed cases for the official Cedar engine.
#[derive(Debug, Deserialize)]
pub struct Manifest {
    pub cases: Vec<Case>,
}

/// Reject empty bundles, parse every policy set, and compare every decision.
pub fn check_manifest(manifest: &Manifest) -> Result<(), String> {
    if manifest.cases.is_empty() {
        return Err("manifest has no cases".into());
    }
    let mut names = BTreeSet::new();
    let mut revisions = BTreeMap::new();
    for case in &manifest.cases {
        if !names.insert(&case.name) {
            return Err(format!("duplicate case name: {}", case.name));
        }
        if !revisions.contains_key(&case.revision) {
            let checked =
                CheckedRevision::new(case).map_err(|error| format!("{}: {error}", case.name))?;
            revisions.insert(case.revision.clone(), checked);
        }
        let revision = &revisions[&case.revision];
        if revision.source != *case.policies.as_value() {
            return Err(format!("{}: conflicting revision output", case.revision));
        }
        check_case(case, &revision.policies, &revision.rendered)
            .map_err(|error| format!("{}: {error}", case.name))?;
    }
    render_artifacts(manifest)?;
    Ok(())
}

struct CheckedRevision {
    source: Value,
    policies: PolicySet,
    rendered: PolicySet,
}

impl CheckedRevision {
    fn new(case: &Case) -> Result<Self, String> {
        let policies = load_policy_set(&case.policies)?;
        let text = render_loaded_policy_set(&policies)?;
        let rendered = PolicySet::from_str(&text)
            .map_err(|error| format!("rendered Cedar text parse: {error}"))?;
        Ok(Self {
            source: case.policies.as_value().clone(),
            policies,
            rendered,
        })
    }
}

/// Replay Lean's requests against independently stored Cedar source files.
/// Cedar assigns source policy IDs, so policy bodies are compared without IDs.
pub fn check_direct_sources(manifest: &Manifest, directory: &Path) -> Result<(), String> {
    if manifest.cases.is_empty() {
        return Err("manifest has no cases".into());
    }
    let mut sources = BTreeMap::new();
    for case in &manifest.cases {
        let policies = direct_source(&mut sources, directory, case)?;
        check_direct_case(case, policies).map_err(|error| format!("{}: {error}", case.name))?;
    }
    Ok(())
}

fn direct_source<'a>(
    sources: &'a mut BTreeMap<String, PolicySet>,
    directory: &Path,
    case: &Case,
) -> Result<&'a PolicySet, String> {
    if case.revision.is_empty()
        || !case
            .revision
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || character == '-')
    {
        return Err(format!("{}: invalid revision name", case.name));
    }
    if !sources.contains_key(&case.revision) {
        let path = directory.join(format!("{}.cedar", case.revision));
        let text = std::fs::read_to_string(&path)
            .map_err(|error| format!("{}: {error}", path.display()))?;
        let policies =
            PolicySet::from_str(&text).map_err(|error| format!("{}: {error}", path.display()))?;
        sources.insert(case.revision.clone(), policies);
    }
    Ok(&sources[&case.revision])
}

fn check_direct_case(case: &Case, policies: &PolicySet) -> Result<(), String> {
    if policies.policies().count() != case.policy_ids.len() {
        return Err("direct policy count differs".into());
    }
    let compiled = load_policy_set(&case.policies)?;
    if !same_policy_bodies_ignoring_ids(policies, &compiled)? {
        return Err("direct policy bodies differ".into());
    }
    let entities = Entities::from_json_value(case.entities.clone(), None)
        .map_err(|error| format!("Cedar entities: {error}"))?;
    let uid = |value: &str| EntityUid::from_str(value).map_err(|error| error.to_string());
    let context = Context::from_json_value(case.request.context.clone(), None)
        .map_err(|error| format!("Cedar context: {error}"))?;
    let request = Request::new(
        uid(&case.request.principal)?,
        uid(&case.request.action)?,
        uid(&case.request.resource)?,
        context,
        None,
    )
    .map_err(|error| format!("Cedar request: {error}"))?;
    let response = Authorizer::new().is_authorized(&request, policies, &entities);
    let decision = match response.decision() {
        Decision::Allow => "allow",
        Decision::Deny => "deny",
    };
    let errors = response.diagnostics().errors().count();
    if decision != case.expected || errors != case.expected_error_policies.len() {
        return Err(format!(
            "direct Cedar expected {} with {} errors, got {} with {} errors",
            case.expected,
            case.expected_error_policies.len(),
            decision,
            errors
        ));
    }
    Ok(())
}

fn same_policy_bodies_ignoring_ids(left: &PolicySet, right: &PolicySet) -> Result<bool, String> {
    let body_counts = |policies: &PolicySet| -> Result<BTreeMap<String, usize>, String> {
        let mut counts = BTreeMap::new();
        for policy in policies.policies() {
            let json = policy
                .to_json()
                .map_err(|error| format!("Cedar policy JSON: {error}"))?;
            let normalized = cedar_policy::Policy::from_json(None, json)
                .map_err(|error| format!("Cedar policy normalization: {error}"))?;
            let body = normalized
                .to_cedar()
                .ok_or("normalized Cedar policy has no source")?;
            *counts.entry(body).or_insert(0) += 1;
        }
        Ok(counts)
    };
    Ok(body_counts(left)? == body_counts(right)?)
}

/// Load a Lean-POO compiled policy set through Cedar's public JSON parser.
pub fn load_policy_set(json: &CompiledPolicyJson) -> Result<PolicySet, String> {
    let object = json
        .as_value()
        .as_object()
        .ok_or("compiled policy artifact must be a JSON object")?;
    let static_policies = object
        .get("staticPolicies")
        .and_then(Value::as_object)
        .ok_or("compiled policy artifact needs staticPolicies")?;
    if !object
        .get("templates")
        .and_then(Value::as_object)
        .is_some_and(serde_json::Map::is_empty)
        || !object
            .get("templateLinks")
            .and_then(Value::as_array)
            .is_some_and(Vec::is_empty)
    {
        return Err("compiled policy artifact must contain only materialized policies".into());
    }
    let policies = PolicySet::from_json_value(json.as_value().clone())
        .map_err(|error| format!("Cedar policy parse: {error}"))?;
    let expected = static_policies.keys().cloned().collect::<BTreeSet<_>>();
    let loaded = policies
        .policies()
        .map(|policy| policy.id().to_string())
        .collect::<BTreeSet<_>>();
    if expected != loaded {
        return Err("Cedar loaded a different policy ID set".into());
    }
    Ok(policies)
}

/// Render an already admitted Cedar policy set without parsing JSON again.
pub fn render_loaded_policy_set(policies: &PolicySet) -> Result<String, String> {
    if policies.templates().next().is_some() {
        return Err("template source cannot render as a materialized policy file".into());
    }
    let mut rendered = policies
        .policies()
        .map(|policy| {
            let body = policy
                .to_cedar()
                .ok_or_else(|| "linked policy cannot render as Cedar text".to_owned())?;
            Ok((policy.id().to_string(), body))
        })
        .collect::<Result<Vec<_>, String>>()?;
    rendered.sort_by(|left, right| left.0.cmp(&right.0));
    let sections = rendered
        .into_iter()
        .map(|(id, body)| format!("// POO policy ID: {id}\n{body}"))
        .collect::<Vec<_>>();
    Ok(format!(
        "// Generated from Lean-POO. Cedar assigns new IDs when parsing this text.\n{}\n",
        sections.join("\n\n")
    ))
}

/// Render a compiled Lean policy set to a valid `.cedar` source file.
/// Cedar source comments retain the original IDs for readers.
pub fn render_policy_source(json: &CompiledPolicyJson) -> Result<String, String> {
    render_loaded_policy_set(&load_policy_set(json)?)
}

/// Render each revision to Cedar's human-readable policy language.
/// The original IDs remain in the JSON export; Cedar text cannot encode them.
pub fn render_artifacts(manifest: &Manifest) -> Result<BTreeMap<String, String>, String> {
    let mut artifacts: BTreeMap<String, (&Value, String)> = BTreeMap::new();
    for case in &manifest.cases {
        if case.revision.is_empty()
            || !case
                .revision
                .chars()
                .all(|character| character.is_ascii_alphanumeric() || character == '-')
        {
            return Err(format!("{}: invalid revision name", case.name));
        }
        match artifacts.entry(case.revision.clone()) {
            std::collections::btree_map::Entry::Occupied(entry) => {
                if entry.get().0 != case.policies.as_value() {
                    return Err(format!("{}: conflicting revision output", case.revision));
                }
            }
            std::collections::btree_map::Entry::Vacant(entry) => {
                let policies = load_policy_set(&case.policies)?;
                let artifact = render_loaded_policy_set(&policies)
                    .map_err(|error| format!("{}: {error}", case.name))?;
                entry.insert((case.policies.as_value(), artifact));
            }
        }
    }
    Ok(artifacts
        .into_iter()
        .map(|(revision, (_, artifact))| (revision, artifact))
        .collect())
}

fn check_case(case: &Case, policies: &PolicySet, rendered: &PolicySet) -> Result<(), String> {
    let expected_ids = case.policy_ids.iter().cloned().collect::<BTreeSet<_>>();
    let loaded_ids = policies
        .policies()
        .map(|policy| policy.id().to_string())
        .collect::<BTreeSet<_>>();
    if expected_ids.len() != case.policy_ids.len() || expected_ids != loaded_ids {
        return Err("loaded policy IDs differ from the Lean compilation".into());
    }
    let entities = Entities::from_json_value(case.entities.clone(), None)
        .map_err(|error| format!("Cedar entity parse: {error}"))?;
    let uid = |text: &str| EntityUid::from_str(text).map_err(|error| error.to_string());
    let action = uid(&case.request.action)?;
    let context = Context::from_json_value(case.request.context.clone(), None)
        .map_err(|error| format!("Cedar context parse: {error}"))?;
    let request = Request::new(
        uid(&case.request.principal)?,
        action,
        uid(&case.request.resource)?,
        context,
        None,
    )
    .map_err(|error| format!("Cedar request: {error}"))?;
    let response = Authorizer::new().is_authorized(&request, policies, &entities);
    let decision = match response.decision() {
        Decision::Allow => "allow",
        Decision::Deny => "deny",
    };
    let reasons = response
        .diagnostics()
        .reason()
        .map(ToString::to_string)
        .collect::<BTreeSet<_>>();
    let error_policies = response
        .diagnostics()
        .errors()
        .map(|error| match error {
            AuthorizationError::PolicyEvaluationError(error) => error.policy_id().to_string(),
        })
        .collect::<BTreeSet<_>>();
    let expected_reasons = case
        .expected_reasons
        .iter()
        .cloned()
        .collect::<BTreeSet<_>>();
    let expected_error_policies = case
        .expected_error_policies
        .iter()
        .cloned()
        .collect::<BTreeSet<_>>();
    if decision != case.expected
        || reasons != expected_reasons
        || error_policies != expected_error_policies
        || expected_reasons.len() != case.expected_reasons.len()
        || expected_error_policies.len() != case.expected_error_policies.len()
    {
        return Err(format!(
            "expected {} reasons {:?} errors {:?}, got {} reasons {:?} errors {:?}",
            case.expected,
            expected_reasons,
            expected_error_policies,
            decision,
            reasons,
            error_policies
        ));
    }
    let reparsed = Authorizer::new().is_authorized(&request, rendered, &entities);
    if reparsed.decision() != response.decision()
        || reparsed.diagnostics().errors().count() != error_policies.len()
    {
        return Err("rendered Cedar text changed authorization behavior".into());
    }
    Ok(())
}

#[cfg(test)]
#[path = "../tests/unit/bridge.rs"]
mod tests;

//! Parse official Cedar JSON and compare Rust authorization to Lean receipts.

use crate::CompiledPolicyJson;
use cedar_policy::{Authorizer, Context, Decision, Entities, EntityUid, PolicySet, Request};
use serde::Deserialize;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
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
    pub expected_errors: usize,
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
    for case in &manifest.cases {
        if !names.insert(&case.name) {
            return Err(format!("duplicate case name: {}", case.name));
        }
        check_case(case).map_err(|error| format!("{}: {error}", case.name))?;
    }
    render_artifacts(manifest)?;
    Ok(())
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

fn render_policy_set(policies: &PolicySet) -> Result<String, String> {
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
    render_policy_set(&load_policy_set(json)?)
}

/// Render each revision to Cedar's human-readable policy language.
/// The original IDs remain in the JSON export; Cedar text cannot encode them.
pub fn render_artifacts(manifest: &Manifest) -> Result<BTreeMap<String, String>, String> {
    let mut artifacts = BTreeMap::new();
    for case in &manifest.cases {
        if case.revision.is_empty()
            || !case
                .revision
                .chars()
                .all(|character| character.is_ascii_alphanumeric() || character == '-')
        {
            return Err(format!("{}: invalid revision name", case.name));
        }
        let policies = load_policy_set(&case.policies)?;
        let artifact =
            render_policy_set(&policies).map_err(|error| format!("{}: {error}", case.name))?;
        match artifacts.insert(case.revision.clone(), artifact.clone()) {
            Some(previous) if previous != artifact => {
                return Err(format!("{}: conflicting revision output", case.revision));
            }
            _ => {}
        }
    }
    Ok(artifacts)
}

fn check_case(case: &Case) -> Result<(), String> {
    let policies = load_policy_set(&case.policies)?;
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
    let response = Authorizer::new().is_authorized(&request, &policies, &entities);
    let decision = match response.decision() {
        Decision::Allow => "allow",
        Decision::Deny => "deny",
    };
    let errors = response.diagnostics().errors().count();
    if decision != case.expected || errors != case.expected_errors {
        return Err(format!(
            "expected {} with {} errors, got {} with {} errors",
            case.expected, case.expected_errors, decision, errors
        ));
    }
    let text = render_policy_set(&policies)?;
    let parsed = PolicySet::from_str(&text)
        .map_err(|error| format!("rendered Cedar text parse: {error}"))?;
    let reparsed = Authorizer::new().is_authorized(&request, &parsed, &entities);
    if reparsed.decision() != response.decision()
        || reparsed.diagnostics().errors().count() != errors
    {
        return Err("rendered Cedar text changed authorization behavior".into());
    }
    Ok(())
}

#[cfg(test)]
#[path = "../tests/unit/bridge.rs"]
mod tests;

//! Parse official Cedar JSON and compare Rust authorization to Lean receipts.

use cedar_policy::{Authorizer, Context, Decision, Entities, EntityUid, PolicySet, Request};
use serde::Deserialize;
use serde_json::Value;
use std::str::FromStr;

/// Materialized Cedar policy set in the official JSON policy-set format.
#[derive(Debug, Deserialize)]
#[serde(transparent)]
pub struct CompiledPolicyJson(Value);

impl FromStr for CompiledPolicyJson {
    type Err = serde_json::Error;

    fn from_str(source: &str) -> Result<Self, Self::Err> {
        serde_json::from_str(source)
    }
}

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
    for case in &manifest.cases {
        check_case(case).map_err(|error| format!("{}: {error}", case.name))?;
    }
    Ok(())
}

/// Load a Lean-POO compiled policy set through Cedar's public JSON parser.
pub fn load_policy_set(json: &CompiledPolicyJson) -> Result<PolicySet, String> {
    PolicySet::from_json_value(json.0.clone())
        .map_err(|error| format!("Cedar policy parse: {error}"))
}

fn check_case(case: &Case) -> Result<(), String> {
    let policies = load_policy_set(&case.policies)?;
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
    Ok(())
}

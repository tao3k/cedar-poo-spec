//! Strict Cedar schema validation and schema-bound replay records.

use crate::bridge::{Case, ReplayReceipt, check_manifest_inner, json_sha256, load_policy_set};
use cedar_policy::{Schema, ValidationMode, Validator};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeSet;

/// A schema-bearing manifest intended for admission as a deployment candidate.
#[derive(Debug, Deserialize)]
pub struct ValidatedManifest {
    pub schema: Value,
    pub cases: Vec<Case>,
}

/// Two schema-checked projections of the same policies and concrete inputs.
#[derive(Debug, Deserialize)]
pub struct SchemaEvolutionBundle {
    pub before: ValidatedManifest,
    pub after: ValidatedManifest,
}

/// A Cedar replay bound to the exact schema used for strict validation.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SchemaBoundReceipt {
    pub schema_sha256: String,
    pub replay: ReplayReceipt,
}

/// Evidence that a schema edit preserved Cedar's observed results for these inputs.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SchemaOnlyRevisionReceipt {
    pub before_schema_sha256: String,
    pub after_schema_sha256: String,
    pub replay: Vec<ReplayReceipt>,
}

/// Validate policies and replay with schema-parsed entities, context, and request.
pub fn replay_validated_manifest(
    manifest: &ValidatedManifest,
) -> Result<Vec<SchemaBoundReceipt>, String> {
    let schema = Schema::from_json_value(manifest.schema.clone())
        .map_err(|error| format!("Cedar schema: {error}"))?;
    let validator = Validator::new(schema);
    let mut revisions = BTreeSet::new();
    for case in &manifest.cases {
        if revisions.insert(&case.revision) {
            let policies = load_policy_set(&case.policies)?;
            let result = validator.validate(&policies, ValidationMode::Strict);
            if !result.validation_passed() {
                return Err(format!(
                    "{}: Cedar strict policy validation failed: {result:?}",
                    case.revision
                ));
            }
        }
    }
    let schema_sha256 = json_sha256(&manifest.schema)?;
    check_manifest_inner(&manifest.cases, true, Some(validator.schema())).map(|receipts| {
        receipts
            .into_iter()
            .map(|replay| SchemaBoundReceipt {
                schema_sha256: schema_sha256.clone(),
                replay,
            })
            .collect()
    })
}

/// Recompute schema-bound receipts against the current official Cedar runtime.
pub fn verify_validated_replay_receipts(
    manifest: &ValidatedManifest,
    receipts: &[SchemaBoundReceipt],
) -> Result<(), String> {
    if replay_validated_manifest(manifest)? != receipts {
        return Err(
            "schema-bound Cedar receipts differ from the current manifest or runtime".into(),
        );
    }
    Ok(())
}

/// Replay the same policy and request artifacts under two different schemas.
/// Equality is restricted to the finite cases supplied by the caller.
pub fn replay_schema_only_revision(
    bundle: &SchemaEvolutionBundle,
) -> Result<SchemaOnlyRevisionReceipt, String> {
    let before = replay_validated_manifest(&bundle.before)?;
    let after = replay_validated_manifest(&bundle.after)?;
    let before_schema_sha256 = before
        .first()
        .ok_or("schema-only revision has no cases")?
        .schema_sha256
        .clone();
    let after_schema_sha256 = after
        .first()
        .ok_or("schema-only revision has no cases")?
        .schema_sha256
        .clone();
    if before_schema_sha256 == after_schema_sha256 {
        return Err("schema-only revision requires a changed schema".into());
    }
    let before_replay = before.into_iter().map(|row| row.replay).collect::<Vec<_>>();
    let after_replay = after.into_iter().map(|row| row.replay).collect::<Vec<_>>();
    if before_replay != after_replay {
        return Err(
            "schema-only revision changed policy/request artifacts or Cedar diagnostics".into(),
        );
    }
    Ok(SchemaOnlyRevisionReceipt {
        before_schema_sha256,
        after_schema_sha256,
        replay: before_replay,
    })
}

/// Recompute a stored schema-only revision receipt against the current runtime.
pub fn verify_schema_only_revision(
    bundle: &SchemaEvolutionBundle,
    receipt: &SchemaOnlyRevisionReceipt,
) -> Result<(), String> {
    if &replay_schema_only_revision(bundle)? != receipt {
        return Err(
            "schema-only revision receipt differs from the current inputs or runtime".into(),
        );
    }
    Ok(())
}

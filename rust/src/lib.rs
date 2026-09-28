//! Cedar policy language conformance boundary for Lean-POO exports.

mod artifact;
pub use artifact::{CompiledPolicyJson, TemplateSourceJson};

#[cfg(feature = "cedar-runtime")]
mod bridge;
#[cfg(feature = "cedar-runtime")]
pub mod cli;
#[cfg(feature = "cedar-runtime")]
mod schema;

#[cfg(feature = "cedar-runtime")]
pub use bridge::{
    Case, Manifest, ReplayReceipt, RequestInput, check_direct_sources, check_manifest,
    check_template_source, load_policy_set, load_template_source, render_artifacts,
    render_loaded_policy_set, render_policy_source, replay_manifest, verify_replay_receipts,
};
#[cfg(feature = "cedar-runtime")]
pub use schema::{
    SchemaBoundReceipt, SchemaEvolutionBundle, SchemaOnlyRevisionReceipt, ValidatedManifest,
    replay_schema_only_revision, replay_validated_manifest, verify_schema_only_revision,
    verify_validated_replay_receipts,
};

#[cfg(test)]
asp_rust::asp_rust_cargo_test_gate!(mode = deny, config = asp_rust::default_asp_rust_config());

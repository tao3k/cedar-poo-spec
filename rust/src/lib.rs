//! Cedar policy language conformance boundary for Lean-POO exports.

mod artifact;
pub use artifact::CompiledPolicyJson;

#[cfg(feature = "cedar-runtime")]
mod bridge;
#[cfg(feature = "cedar-runtime")]
pub mod cli;

#[cfg(feature = "cedar-runtime")]
pub use bridge::{
    Case, Manifest, RequestInput, check_direct_sources, check_manifest, load_policy_set,
    render_artifacts, render_policy_source,
};

#[cfg(test)]
asp_rust::asp_rust_cargo_test_gate!(mode = deny, config = asp_rust::default_asp_rust_config());

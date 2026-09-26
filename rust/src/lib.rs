//! Cedar policy language conformance boundary for Lean-POO exports.

mod bridge;
pub mod cli;

pub use bridge::{
    Case, CompiledPolicyJson, Manifest, RequestInput, check_manifest, load_policy_set,
    render_artifacts, render_policy_source,
};

#[cfg(test)]
asp_rust::asp_rust_cargo_test_gate!(mode = deny, config = asp_rust::default_asp_rust_config());

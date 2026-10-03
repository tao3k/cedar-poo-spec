//! MRR conditional-commit adapter for admitted commerce claims.
pub mod budget_commit;
#[cfg(feature = "consumption")]
pub mod consumption;
#[cfg(feature = "credential")]
pub mod credential;
#[cfg(feature = "consumption")]
pub mod provider;

#[cfg(test)]
asp_rust::asp_rust_cargo_test_gate!(mode = deny, config = asp_rust::default_asp_rust_config());

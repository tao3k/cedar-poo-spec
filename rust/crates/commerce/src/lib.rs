//! Typed mandate, offer, admission and shared-budget contracts for agentic AI commerce.

#[cfg(feature = "admission")]
pub mod admission;
#[cfg(feature = "budget-commit")]
pub mod budget_commit;
#[cfg(feature = "consumption")]
pub mod consumption;
#[cfg(feature = "credential")]
pub mod credential;
#[cfg(feature = "projection")]
pub mod projection;
#[cfg(feature = "consumption")]
pub mod provider;
pub mod signatures;

#[cfg(test)]
asp_rust::asp_rust_cargo_test_gate!(mode = deny, config = asp_rust::default_asp_rust_config());

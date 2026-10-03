//! Shared tool-action and sink boundary contracts.
pub mod boundary;

#[cfg(test)]
asp_rust::asp_rust_cargo_test_gate!(mode = deny, config = asp_rust::default_asp_rust_config());

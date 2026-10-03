//! Storage-independent commerce signatures, projected claims and admission.
#[cfg(feature = "acceptance")]
pub mod acceptance;
#[cfg(feature = "admission")]
pub mod admission;
#[cfg(feature = "projection")]
pub mod projection;
pub mod signatures;

#[cfg(test)]
asp_rust::asp_rust_cargo_test_gate!(mode = deny, config = asp_rust::default_asp_rust_config());

//! Common token profiles and optional Google SDP wire contracts.
#[cfg(feature = "google-sdp")]
pub mod google_sdp;
pub mod pseudonymization;

#[cfg(test)]
asp_rust::asp_rust_cargo_test_gate!(mode = deny, config = asp_rust::default_asp_rust_config());

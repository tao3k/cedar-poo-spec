//! In-memory admission and release boundary for a Google SDP table effect.
//! The caller owns authenticated transport, approval facts, and durable storage.

mod host;
pub use host::{
    InMemoryGoogleSdpHost, PreparedTableEffect, TableEffect, TableEffectAudit, TableEffectInput,
};

#[cfg(test)]
asp_rust::asp_rust_cargo_test_gate!(mode = deny, config = asp_rust::default_asp_rust_config());

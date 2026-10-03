//! Bounded pinned Checkout mandate binding verification, independent of storage.
//! Verification supplies no freshness ledger, dispatch permit or settlement claim.
#[cfg(feature = "ap2-checkout")]
pub mod checkout;
#[cfg(feature = "ap2-checkout")]
mod contract;
#[cfg(feature = "ap2-checkout")]
mod disclosures;
#[cfg(feature = "ap2-checkout")]
mod wire;
#[cfg(test)]
asp_rust::asp_rust_cargo_test_gate!(mode = deny, config = asp_rust::default_asp_rust_config());

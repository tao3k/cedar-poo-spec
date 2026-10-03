//! Shared Checkout state, atomic persistence contract and structural restoration.
mod snapshot;
mod state;

pub use state::{
    CheckoutCoordinationIdentity, CoordinationCommit, CoordinationError, SharedCheckoutState,
    SharedCheckoutStore, commit_presentation, commit_receipt,
};

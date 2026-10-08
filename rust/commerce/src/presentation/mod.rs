//! Selected Checkout receipt verification and presentation lifecycle boundary.
mod receipt;

pub use receipt::{
    AP2_SOURCE_REVISION, CLOSED_CHECKOUT_VCT, CheckoutPresentation, CheckoutReceiptClaims,
    CheckoutReceiptTrust, CheckoutStatus, OPEN_CHECKOUT_VCT, PresentationError, PresentationLedger,
    ReceiptKeyId, VerifiedCheckoutReceipt,
};

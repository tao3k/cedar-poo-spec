//! Shared verification refusal contract, independent of parser and domain ownership.
/// Explicit failures; unsupported valid inputs never become verified evidence.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum MandateError {
    Malformed,
    Limit,
    Unsupported,
    Signature,
    Disclosure,
    Binding,
    Context,
    Time,
    Claims,
}

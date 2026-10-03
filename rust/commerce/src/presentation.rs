//! Pinned AP2 Checkout Receipt ES256 subprofile and single-open-mandate lifecycle.
//! Full SD-JWT mandate verification, constraint evaluation and persistence are Host
//! obligations. A success receipt does not establish settlement or fulfillment.
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use p256::ecdsa::{Signature, VerifyingKey, signature::Verifier};
use serde::{Deserialize, Deserializer, Serialize};
use std::collections::BTreeMap;

pub const AP2_SOURCE_REVISION: &str = "e1ea56db72a6385bce3e5c1112b3a56ce60acb43";
pub const OPEN_CHECKOUT_VCT: &str = "mandate.checkout.open.1";
pub const CLOSED_CHECKOUT_VCT: &str = "mandate.checkout.1";

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum PresentationError {
    InvalidClaims,
    InvalidSignature,
    UntrustedIssuer,
    ReceiptMismatch,
    InvalidTransition,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum CheckoutStatus {
    Success,
    Error,
}
fn present_string<'de, D: Deserializer<'de>>(d: D) -> Result<Option<String>, D::Error> {
    String::deserialize(d).map(Some)
}

/// Strict selected schema: omitted optional strings are allowed; JSON null is not.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct CheckoutReceiptClaims {
    pub status: CheckoutStatus,
    pub iss: String,
    pub iat: u64,
    pub reference: String,
    #[serde(
        default,
        deserialize_with = "present_string",
        skip_serializing_if = "Option::is_none"
    )]
    pub error: Option<String>,
    #[serde(
        default,
        deserialize_with = "present_string",
        skip_serializing_if = "Option::is_none"
    )]
    pub error_description: Option<String>,
    #[serde(
        default,
        deserialize_with = "present_string",
        skip_serializing_if = "Option::is_none"
    )]
    pub order_id: Option<String>,
}
impl CheckoutReceiptClaims {
    fn valid(&self) -> bool {
        let nonempty = |s: &Option<String>| s.as_ref().is_some_and(|s| !s.is_empty());
        !self.iss.is_empty()
            && !self.reference.is_empty()
            && match self.status {
                CheckoutStatus::Success => {
                    nonempty(&self.order_id)
                        && self.error.is_none()
                        && self.error_description.is_none()
                }
                CheckoutStatus::Error => {
                    nonempty(&self.error)
                        && nonempty(&self.error_description)
                        && self.order_id.is_none()
                }
            }
    }
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Header {
    alg: String,
    #[serde(default, deserialize_with = "present_string")]
    typ: Option<String>,
    #[serde(default, deserialize_with = "present_string")]
    kid: Option<String>,
}

/// Keys are enrolled by issuer AND role outside presented JWTs. This registry
/// contains merchant Checkout Receipt keys only; payment keys cannot unlock it.
#[derive(Default)]
pub struct CheckoutReceiptTrust {
    keys: BTreeMap<String, (String, VerifyingKey, Vec<String>)>,
}
impl CheckoutReceiptTrust {
    pub fn enroll(&mut self, issuer: String, key_id: String, key: VerifyingKey) {
        self.keys.insert(issuer, (key_id, key, Vec::new()));
    }
    /// Configure a terminal non-acceptance code agreed with this merchant.
    /// Timeout/unknown errors must never be classified as rejection.
    /// # Errors
    /// Refuses an unenrolled issuer or empty code.
    pub fn allow_rejection(&mut self, issuer: &str, code: String) -> Result<(), PresentationError> {
        if code.is_empty() {
            return Err(PresentationError::InvalidClaims);
        }
        let (_, _, codes) = self
            .keys
            .get_mut(issuer)
            .ok_or(PresentationError::UntrustedIssuer)?;
        codes.push(code);
        Ok(())
    }
    pub fn revoke(&mut self, issuer: &str) {
        self.keys.remove(issuer);
    }
    /// Verify exact compact JWS using independently configured merchant trust.
    /// # Errors
    /// Rejects algorithms/headers outside this profile, malformed schema, bad
    /// signature, wrong issuer/reference and receipts outside the presentation time.
    pub fn verify(
        &self,
        jwt: &str,
        presentation: &CheckoutPresentation,
        now: u64,
    ) -> Result<VerifiedCheckoutReceipt, PresentationError> {
        if jwt.len() > 16384 {
            return Err(PresentationError::InvalidClaims);
        }
        let parts: Vec<_> = jwt.split('.').collect();
        if parts.len() != 3 {
            return Err(PresentationError::InvalidClaims);
        }
        let decode = |part: &str| {
            URL_SAFE_NO_PAD
                .decode(part)
                .map_err(|_| PresentationError::InvalidClaims)
        };
        let header: Header = serde_json::from_slice(&decode(parts[0])?)
            .map_err(|_| PresentationError::InvalidClaims)?;
        if header.alg != "ES256" || header.typ.as_deref().is_some_and(|t| t != "JWT") {
            return Err(PresentationError::InvalidClaims);
        }
        let (key_id, key, rejection_codes) = self
            .keys
            .get(&presentation.merchant_issuer)
            .ok_or(PresentationError::UntrustedIssuer)?;
        if header.kid.as_ref().is_some_and(|kid| kid != key_id) {
            return Err(PresentationError::UntrustedIssuer);
        }
        let signature = Signature::from_slice(&decode(parts[2])?)
            .map_err(|_| PresentationError::InvalidSignature)?;
        key.verify(format!("{}.{}", parts[0], parts[1]).as_bytes(), &signature)
            .map_err(|_| PresentationError::InvalidSignature)?;
        let claims: CheckoutReceiptClaims = serde_json::from_slice(&decode(parts[1])?)
            .map_err(|_| PresentationError::InvalidClaims)?;
        if !claims.valid() {
            return Err(PresentationError::InvalidClaims);
        }
        if claims.iss != presentation.merchant_issuer
            || claims.reference != presentation.reference
            || claims.iat < presentation.presented_at
            || claims.iat > now
        {
            return Err(PresentationError::ReceiptMismatch);
        }
        if claims.status == CheckoutStatus::Error
            && !claims
                .error
                .as_ref()
                .is_some_and(|code| rejection_codes.contains(code))
        {
            return Err(PresentationError::InvalidClaims);
        }
        Ok(VerifiedCheckoutReceipt { claims })
    }
}
#[derive(Debug)]
pub struct VerifiedCheckoutReceipt {
    claims: CheckoutReceiptClaims,
}
impl VerifiedCheckoutReceipt {
    pub fn claims(&self) -> &CheckoutReceiptClaims {
        &self.claims
    }
}

/// Exact closed-mandate reference is supplied by an independently verified Host.
/// This subprofile does not guess a mandate canonicalization/hash algorithm.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct CheckoutPresentation {
    pub reference: String,
    pub merchant_issuer: String,
    pub presented_at: u64,
}
/// Persist one ledger per authenticated open-mandate/agent scope BEFORE sending.
/// Seen references are retained to prevent old rejection receipts clearing a retry.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct PresentationLedger {
    pub open_mandate_scope: String,
    pub revision: u64,
    pub pending: Option<CheckoutPresentation>,
    pub spent: bool,
    pub seen: Vec<String>,
}
impl PresentationLedger {
    /// Pure proposal; current mandate verification and atomic persistence required.
    #[must_use]
    pub fn present(
        &self,
        open_vct: &str,
        closed_vct: &str,
        presentation: CheckoutPresentation,
    ) -> Option<Self> {
        if open_vct != OPEN_CHECKOUT_VCT
            || closed_vct != CLOSED_CHECKOUT_VCT
            || self.spent
            || self.pending.is_some()
            || self.open_mandate_scope.is_empty()
            || presentation.reference.is_empty()
            || presentation.merchant_issuer.is_empty()
            || self.seen.contains(&presentation.reference)
        {
            return None;
        }
        let mut next = self.clone();
        next.revision = self.revision.checked_add(1)?;
        next.seen.push(presentation.reference.clone());
        next.pending = Some(presentation);
        Some(next)
    }
    /// Only a cryptographically verified exact receipt can close the pending slot.
    #[must_use]
    pub fn complete(&self, receipt: &VerifiedCheckoutReceipt) -> Option<Self> {
        if self.spent {
            return None;
        }
        let pending = self.pending.as_ref()?;
        let claims = receipt.claims();
        if claims.reference != pending.reference
            || claims.iss != pending.merchant_issuer
            || claims.iat < pending.presented_at
        {
            return None;
        }
        Some(Self {
            revision: self.revision.checked_add(1)?,
            pending: None,
            spent: claims.status == CheckoutStatus::Success,
            ..self.clone()
        })
    }
}

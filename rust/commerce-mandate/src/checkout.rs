//! Selected two-hop ES256/SHA-256 binding verifier for the fixed SDK corpus.
//! Selected merchant/item constraints; no full UCP business-schema or stateful admission claim.
use crate::{
    constraints::{self, ConstraintSet},
    disclosures::Token,
    wire,
};
use p256::ecdsa::VerifyingKey;
use serde_json::Value;

/// Immutable source revision defining the selected SDK wire forms.
pub const AP2_SOURCE_REVISION: &str = "e1ea56db72a6385bce3e5c1112b3a56ce60acb43";
pub use crate::contract::{CheckoutConstraintCoverage, MandateError};
/// Host-authenticated transaction context; keys are enrolled outside the tokens.
/// This context supports the pinned root typ `example+sd-jwt`, terminal typ
/// `kb+sd-jwt` and merchant typ `JWT`. All use ES256; kid/x5c are unsupported.
pub struct CheckoutContext {
    pub root_key: VerifyingKey,
    pub merchant_key: VerifyingKey,
    pub transaction: TransactionContext,
    pub now: u64,
}
/// Independently authenticated audience, server nonce and merchant identity.
/// Strings preserve exact wire spelling. A caller must not copy these from tokens.
pub struct TransactionContext {
    pub audience: Audience,
    pub nonce: ServerNonce,
    pub merchant: MerchantId,
}
/// Exact enrolled transaction audience.
pub struct Audience(pub String);
/// Exact server-issued transaction nonce; runtime replay state remains external.
pub struct ServerNonce(pub String);
/// Exact independently authenticated merchant identifier.
pub struct MerchantId(pub String);
/// Privately constructed binding evidence; no deserialize, permit or receipt reference.
/// Digests name exact issuer JWS bytes, independently of disclosure selection.
pub struct VerifiedCheckoutBinding {
    constraint_coverage: CheckoutConstraintCoverage,
    root_jws_digest: String,
    root_key_digest: String,
    root_signed_content_digest: String,
    closed_jws_digest: String,
    agent_key_digest: String,
    checkout_hash: String,
    checkout: AuthenticatedCheckout,
}
impl VerifiedCheckoutBinding {
    /// Explicit coverage of the selected policy; seed evidence does not satisfy
    /// the full pinned open-mandate schema's required line-items constraint.
    pub fn constraint_coverage(&self) -> CheckoutConstraintCoverage {
        self.constraint_coverage
    }
    /// Exact signed root evidence digest; not a complete authorization identity.
    pub fn root_jws_digest(&self) -> &str {
        &self.root_jws_digest
    }
    /// Enrolled root key fingerprint, independent of token-provided identifiers.
    pub fn root_key_digest(&self) -> &str {
        &self.root_key_digest
    }
    /// Signed header/payload digest excluding signature and disclosures. Host
    /// authorization grouping must also bind root enrollment and policy identity.
    pub fn root_signed_content_digest(&self) -> &str {
        &self.root_signed_content_digest
    }
    /// Exact closed issuer JWS evidence digest; not an AP2 receipt-reference derivation.
    pub fn closed_jws_digest(&self) -> &str {
        &self.closed_jws_digest
    }
    /// Digest of the verified agent's uncompressed P-256 public point.
    pub fn agent_key_digest(&self) -> &str {
        &self.agent_key_digest
    }
    /// SHA-256 digest of exact independently verified merchant Checkout JWT bytes.
    pub fn checkout_hash(&self) -> &str {
        &self.checkout_hash
    }
    /// Authenticated merchant JSON; downstream UCP business validation is required.
    pub fn merchant_checkout(&self) -> &AuthenticatedCheckout {
        &self.checkout
    }
}
impl CheckoutContext {
    /// Verify the selected two-hop wire form and its exact transaction/checkout binding.
    /// # Errors
    /// Rejects untrusted signatures, unsupported types/constraints, ambiguous or
    /// unmatched disclosures, context substitution, expiry and checkout substitution.
    pub fn verify(&self, tokens: &[&str]) -> Result<VerifiedCheckoutBinding, MandateError> {
        self.validate_context()?;
        if tokens.len() != 2 {
            return Err(MandateError::Unsupported);
        }
        let chain = self.verify_chain(tokens)?;
        let checkout = self.verify_checkout(&chain.closed)?;
        chain.constraints.evaluate(&checkout.claims)?;
        Ok(VerifiedCheckoutBinding {
            constraint_coverage: chain.constraints.coverage(),
            root_jws_digest: chain.root_digest,
            root_key_digest: wire::hash(self.root_key.to_encoded_point(false).as_bytes()),
            root_signed_content_digest: chain.root_content_digest,
            closed_jws_digest: chain.closed_digest,
            agent_key_digest: chain.agent_digest,
            checkout_hash: wire::hash(checkout.compact_jwt.as_bytes()),
            checkout,
        })
    }
    fn verify_chain(&self, tokens: &[&str]) -> Result<BoundChain, MandateError> {
        let root = Token::parse(tokens[0])?;
        let leaf = Token::parse(tokens[1])?;
        let open = root.resolve(wire::jws(root.issuer, &self.root_key, "example+sd-jwt")?)?;
        let authority = self.verify_open(&open)?;
        let agent = authority.agent;
        let open_time = authority.validity;
        let terminal = leaf.resolve(wire::jws(leaf.issuer, &agent, "kb+sd-jwt")?)?;
        let closed = self.verify_terminal(&terminal, &root, open_time)?.clone();
        Ok(BoundChain {
            root_digest: wire::hash(root.issuer.as_bytes()),
            root_content_digest: wire::hash(
                root.issuer
                    .rsplit_once('.')
                    .ok_or(MandateError::Malformed)?
                    .0
                    .as_bytes(),
            ),
            closed_digest: wire::hash(leaf.issuer.as_bytes()),
            agent_digest: wire::hash(agent.to_encoded_point(false).as_bytes()),
            closed,
            constraints: authority.constraints,
        })
    }
    fn verify_checkout(&self, closed: &Value) -> Result<AuthenticatedCheckout, MandateError> {
        let checkout_jwt = wire::text(closed, "checkout_jwt")?;
        if wire::text(closed, "checkout_hash")? != wire::hash(checkout_jwt.as_bytes()) {
            return Err(MandateError::Binding);
        }
        let claims = wire::jws(checkout_jwt, &self.merchant_key, "JWT")?;
        self.verify_merchant(&claims)?;
        Ok(AuthenticatedCheckout {
            claims,
            compact_jwt: checkout_jwt.to_owned(),
        })
    }
    fn validate_context(&self) -> Result<(), MandateError> {
        if self.transaction.audience.0.is_empty()
            || self.transaction.nonce.0.is_empty()
            || self.transaction.merchant.0.is_empty()
        {
            return Err(MandateError::Context);
        }
        Ok(())
    }
    fn verify_open(&self, payload: &Value) -> Result<OpenAuthority, MandateError> {
        wire::fields(payload, &["delegate_payload"])?;
        let open = delegate(payload)?;
        wire::fields(open, &["vct", "constraints", "cnf", "iat", "exp"])?;
        if wire::text(open, "vct")? != "mandate.checkout.open.1" {
            return Err(MandateError::Unsupported);
        }
        let constraints = constraints::parse(open.get("constraints").ok_or(MandateError::Claims)?)?;
        let cnf = open.get("cnf").ok_or(MandateError::Claims)?;
        wire::fields(cnf, &["jwk"])?;
        let agent = wire::jwk(cnf.get("jwk").ok_or(MandateError::Claims)?)?;
        Ok(OpenAuthority {
            agent,
            validity: wire::time(open, self.now)?,
            constraints,
        })
    }
    fn verify_terminal<'a>(
        &self,
        payload: &'a Value,
        root: &Token<'_>,
        open_time: (u64, u64),
    ) -> Result<&'a Value, MandateError> {
        wire::fields(
            payload,
            &[
                "delegate_payload",
                "iat",
                "aud",
                "nonce",
                "sd_hash",
                "issuer_jwt_hash",
            ],
        )?;
        if wire::text(payload, "aud")? != self.transaction.audience.0
            || wire::text(payload, "nonce")? != self.transaction.nonce.0
        {
            return Err(MandateError::Context);
        }
        let iat = payload
            .get("iat")
            .and_then(Value::as_u64)
            .ok_or(MandateError::Claims)?;
        if iat > self.now || iat < open_time.0 {
            return Err(MandateError::Time);
        }
        verify_parent(payload, root)?;
        let closed = delegate(payload)?;
        wire::fields(
            closed,
            &["vct", "checkout_jwt", "checkout_hash", "iat", "exp"],
        )?;
        if wire::text(closed, "vct")? != "mandate.checkout.1" {
            return Err(MandateError::Unsupported);
        }
        let (closed_iat, closed_exp) = wire::time(closed, self.now)?;
        if closed_iat < open_time.0 || closed_exp > open_time.1 {
            return Err(MandateError::Time);
        }
        Ok(closed)
    }
    fn verify_merchant(&self, checkout: &Value) -> Result<(), MandateError> {
        wire::object(checkout)?;
        wire::text(checkout, "id")?;
        let merchant = checkout.get("merchant").ok_or(MandateError::Claims)?;
        if wire::text(merchant, "id")? != self.transaction.merchant.0 {
            return Err(MandateError::Context);
        }
        Ok(())
    }
}
fn delegate(payload: &Value) -> Result<&Value, MandateError> {
    let items = payload
        .get("delegate_payload")
        .and_then(Value::as_array)
        .ok_or(MandateError::Claims)?;
    if items.len() != 1 {
        return Err(MandateError::Unsupported);
    }
    wire::object(&items[0])?;
    Ok(&items[0])
}
fn verify_parent(payload: &Value, root: &Token<'_>) -> Result<(), MandateError> {
    let expected = match (payload.get("sd_hash"), payload.get("issuer_jwt_hash")) {
        (Some(actual), None) => (actual, wire::hash(root.wire.as_bytes())),
        (None, Some(actual)) => (actual, wire::hash(root.issuer.as_bytes())),
        _ => return Err(MandateError::Binding),
    };
    if expected.0.as_str() != Some(&expected.1) {
        return Err(MandateError::Binding);
    }
    Ok(())
}

struct OpenAuthority {
    agent: VerifyingKey,
    validity: (u64, u64),
    constraints: ConstraintSet,
}
struct BoundChain {
    root_digest: String,
    root_content_digest: String,
    closed_digest: String,
    agent_digest: String,
    closed: Value,
    constraints: ConstraintSet,
}
/// Exact signed merchant evidence with a verified identifier; downstream UCP
/// business-schema validation remains required before any commerce admission.
pub struct AuthenticatedCheckout {
    claims: Value,
    compact_jwt: String,
}
impl AuthenticatedCheckout {
    /// Nonempty checkout identifier from the authenticated payload.
    pub fn checkout_id(&self) -> &str {
        self.claims["id"].as_str().expect("verified identifier")
    }
    /// Exact authenticated compact JWS for downstream business validation/evidence.
    pub fn compact_jwt(&self) -> &str {
        &self.compact_jwt
    }
}

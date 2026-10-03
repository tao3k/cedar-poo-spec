//! Host-side signature checks for local mandate, delegation, and offer evidence.
//!
//! The caller configures trusted principal and merchant public keys. A
//! successful result authenticates the exact versioned payload and checkout
//! bytes; it does not publish policy, reserve budget, or execute a payment.
//! This encoding is local to this repository and is not an AP2 JWT format.

use p256::ecdsa::{Signature, VerifyingKey, signature::Verifier};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;

const MANDATE_DOMAIN: &[u8] = b"cedar-poo-agent-mandate-v1\0";
const DELEGATION_DOMAIN: &[u8] = b"cedar-poo-agent-delegation-v1\0";
const OFFER_DOMAIN: &[u8] = b"cedar-poo-merchant-offer-v1\0";

macro_rules! semantic_id {
    ($name:ident) => {
        #[derive(Clone, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
        #[serde(transparent)]
        pub struct $name(String);

        impl $name {
            pub fn as_str(&self) -> &str {
                &self.0
            }

            pub fn is_empty(&self) -> bool {
                self.0.is_empty()
            }
        }

        impl AsRef<str> for $name {
            fn as_ref(&self) -> &str {
                self.as_str()
            }
        }

        impl From<&str> for $name {
            fn from(value: &str) -> Self {
                Self(value.to_owned())
            }
        }

        impl From<String> for $name {
            fn from(value: String) -> Self {
                Self(value)
            }
        }
    };
}

semantic_id!(MandateId);
semantic_id!(AgentId);
semantic_id!(AgentPublicKey);
semantic_id!(MerchantId);
semantic_id!(ProductId);
semantic_id!(OfferId);

fn append_u64(bytes: &mut Vec<u8>, number: u64) {
    bytes.extend_from_slice(&number.to_be_bytes());
}

fn append_string(bytes: &mut Vec<u8>, value: &str) {
    append_u64(bytes, value.len() as u64);
    bytes.extend_from_slice(value.as_bytes());
}

fn append_strings<T: AsRef<str>>(bytes: &mut Vec<u8>, values: &[T]) {
    append_u64(bytes, values.len() as u64);
    for value in values {
        append_string(bytes, value.as_ref());
    }
}

fn hex_lower(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut result = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        result.push(HEX[(byte >> 4) as usize] as char);
        result.push(HEX[(byte & 0x0f) as usize] as char);
    }
    result
}

/// Lowercase SHA-256 commitment over the complete merchant checkout bytes.
pub fn sha256_hex(bytes: &[u8]) -> String {
    hex_lower(&Sha256::digest(bytes))
}

fn decode_lower_hex(value: &str) -> Option<Vec<u8>> {
    fn nibble(value: u8) -> Option<u8> {
        match value {
            b'0'..=b'9' => Some(value - b'0'),
            b'a'..=b'f' => Some(value - b'a' + 10),
            _ => None,
        }
    }
    let (pairs, remainder) = value.as_bytes().as_chunks::<2>();
    if !remainder.is_empty() {
        return None;
    }
    let mut bytes = Vec::with_capacity(pairs.len());
    for pair in pairs {
        bytes.push((nibble(pair[0])? << 4) | nibble(pair[1])?);
    }
    Some(bytes)
}

fn agent_key(hex: &str) -> Option<VerifyingKey> {
    let bytes = decode_lower_hex(hex)?;
    if bytes.len() != 33 || !matches!(bytes[0], 0x02 | 0x03) {
        return None;
    }
    VerifyingKey::from_sec1_bytes(&bytes).ok()
}

/// Exact components of Lean `EntityUID { ty := { id, path }, eid }`.
#[derive(Clone, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct PrincipalId {
    pub entity_type_id: String,
    pub entity_type_path: Vec<String>,
    pub entity_id: String,
}

impl PrincipalId {
    fn valid_shape(&self) -> bool {
        !self.entity_type_id.is_empty()
            && self.entity_type_path.iter().all(|part| !part.is_empty())
            && !self.entity_id.is_empty()
    }

    fn append_to(&self, bytes: &mut Vec<u8>) {
        append_string(bytes, &self.entity_type_id);
        append_strings(bytes, &self.entity_type_path);
        append_string(bytes, &self.entity_id);
    }
}

/// Fields must map exactly to the Lean mandate before its `verified` flag is set.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct MandatePayload {
    pub mandate_id: MandateId,
    pub principal: PrincipalId,
    pub agent_id: AgentId,
    /// Lowercase hex of a compressed P-256 SEC1 public key.
    pub agent_public_key: AgentPublicKey,
    pub allowed_merchants: Vec<MerchantId>,
    pub allowed_products: Vec<ProductId>,
    pub asset: String,
    pub per_purchase_cap: u64,
    pub total_cap: u64,
    pub policy_epoch: u64,
    pub expires_at: u64,
}

impl MandatePayload {
    fn valid_shape(&self) -> bool {
        !self.mandate_id.is_empty()
            && self.principal.valid_shape()
            && !self.agent_id.is_empty()
            && agent_key(self.agent_public_key.as_str()).is_some()
            && !self.allowed_merchants.is_empty()
            && !self.allowed_products.is_empty()
            && self.allowed_merchants.iter().all(|value| !value.is_empty())
            && self.allowed_products.iter().all(|value| !value.is_empty())
            && !self.asset.is_empty()
            && self.per_purchase_cap > 0
            && self.total_cap >= self.per_purchase_cap
            && self.expires_at > 0
    }

    /// Versioned bytes that the principal signs for this exact mandate.
    pub fn signing_bytes(&self) -> Vec<u8> {
        let mut bytes = MANDATE_DOMAIN.to_vec();
        append_string(&mut bytes, self.mandate_id.as_str());
        self.principal.append_to(&mut bytes);
        append_string(&mut bytes, self.agent_id.as_str());
        append_string(&mut bytes, self.agent_public_key.as_str());
        append_strings(&mut bytes, &self.allowed_merchants);
        append_strings(&mut bytes, &self.allowed_products);
        append_string(&mut bytes, &self.asset);
        append_u64(&mut bytes, self.per_purchase_cap);
        append_u64(&mut bytes, self.total_cap);
        append_u64(&mut bytes, self.policy_epoch);
        append_u64(&mut bytes, self.expires_at);
        bytes
    }
}

/// Versioned bytes that the parent Agent signs to delegate this exact child.
pub fn delegation_signing_bytes(parent: &MandatePayload, child: &MandatePayload) -> Vec<u8> {
    let mut bytes = DELEGATION_DOMAIN.to_vec();
    bytes.extend_from_slice(&Sha256::digest(parent.signing_bytes()));
    bytes.extend_from_slice(&child.signing_bytes());
    bytes
}

fn child_attenuates(parent: &MandatePayload, child: &MandatePayload) -> bool {
    child.mandate_id != parent.mandate_id
        && child.agent_id != parent.agent_id
        && child.agent_public_key != parent.agent_public_key
        && child.principal == parent.principal
        && child.asset == parent.asset
        && child.policy_epoch == parent.policy_epoch
        && child
            .allowed_merchants
            .iter()
            .all(|merchant| parent.allowed_merchants.contains(merchant))
        && child
            .allowed_products
            .iter()
            .all(|product| parent.allowed_products.contains(product))
        && child.per_purchase_cap <= parent.per_purchase_cap
        && child.total_cap <= parent.total_cap
        && child.expires_at <= parent.expires_at
}

/// The signed offer commits to a separately supplied, complete checkout byte string.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct OfferPayload {
    pub merchant_id: MerchantId,
    pub product_id: ProductId,
    pub offer_id: OfferId,
    pub checkout_sha256: String,
    pub amount_minor: u64,
    pub asset: String,
    pub expires_at: u64,
}

impl OfferPayload {
    fn valid_shape(&self) -> bool {
        !self.merchant_id.is_empty()
            && !self.product_id.is_empty()
            && !self.offer_id.is_empty()
            && self.amount_minor > 0
            && !self.asset.is_empty()
            && self.expires_at > 0
    }

    /// Versioned bytes that the merchant signs for this exact offer.
    pub fn signing_bytes(&self) -> Vec<u8> {
        let mut bytes = OFFER_DOMAIN.to_vec();
        append_string(&mut bytes, self.merchant_id.as_str());
        append_string(&mut bytes, self.product_id.as_str());
        append_string(&mut bytes, self.offer_id.as_str());
        append_string(&mut bytes, &self.checkout_sha256);
        append_u64(&mut bytes, self.amount_minor);
        append_string(&mut bytes, &self.asset);
        append_u64(&mut bytes, self.expires_at);
        bytes
    }
}

#[derive(Clone, Debug)]
struct MandateIdentity {
    id: MandateId,
    agent_id: AgentId,
    agent_key: AgentPublicKey,
}

impl From<&MandatePayload> for MandateIdentity {
    fn from(payload: &MandatePayload) -> Self {
        Self {
            id: payload.mandate_id.clone(),
            agent_id: payload.agent_id.clone(),
            agent_key: payload.agent_public_key.clone(),
        }
    }
}

/// Only a successful signature verification can construct this chain value.
#[derive(Clone, Debug)]
pub struct VerifiedMandate {
    payload: MandatePayload,
    lineage: Vec<MandateIdentity>,
}

impl VerifiedMandate {
    pub fn payload(&self) -> &MandatePayload {
        &self.payload
    }
}

/// Only `MandateOfferTrust::verify_offer` can construct this value.
#[derive(Clone, Debug)]
pub struct VerifiedOffer(OfferPayload);

impl VerifiedOffer {
    pub fn payload(&self) -> &OfferPayload {
        &self.0
    }
}

/// The Host owns this trust registry and its key rotation/revocation policy.
#[derive(Default)]
pub struct MandateOfferTrust {
    principal_keys: HashMap<PrincipalId, VerifyingKey>,
    merchant_keys: HashMap<MerchantId, VerifyingKey>,
}

impl MandateOfferTrust {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn trust_principal(&mut self, principal: PrincipalId, key: VerifyingKey) {
        self.principal_keys.insert(principal, key);
    }

    pub fn trust_merchant(&mut self, merchant_id: MerchantId, key: VerifyingKey) {
        self.merchant_keys.insert(merchant_id, key);
    }

    pub fn verify_mandate(
        &self,
        payload: MandatePayload,
        signature_bytes: &[u8],
    ) -> Result<VerifiedMandate, String> {
        if !payload.valid_shape() {
            return Err("invalid mandate shape".into());
        }
        let key = self
            .principal_keys
            .get(&payload.principal)
            .ok_or("untrusted principal")?;
        let signature = Signature::from_slice(signature_bytes)
            .map_err(|_| "invalid mandate signature encoding")?;
        key.verify(&payload.signing_bytes(), &signature)
            .map_err(|_| "mandate signature mismatch")?;
        Ok(VerifiedMandate {
            lineage: vec![MandateIdentity::from(&payload)],
            payload,
        })
    }

    pub fn verify_offer(
        &self,
        payload: OfferPayload,
        checkout_bytes: &[u8],
        signature_bytes: &[u8],
    ) -> Result<VerifiedOffer, String> {
        if !payload.valid_shape() {
            return Err("invalid offer shape".into());
        }
        let actual_checkout_digest = sha256_hex(checkout_bytes);
        if payload.checkout_sha256 != actual_checkout_digest {
            return Err("checkout commitment mismatch".into());
        }
        let key = self
            .merchant_keys
            .get(&payload.merchant_id)
            .ok_or("untrusted merchant")?;
        let signature = Signature::from_slice(signature_bytes)
            .map_err(|_| "invalid offer signature encoding")?;
        key.verify(&payload.signing_bytes(), &signature)
            .map_err(|_| "offer signature mismatch")?;
        Ok(VerifiedOffer(payload))
    }

    /// Verify a child grant against the exact authenticated parent snapshot.
    /// The parent Agent signs a domain-separated hash of that snapshot and
    /// the complete child payload, whose scope must only narrow.
    pub fn verify_delegation(
        &self,
        parent: &VerifiedMandate,
        child: MandatePayload,
        signature_bytes: &[u8],
    ) -> Result<VerifiedMandate, String> {
        if !child.valid_shape() || !child_attenuates(parent.payload(), &child) {
            return Err("child mandate widens or changes parent authority".into());
        }
        if parent.lineage.iter().any(|ancestor| {
            ancestor.id == child.mandate_id
                || ancestor.agent_id == child.agent_id
                || ancestor.agent_key == child.agent_public_key
        }) {
            return Err("child reuses an ancestor mandate, agent, or key".into());
        }
        let key = agent_key(parent.payload().agent_public_key.as_str())
            .ok_or("invalid parent agent public key")?;
        let signature = Signature::from_slice(signature_bytes)
            .map_err(|_| "invalid delegation signature encoding")?;
        key.verify(
            &delegation_signing_bytes(parent.payload(), &child),
            &signature,
        )
        .map_err(|_| "delegation signature mismatch")?;
        let mut lineage = parent.lineage.clone();
        lineage.push(MandateIdentity::from(&child));
        Ok(VerifiedMandate {
            payload: child,
            lineage,
        })
    }
}

#[cfg(test)]
#[path = "../tests/unit/signatures.rs"]
mod tests;

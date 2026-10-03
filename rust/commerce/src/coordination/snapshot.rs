//! Versioned untrusted snapshot decoding and structural restoration only.
use super::{CheckoutCoordinationIdentity, CoordinationError, SharedCheckoutState};
use crate::presentation::PresentationLedger;
use serde::{
    Deserialize, Serialize,
    de::{DeserializeSeed, MapAccess, SeqAccess, Visitor},
};
use serde_json::{Map, Value};
use std::{
    collections::{BTreeMap, BTreeSet},
    fmt,
};

const VERSION: &str = "cedar-poo.checkout-state.v1";
const MAX_BYTES: usize = 524_288;

#[derive(Serialize)]
struct Envelope<'a> {
    version: &'static str,
    state: &'a SharedCheckoutState,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct UntrustedEnvelope {
    version: String,
    state: UntrustedState,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct UntrustedIdentity {
    enrollment_namespace: String,
    authorization_id: String,
    agent_id: String,
    policy_id: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct UntrustedState {
    identity: UntrustedIdentity,
    revision: u64,
    pending_journal: Option<String>,
    spent: bool,
    journals: BTreeMap<String, PresentationLedger>,
}
impl SharedCheckoutState {
    /// Encode a versioned snapshot. Bytes are not an authenticated durable receipt.
    pub fn snapshot_bytes(&self) -> Vec<u8> {
        serde_json::to_vec(&Envelope {
            version: VERSION,
            state: self,
        })
        .expect("bounded snapshot serialization")
    }
    /// Restore structural state under the expected enrolled identity. This performs
    /// no I/O and grants no send/current-authority certificate. The Host must bind
    /// exact bytes to its authenticated latest head/incarnation before use in CAS.
    /// # Errors
    /// Refuses malformed/unsupported JSON, identity mismatch, inconsistent gate,
    /// journals, counters and tombstones, or profile resource limits.
    pub fn restore_snapshot(
        bytes: &[u8],
        expected_identity: &CheckoutCoordinationIdentity,
    ) -> Result<Self, CoordinationError> {
        let raw = decode_snapshot(bytes)?;
        let identity = CheckoutCoordinationIdentity::enrolled(
            &raw.state.identity.enrollment_namespace,
            &raw.state.identity.authorization_id,
            &raw.state.identity.agent_id,
            &raw.state.identity.policy_id,
        )?;
        if &identity != expected_identity {
            return Err(CoordinationError::InvalidIdentity);
        }
        let restored = Self {
            identity,
            revision: raw.state.revision,
            pending_journal: raw.state.pending_journal,
            spent: raw.state.spent,
            journals: raw.state.journals,
        };
        restored.validate_structure()?;
        Ok(restored)
    }
    fn validate_structure(&self) -> Result<(), CoordinationError> {
        if self.journals.len() > 16 {
            return Err(CoordinationError::Limit);
        }
        let key = self.identity.storage_key();
        let mut seen = BTreeSet::new();
        let mut pending = None;
        let mut spent_count = 0;
        let mut revision = 0u64;
        for (name, journal) in &self.journals {
            if name.is_empty()
                || name.len() > 256
                || journal.open_mandate_scope != key
                || journal.seen.is_empty()
            {
                return Err(CoordinationError::InvalidSnapshot);
            }
            for reference in &journal.seen {
                if reference.is_empty() || reference.len() > 256 || !seen.insert(reference) {
                    return Err(CoordinationError::InvalidSnapshot);
                }
                if seen.len() > 256 {
                    return Err(CoordinationError::Limit);
                }
            }
            let expected = u64::try_from(journal.seen.len())
                .map_err(|_| CoordinationError::Limit)?
                .checked_mul(2)
                .and_then(|n| n.checked_sub(u64::from(journal.pending.is_some())))
                .ok_or(CoordinationError::Limit)?;
            if expected != journal.revision {
                return Err(CoordinationError::InvalidSnapshot);
            }
            revision = revision
                .checked_add(journal.revision)
                .ok_or(CoordinationError::Limit)?;
            if let Some(presentation) = &journal.pending {
                if pending.is_some()
                    || journal.seen.last() != Some(&presentation.reference)
                    || presentation.merchant_issuer.is_empty()
                    || presentation.merchant_issuer.len() > 256
                {
                    return Err(CoordinationError::InvalidSnapshot);
                }
                pending = Some(name.clone());
            }
            spent_count += usize::from(journal.spent);
        }
        if revision != self.revision
            || pending != self.pending_journal
            || spent_count > 1
            || self.spent != (spent_count == 1)
            || (self.spent && pending.is_some())
        {
            return Err(CoordinationError::InvalidSnapshot);
        }
        Ok(())
    }
}
fn decode_snapshot(bytes: &[u8]) -> Result<UntrustedEnvelope, CoordinationError> {
    if bytes.len() > MAX_BYTES {
        return Err(CoordinationError::Limit);
    }
    let mut parser = serde_json::Deserializer::from_slice(bytes);
    let value = Strict(0)
        .deserialize(&mut parser)
        .map_err(|_| CoordinationError::InvalidSnapshot)?;
    parser
        .end()
        .map_err(|_| CoordinationError::InvalidSnapshot)?;
    // Serde Option fields otherwise accept omission. The versioned wire format
    // requires explicit null for an absent shared pointer and ledger pending.
    let state = value
        .get("state")
        .ok_or(CoordinationError::InvalidSnapshot)?;
    if state.get("pending_journal").is_none() {
        return Err(CoordinationError::InvalidSnapshot);
    }
    let journals = state
        .get("journals")
        .and_then(Value::as_object)
        .ok_or(CoordinationError::InvalidSnapshot)?;
    if journals.values().any(|j| j.get("pending").is_none()) {
        return Err(CoordinationError::InvalidSnapshot);
    }
    let raw: UntrustedEnvelope =
        serde_json::from_value(value).map_err(|_| CoordinationError::InvalidSnapshot)?;
    if raw.version != VERSION {
        return Err(CoordinationError::InvalidSnapshot);
    }
    Ok(raw)
}

struct Strict(usize);
impl<'de> DeserializeSeed<'de> for Strict {
    type Value = Value;
    fn deserialize<D: serde::Deserializer<'de>>(self, d: D) -> Result<Self::Value, D::Error> {
        if self.0 > 12 {
            return Err(serde::de::Error::custom("snapshot depth"));
        }
        d.deserialize_any(self)
    }
}
impl<'de> Visitor<'de> for Strict {
    type Value = Value;
    fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("bounded duplicate-free snapshot JSON")
    }
    fn visit_bool<E>(self, x: bool) -> Result<Self::Value, E> {
        Ok(x.into())
    }
    fn visit_u64<E>(self, x: u64) -> Result<Self::Value, E> {
        Ok(x.into())
    }
    fn visit_i64<E>(self, x: i64) -> Result<Self::Value, E> {
        Ok(x.into())
    }
    fn visit_unit<E>(self) -> Result<Self::Value, E> {
        Ok(Value::Null)
    }
    fn visit_str<E: serde::de::Error>(self, x: &str) -> Result<Self::Value, E> {
        if x.len() > 256 {
            return Err(E::custom("snapshot string bound"));
        }
        Ok(x.into())
    }
    fn visit_string<E: serde::de::Error>(self, x: String) -> Result<Self::Value, E> {
        self.visit_str(&x)
    }
    fn visit_seq<A: SeqAccess<'de>>(self, mut a: A) -> Result<Self::Value, A::Error> {
        let mut values = Vec::new();
        while let Some(value) = a.next_element_seed(Strict(self.0 + 1))? {
            if values.len() == 256 {
                return Err(serde::de::Error::custom("snapshot array bound"));
            }
            values.push(value);
        }
        Ok(Value::Array(values))
    }
    fn visit_map<A: MapAccess<'de>>(self, mut a: A) -> Result<Self::Value, A::Error> {
        let mut values = Map::new();
        while let Some(key) = a.next_key::<String>()? {
            if key.len() > 256 || values.len() == 256 || values.contains_key(&key) {
                return Err(serde::de::Error::custom("snapshot duplicate/key/map bound"));
            }
            values.insert(key, a.next_value_seed(Strict(self.0 + 1))?);
        }
        Ok(Value::Object(values))
    }
}

//! Immutable complete entity source; ownership is not SDK validity or admission.
use crate::JsonSourceIdentity;
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::Value;
use std::{
    ops::Deref,
    sync::{Arc, OnceLock},
};
/// Complete immutable Cedar entity JSON source; SDK parsing and schema admission are separate.
#[derive(Debug, Clone)]
pub struct EntitySourceJson(Arc<EntitySource>);
#[derive(Debug)]
struct EntitySource {
    value: Value,
    identity: OnceLock<Result<String, String>>,
}
impl PartialEq for EntitySourceJson {
    fn eq(&self, other: &Self) -> bool {
        self.0.value == other.0.value
    }
}
impl EntitySourceJson {
    /// Complete immutable source encoding shared by transport and SDK preparation.
    /// Its presence never establishes SDK validity or admission.
    pub fn source_identity(&self) -> Result<&str, String> {
        self.0
            .identity
            .get_or_init(|| self.0.value.encode_source())
            .as_ref()
            .map(String::as_str)
            .map_err(Clone::clone)
    }
}
impl<'de> Deserialize<'de> for EntitySourceJson {
    fn deserialize<D: Deserializer<'de>>(decoder: D) -> Result<Self, D::Error> {
        Value::deserialize(decoder).map(|value| {
            Self(Arc::new(EntitySource {
                value,
                identity: OnceLock::new(),
            }))
        })
    }
}
impl Serialize for EntitySourceJson {
    fn serialize<S: Serializer>(&self, encoder: S) -> Result<S::Ok, S::Error> {
        self.0.value.serialize(encoder)
    }
}
impl Deref for EntitySourceJson {
    type Target = Value;
    fn deref(&self) -> &Self::Target {
        &self.0.value
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn shared_encoding_does_not_change_value_equality_or_public_wire() {
        let value = serde_json::json!([{"uid":{"type":"User","id":"雪"},"attrs":{},"parents":[]}]);
        let a: EntitySourceJson = serde_json::from_value(value.clone()).unwrap();
        let b: EntitySourceJson = serde_json::from_value(value.clone()).unwrap();
        let shared = a.clone();
        let wire = a.source_identity().unwrap();
        assert_eq!(a, b, "a memoized encoding is not entity value state");
        assert!(std::ptr::eq(a.deref(), shared.deref()));
        assert!(std::ptr::eq(wire, shared.source_identity().unwrap()));
        assert_eq!(serde_json::to_value(&a).unwrap(), value);
        assert_eq!(wire, serde_json::to_string(&value).unwrap());
        assert_eq!(wire, b.source_identity().unwrap());
    }
}

use crate::contract::MandateError;
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use p256::ecdsa::{Signature, VerifyingKey, signature::Verifier};
use serde::de::{DeserializeSeed, MapAccess, SeqAccess, Visitor};
use serde_json::{Map, Value};
use sha2::{Digest, Sha256};
use std::fmt;

pub(crate) fn decode(value: &str) -> Result<Vec<u8>, MandateError> {
    URL_SAFE_NO_PAD
        .decode(value)
        .map_err(|_| MandateError::Malformed)
}
pub(crate) fn hash(value: &[u8]) -> String {
    URL_SAFE_NO_PAD.encode(Sha256::digest(value))
}
pub(crate) fn json(bytes: &[u8]) -> Result<Value, MandateError> {
    let mut parser = serde_json::Deserializer::from_slice(bytes);
    let result = Strict(0)
        .deserialize(&mut parser)
        .map_err(|_| MandateError::Malformed)?;
    parser.end().map_err(|_| MandateError::Malformed)?;
    Ok(result)
}
struct Strict(usize);
impl<'de> DeserializeSeed<'de> for Strict {
    type Value = Value;
    fn deserialize<D: serde::Deserializer<'de>>(self, d: D) -> Result<Self::Value, D::Error> {
        if self.0 > 16 {
            return Err(serde::de::Error::custom("JSON depth exceeds profile"));
        }
        d.deserialize_any(self)
    }
}
impl<'de> Visitor<'de> for Strict {
    type Value = Value;
    fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("bounded JSON without duplicate members")
    }
    fn visit_bool<E>(self, x: bool) -> Result<Self::Value, E> {
        Ok(Value::Bool(x))
    }
    fn visit_i64<E>(self, x: i64) -> Result<Self::Value, E> {
        Ok(x.into())
    }
    fn visit_u64<E>(self, x: u64) -> Result<Self::Value, E> {
        Ok(x.into())
    }
    fn visit_str<E: serde::de::Error>(self, x: &str) -> Result<Self::Value, E> {
        Ok(x.into())
    }
    fn visit_string<E>(self, x: String) -> Result<Self::Value, E> {
        Ok(x.into())
    }
    fn visit_unit<E>(self) -> Result<Self::Value, E> {
        Ok(Value::Null)
    }
    fn visit_seq<A: SeqAccess<'de>>(self, mut a: A) -> Result<Self::Value, A::Error> {
        let mut result = Vec::new();
        while let Some(x) = a.next_element_seed(Strict(self.0 + 1))? {
            result.push(x);
        }
        Ok(Value::Array(result))
    }
    fn visit_map<A: MapAccess<'de>>(self, mut a: A) -> Result<Self::Value, A::Error> {
        let mut result = Map::new();
        while let Some(key) = a.next_key::<String>()? {
            if result.contains_key(&key) {
                return Err(serde::de::Error::custom("duplicate member"));
            }
            let x = a.next_value_seed(Strict(self.0 + 1))?;
            result.insert(key, x);
        }
        Ok(Value::Object(result))
    }
}
pub(crate) fn object(value: &Value) -> Result<&Map<String, Value>, MandateError> {
    value.as_object().ok_or(MandateError::Malformed)
}
pub(crate) fn text<'a>(value: &'a Value, key: &str) -> Result<&'a str, MandateError> {
    value
        .get(key)
        .and_then(Value::as_str)
        .filter(|x| !x.is_empty())
        .ok_or(MandateError::Claims)
}
pub(crate) fn fields(value: &Value, allowed: &[&str]) -> Result<(), MandateError> {
    if object(value)?
        .keys()
        .any(|k| !allowed.contains(&k.as_str()))
    {
        return Err(MandateError::Unsupported);
    }
    Ok(())
}
pub(crate) fn time(value: &Value, now: u64) -> Result<(u64, u64), MandateError> {
    let iat = value
        .get("iat")
        .and_then(Value::as_u64)
        .ok_or(MandateError::Claims)?;
    let exp = value
        .get("exp")
        .and_then(Value::as_u64)
        .ok_or(MandateError::Claims)?;
    if iat > now || now >= exp || iat >= exp {
        return Err(MandateError::Time);
    }
    Ok((iat, exp))
}
pub(crate) fn jwk(value: &Value) -> Result<VerifyingKey, MandateError> {
    fields(value, &["kty", "crv", "x", "y"])?;
    if text(value, "kty")? != "EC" || text(value, "crv")? != "P-256" {
        return Err(MandateError::Unsupported);
    }
    let x = decode(text(value, "x")?)?;
    let y = decode(text(value, "y")?)?;
    if x.len() != 32 || y.len() != 32 {
        return Err(MandateError::Claims);
    }
    let mut point = vec![4];
    point.extend(x);
    point.extend(y);
    VerifyingKey::from_sec1_bytes(&point).map_err(|_| MandateError::Claims)
}
pub(crate) fn jws(token: &str, key: &VerifyingKey, typ: &str) -> Result<Value, MandateError> {
    if token.len() > 16384 {
        return Err(MandateError::Limit);
    }
    let parts: Vec<_> = token.split('.').collect();
    if parts.len() != 3 {
        return Err(MandateError::Malformed);
    }
    let header = json(&decode(parts[0])?)?;
    fields(&header, &["alg", "typ"])?;
    if text(&header, "alg")? != "ES256" || text(&header, "typ")? != typ {
        return Err(MandateError::Unsupported);
    }
    let signature =
        Signature::from_slice(&decode(parts[2])?).map_err(|_| MandateError::Signature)?;
    key.verify(format!("{}.{}", parts[0], parts[1]).as_bytes(), &signature)
        .map_err(|_| MandateError::Signature)?;
    json(&decode(parts[1])?)
}

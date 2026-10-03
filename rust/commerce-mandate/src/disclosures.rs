use crate::contract::MandateError;
use crate::wire::{decode, hash, json};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

pub(crate) struct Token<'a> {
    pub(crate) issuer: &'a str,
    pub(crate) disclosures: Vec<&'a str>,
    pub(crate) wire: &'a str,
}
impl<'a> Token<'a> {
    pub(crate) fn parse(wire: &'a str) -> Result<Self, MandateError> {
        if wire.len() > 16384 {
            return Err(MandateError::Limit);
        }
        let parts: Vec<_> = wire.split('~').collect();
        if parts.len() < 2 || parts.last() != Some(&"") || parts[..parts.len() - 1].contains(&"") {
            return Err(MandateError::Malformed);
        }
        if parts.len() > 18 {
            return Err(MandateError::Limit);
        }
        Ok(Self {
            issuer: parts[0],
            disclosures: parts[1..parts.len() - 1].to_vec(),
            wire,
        })
    }
    pub(crate) fn resolve(&self, mut payload: Value) -> Result<Value, MandateError> {
        let algorithm = payload
            .get("_sd_alg")
            .and_then(Value::as_str)
            .unwrap_or("sha-256");
        if algorithm != "sha-256" || payload.get("_sd_alg").is_some_and(|x| !x.is_string()) {
            return Err(MandateError::Unsupported);
        }
        payload
            .as_object_mut()
            .ok_or(MandateError::Malformed)?
            .remove("_sd_alg");
        let mut resolver = Resolver {
            supplied: BTreeMap::new(),
            referenced: BTreeSet::new(),
            used: BTreeSet::new(),
        };
        for disclosure in &self.disclosures {
            let digest = hash(disclosure.as_bytes());
            let values = json(&decode(disclosure)?)?;
            let values = values.as_array().ok_or(MandateError::Disclosure)?;
            if !matches!(values.len(), 2 | 3) || values[0].as_str().is_none_or(|x| x.is_empty()) {
                return Err(MandateError::Disclosure);
            }
            if resolver.supplied.insert(digest, values.clone()).is_some() {
                return Err(MandateError::Disclosure);
            }
        }
        let result = resolver.walk(payload, 0)?;
        if resolver.used.len() != resolver.supplied.len() {
            return Err(MandateError::Disclosure);
        }
        Ok(result)
    }
}
struct Resolver {
    supplied: BTreeMap<String, Vec<Value>>,
    referenced: BTreeSet<String>,
    used: BTreeSet<String>,
}
impl Resolver {
    fn lookup(&mut self, digest: &Value) -> Result<Option<Vec<Value>>, MandateError> {
        let digest = digest.as_str().ok_or(MandateError::Disclosure)?;
        if decode(digest)?.len() != 32 || !self.referenced.insert(digest.to_owned()) {
            return Err(MandateError::Disclosure);
        }
        let values = self.supplied.get(digest).cloned();
        if values.is_some() {
            self.used.insert(digest.to_owned());
        }
        Ok(values)
    }
    fn walk(&mut self, value: Value, depth: usize) -> Result<Value, MandateError> {
        if depth > 16 {
            return Err(MandateError::Limit);
        }
        match value {
            Value::Object(mut entries) => {
                if entries.contains_key("...") || entries.contains_key("_sd_alg") {
                    return Err(MandateError::Disclosure);
                }
                if let Some(digests) = entries.remove("_sd") {
                    for digest in digests.as_array().ok_or(MandateError::Disclosure)? {
                        if let Some(values) = self.lookup(digest)? {
                            if values.len() != 3 {
                                return Err(MandateError::Disclosure);
                            }
                            let name = values[1]
                                .as_str()
                                .filter(|n| !matches!(*n, "_sd" | "..." | "_sd_alg"))
                                .ok_or(MandateError::Disclosure)?;
                            if entries.insert(name.to_owned(), values[2].clone()).is_some() {
                                return Err(MandateError::Disclosure);
                            }
                        }
                    }
                }
                // The pinned schema permits selective alternatives/merchants,
                // not omission of entire constraints or requirement slots.
                let protected_array = |name: &str| {
                    entries
                        .get(name)
                        .and_then(Value::as_array)
                        .is_some_and(|values| values.iter().any(|v| v.get("...").is_some()))
                };
                if protected_array("constraints")
                    || (entries.get("type").and_then(Value::as_str) == Some("checkout.line_items")
                        && protected_array("items"))
                {
                    return Err(MandateError::Unsupported);
                }
                for entry in entries.values_mut() {
                    *entry = self.walk(entry.take(), depth + 1)?;
                }
                Ok(Value::Object(entries))
            }
            Value::Array(entries) => {
                let mut result = Vec::new();
                for entry in entries {
                    if let Some(digest) = entry.get("...") {
                        if entry.as_object().is_none_or(|x| x.len() != 1) {
                            return Err(MandateError::Disclosure);
                        }
                        if let Some(values) = self.lookup(digest)? {
                            if values.len() != 2 {
                                return Err(MandateError::Disclosure);
                            }
                            result.push(self.walk(values[1].clone(), depth + 1)?);
                        }
                    } else {
                        result.push(self.walk(entry, depth + 1)?);
                    }
                }
                Ok(Value::Array(result))
            }
            other => Ok(other),
        }
    }
}

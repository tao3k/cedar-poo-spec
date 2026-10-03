//! Small, Cedar-independent representation of a compiled Lean policy set.

use serde::Deserialize;
use serde_json::Value;
use std::{ops::Deref, str::FromStr};

/// Materialized Cedar policy set in the public JSON policy-set format.
#[derive(Debug, Clone, Deserialize)]
#[serde(transparent)]
pub struct CompiledPolicyJson(Value);

/// Cedar source with static policies, editable templates, and links.
#[derive(Debug, Deserialize)]
#[serde(transparent)]
pub struct TemplateSourceJson(Value);

impl FromStr for CompiledPolicyJson {
    type Err = serde_json::Error;

    fn from_str(source: &str) -> Result<Self, Self::Err> {
        serde_json::from_str(source)
    }
}

impl CompiledPolicyJson {
    /// Serialize the artifact for storage or an application-owned Cedar parser.
    pub fn to_json_string(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(&self.0)
    }
}

impl FromStr for TemplateSourceJson {
    type Err = serde_json::Error;

    fn from_str(source: &str) -> Result<Self, Self::Err> {
        serde_json::from_str(source)
    }
}

impl TemplateSourceJson {
    /// Serialize Cedar source for storage or a Cedar parser.
    pub fn to_json_string(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(&self.0)
    }
}

// Borrowing the policy JSON preserves its wire shape; it performs no admission.
impl Deref for CompiledPolicyJson {
    type Target = Value;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl Deref for TemplateSourceJson {
    type Target = Value;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

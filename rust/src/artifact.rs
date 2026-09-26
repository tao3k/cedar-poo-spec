//! Small, Cedar-independent representation of a compiled Lean policy set.

use serde::Deserialize;
use serde_json::Value;
use std::str::FromStr;

/// Materialized Cedar policy set in the public JSON policy-set format.
#[derive(Debug, Deserialize)]
#[serde(transparent)]
pub struct CompiledPolicyJson(Value);

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

    #[cfg(feature = "cedar-runtime")]
    pub(crate) fn as_value(&self) -> &Value {
        &self.0
    }
}

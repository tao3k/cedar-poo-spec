//! Google Sensitive Data Protection table request and response boundary.
//!
//! This module constructs REST bodies and checks caller-supplied responses. It
//! neither sends requests nor authenticates the source of a response. The Host
//! owns transport, KMS access, admission, persistence, and plaintext release.

use crate::pseudonymization::{Mode, TokenLineage, TokenProfile};
use base64::{Engine as _, engine::general_purpose::STANDARD};
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

/// A validated, single-row Google SDP AES-SIV table operation.
#[derive(Clone, Debug)]
pub struct TabularAesSiv {
    parent: String,
    value_field: String,
    context_field: String,
    value: String,
    context: String,
    kms_key_name: String,
    wrapped_key_base64: String,
    surrogate_info_type: Option<SurrogateInfoType>,
}

/// A named surrogate annotation used by Google SDP for reversible tokens.
#[derive(Clone, Debug, Deserialize, PartialEq, Eq)]
pub struct SurrogateInfoType(pub String);

/// The selected Lean table input, including catalog lineage. A Host must
/// authenticate its origin before using it as an execution instruction.
#[derive(Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SelectedTabularInput {
    pub dataset: String,
    pub value_field: String,
    pub context_field: String,
    pub value: String,
    pub context: String,
    pub key_domain: String,
    pub token_key_version: String,
    pub transform_version: String,
    pub wrapping_version: String,
    pub surrogate_info_type: Option<SurrogateInfoType>,
}

impl SelectedTabularInput {
    /// Project the selected Google row into the common token catalog. The
    /// caller supplies authenticated tenant and equality scope; neither is
    /// inferred from a provider endpoint or dataset name.
    #[must_use]
    pub fn token_profile<'a>(&'a self, tenant: &'a str, scope: &'a str) -> TokenProfile<'a> {
        TokenProfile {
            mode: Mode::AesSiv,
            scope,
            lineage: TokenLineage {
                tenant,
                key_domain: &self.key_domain,
                token_key_version: &self.token_key_version,
                transform_version: &self.transform_version,
                wrapping_version: &self.wrapping_version,
            },
        }
    }
}

/// A Host-resolved KMS wrapper for the exact catalog key lineage.
pub struct WrappedKeyBinding {
    pub key_domain: String,
    pub token_key_version: String,
    pub wrapping_version: String,
    pub kms_key_name: String,
    pub wrapped_key_base64: String,
}

/// Checked table content and digests; the Host still authenticates transport.
#[derive(Debug, PartialEq, Eq)]
pub struct CheckedTableOutput {
    /// This value is sensitive; callers must not print it as a diagnostic.
    pub value: String,
    pub request_sha256: String,
    pub response_sha256: String,
}

/// A serializable Google SDP REST request body with its schema kept private.
pub struct GoogleSdpRequest {
    body: Value,
}

impl GoogleSdpRequest {
    pub fn to_json_bytes(&self) -> Result<Vec<u8>, String> {
        serde_json::to_vec(&self.body).map_err(|error| error.to_string())
    }
}

/// A parsed response body supplied by the authenticated Host transport.
pub struct GoogleSdpResponse {
    body: Value,
}

impl GoogleSdpResponse {
    pub fn from_json_bytes(bytes: &[u8]) -> Result<Self, String> {
        Ok(Self {
            body: serde_json::from_slice(bytes).map_err(|error| error.to_string())?,
        })
    }
}

/// One bounded Google Table request formed from independently admitted rows.
/// Row identities are retained by the caller in the same order; Google does
/// not return MRR ordinals. The Host authenticates transport and response size.
pub struct TabularAesSivBatch {
    rows: Vec<TabularAesSiv>,
}

const ROW_MARKER_FIELD: &str = "__mrr_row_v1";
const MAX_BATCH_REQUEST_BYTES: usize = 400_000;

impl TabularAesSivBatch {
    /// Combine rows only when they share one endpoint, recipe and wrapped key.
    /// The hard row and input-byte ceilings mirror SPEC Table Batch V1.
    pub fn new(rows: Vec<TabularAesSiv>) -> Result<Self, String> {
        let first = rows.first().ok_or("empty Google SDP table batch")?;
        if rows.len() > 256 {
            return Err("Google SDP table batch exceeds 256 rows".into());
        }
        first.validate()?;
        let mut bytes = 0usize;
        for row in &rows {
            row.validate()?;
            if row.parent != first.parent
                || row.value_field != first.value_field
                || row.context_field != first.context_field
                || row.kms_key_name != first.kms_key_name
                || row.wrapped_key_base64 != first.wrapped_key_base64
                || row.surrogate_info_type != first.surrogate_info_type
            {
                return Err("Google SDP table batch mixes provider recipes".into());
            }
            bytes = bytes
                .checked_add(row.value.len())
                .and_then(|used| used.checked_add(row.context.len()))
                .filter(|used| *used <= 1_048_576)
                .ok_or("Google SDP table batch exceeds selected UTF-8 budget")?;
        }
        if first.value_field == ROW_MARKER_FIELD || first.context_field == ROW_MARKER_FIELD {
            return Err("Google SDP field conflicts with the batch row marker".into());
        }
        let batch = Self { rows };
        if batch.deidentify_body()?.to_json_bytes()?.len() > MAX_BATCH_REQUEST_BYTES {
            return Err("Google SDP serialized batch request exceeds local wire budget".into());
        }
        Ok(batch)
    }

    /// The shared de-identification endpoint for this batch.
    pub fn endpoint(&self) -> Result<String, String> {
        self.rows[0].endpoint(false)
    }

    /// Construct one Table request with ordered value/context rows.
    pub fn deidentify_body(&self) -> Result<GoogleSdpRequest, String> {
        let first = &self.rows[0];
        let rows: Vec<Value> = self
            .rows
            .iter()
            .enumerate()
            .map(|(index, row)| {
                json!({"values": [
                    {"stringValue": row.value}, {"stringValue": row.context},
                    {"stringValue": format!("r{index}")}
                ]})
            })
            .collect();
        Ok(GoogleSdpRequest {
            body: json!({
                "deidentifyConfig": first.transformation(),
                "item": {"table": {
                    "headers": [
                        {"name": first.value_field}, {"name": first.context_field},
                        {"name": ROW_MARKER_FIELD}
                    ],
                    "rows": rows
                }}
            }),
        })
    }

    /// Admit no local row output unless the entire response has the selected
    /// shape, one success per row, unchanged contexts and valid changed tokens.
    /// A rejected response says nothing about external provider side effects.
    pub fn check_deidentify_response(
        &self,
        response: &GoogleSdpResponse,
    ) -> Result<Vec<CheckedTableOutput>, String> {
        let output_rows = self.response_rows(response)?;
        self.check_summary(response)?;
        let request_sha256 = hex_digest(&self.deidentify_body()?.body)?;
        let response_sha256 = hex_digest(&response.body)?;
        self.rows
            .iter()
            .zip(output_rows)
            .enumerate()
            .map(|(index, (selected, output))| {
                let value = Self::checked_row(index, selected, output)?;
                Ok(CheckedTableOutput {
                    value,
                    request_sha256: request_sha256.clone(),
                    response_sha256: response_sha256.clone(),
                })
            })
            .collect()
    }

    fn response_rows<'a>(&self, response: &'a GoogleSdpResponse) -> Result<&'a [Value], String> {
        let first = &self.rows[0];
        let table = response
            .body
            .pointer("/item/table")
            .ok_or("missing Google SDP response table")?;
        let headers = table["headers"]
            .as_array()
            .ok_or("missing Google SDP response headers")?;
        let output_rows = table["rows"]
            .as_array()
            .ok_or("missing Google SDP response rows")?;
        if headers.len() != 3
            || headers[0]["name"] != first.value_field
            || headers[1]["name"] != first.context_field
            || headers[2]["name"] != ROW_MARKER_FIELD
            || output_rows.len() != self.rows.len()
        {
            return Err("Google SDP response changed the batch table shape".into());
        }
        Ok(output_rows)
    }

    fn check_summary(&self, response: &GoogleSdpResponse) -> Result<(), String> {
        let first = &self.rows[0];
        let summaries = response
            .body
            .pointer("/overview/transformationSummaries")
            .and_then(Value::as_array)
            .ok_or("missing Google SDP transformation overview")?;
        if summaries.len() != 1
            || summaries[0]["field"]["name"] != first.value_field
            || summaries[0]["results"].as_array().is_none_or(|results| {
                results.len() != 1
                    || results[0]["code"] != "SUCCESS"
                    || results[0]["count"]
                        .as_str()
                        .and_then(|count| count.parse::<usize>().ok())
                        != Some(self.rows.len())
            })
        {
            return Err("Google SDP did not report exact batch success".into());
        }
        Ok(())
    }

    fn checked_row(
        index: usize,
        selected: &TabularAesSiv,
        output: &Value,
    ) -> Result<String, String> {
        let values = output["values"]
            .as_array()
            .ok_or("missing Google SDP response values")?;
        if values.len() != 3
            || values[1]["stringValue"] != selected.context
            || values[2]["stringValue"] != format!("r{index}")
        {
            return Err("Google SDP changed a batch context or row shape".into());
        }
        let token = values[0]["stringValue"]
            .as_str()
            .ok_or("missing Google SDP batch token")?;
        if token.is_empty() || token == selected.value {
            return Err("Google SDP did not transform a selected batch cell".into());
        }
        selected.check_token_format(token)?;
        Ok(token.to_owned())
    }
}

fn hex_digest(value: &Value) -> Result<String, String> {
    let bytes = serde_json::to_vec(value).map_err(|error| error.to_string())?;
    Ok(Sha256::digest(bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect())
}

impl TabularAesSiv {
    fn check_token_format(&self, token: &str) -> Result<(), String> {
        let encoded = match &self.surrogate_info_type {
            None => token,
            Some(info_type) => {
                let rest = token
                    .strip_prefix(&format!("{}(", info_type.0))
                    .ok_or("Google SDP token has the wrong surrogate annotation")?;
                let (length, encoded) = rest
                    .split_once("):")
                    .ok_or("Google SDP token has an invalid surrogate annotation")?;
                if length.parse::<usize>().ok() != Some(encoded.chars().count()) {
                    return Err("Google SDP token surrogate length differs".into());
                }
                encoded
            }
        };
        if STANDARD
            .decode(encoded)
            .map_or(true, |bytes| bytes.len() <= 16)
        {
            return Err("Google SDP AES-SIV token is not a base64 ciphertext".into());
        }
        Ok(())
    }

    pub fn from_selected(
        parent: String,
        selected: SelectedTabularInput,
        key: WrappedKeyBinding,
    ) -> Result<Self, String> {
        if selected.dataset.is_empty()
            || selected.transform_version.is_empty()
            || selected.key_domain != key.key_domain
            || selected.token_key_version != key.token_key_version
            || selected.wrapping_version != key.wrapping_version
        {
            return Err("Google SDP key binding differs from the selected token lineage".into());
        }
        let plan = Self {
            parent,
            value_field: selected.value_field,
            context_field: selected.context_field,
            value: selected.value,
            context: selected.context,
            kms_key_name: key.kms_key_name,
            wrapped_key_base64: key.wrapped_key_base64,
            surrogate_info_type: selected.surrogate_info_type,
        };
        plan.validate()?;
        Ok(plan)
    }

    fn validate(&self) -> Result<(), String> {
        let parts: Vec<_> = self.parent.split('/').collect();
        let kms_parts: Vec<_> = self.kms_key_name.split('/').collect();
        let safe_segment = |value: &str| {
            !value.is_empty()
                && value
                    .chars()
                    .all(|char| char.is_ascii_alphanumeric() || char == '-' || char == '_')
        };
        if parts.len() != 4
            || parts[0] != "projects"
            || parts[2] != "locations"
            || !safe_segment(parts[1])
            || !safe_segment(parts[3])
            || kms_parts.len() != 8
            || kms_parts[0] != "projects"
            || kms_parts[2] != "locations"
            || kms_parts[4] != "keyRings"
            || kms_parts[6] != "cryptoKeys"
            || ![1, 3, 5, 7]
                .into_iter()
                .all(|index| safe_segment(kms_parts[index]))
            || self.value_field.is_empty()
            || self.context_field.is_empty()
            || self.value_field == self.context_field
            || self.value.is_empty()
            || self.context.is_empty()
            || STANDARD
                .decode(&self.wrapped_key_base64)
                .map_or(true, |bytes| bytes.is_empty())
            || self
                .surrogate_info_type
                .as_ref()
                .is_some_and(|name| name.0.is_empty())
        {
            return Err("invalid Google SDP tabular AES-SIV configuration".into());
        }
        Ok(())
    }

    pub fn endpoint(&self, reidentify: bool) -> Result<String, String> {
        self.validate()?;
        let operation = if reidentify {
            "reidentify"
        } else {
            "deidentify"
        };
        Ok(format!(
            "https://dlp.googleapis.com/v2/{}/content:{operation}",
            self.parent
        ))
    }

    fn transformation(&self) -> Value {
        let mut config = json!({
            "cryptoKey": {"kmsWrapped": {
                "wrappedKey": self.wrapped_key_base64,
                "cryptoKeyName": self.kms_key_name
            }},
            "context": {"name": self.context_field}
        });
        if let Some(name) = &self.surrogate_info_type {
            config["surrogateInfoType"] = json!({"name": name.0});
        }
        json!({"recordTransformations": {"fieldTransformations": [{
            "fields": [{"name": self.value_field}],
            "primitiveTransformation": {"cryptoDeterministicConfig": config}
        }]}})
    }

    fn table(&self, value: &str) -> Value {
        json!({"table": {
            "headers": [{"name": self.value_field}, {"name": self.context_field}],
            "rows": [{"values": [
                {"stringValue": value}, {"stringValue": self.context}
            ]}]
        }})
    }

    /// The JSON body for `projects.locations.content.deidentify`.
    pub fn deidentify_body(&self) -> Result<GoogleSdpRequest, String> {
        self.validate()?;
        Ok(GoogleSdpRequest {
            body: json!({
                "deidentifyConfig": self.transformation(),
                "item": self.table(&self.value)
            }),
        })
    }

    /// The JSON body for `projects.locations.content.reidentify`.
    pub fn reidentify_body(&self, token: &str) -> Result<GoogleSdpRequest, String> {
        self.validate()?;
        if token.is_empty() || token == self.value {
            return Err("missing transformed token".into());
        }
        Ok(GoogleSdpRequest {
            body: json!({
                "reidentifyConfig": self.transformation(),
                "item": self.table(token)
            }),
        })
    }

    fn check_response(
        &self,
        request: &GoogleSdpRequest,
        response: &GoogleSdpResponse,
        expected: &str,
    ) -> Result<CheckedTableOutput, String> {
        self.validate()?;
        let table = response
            .body
            .pointer("/item/table")
            .ok_or("missing Google SDP response table")?;
        let headers = table["headers"]
            .as_array()
            .ok_or("missing Google SDP response headers")?;
        let rows = table["rows"]
            .as_array()
            .ok_or("missing Google SDP response rows")?;
        if headers.len() != 2
            || rows.len() != 1
            || headers[0]["name"] != self.value_field
            || headers[1]["name"] != self.context_field
        {
            return Err("Google SDP response changed the table shape".into());
        }
        let values = rows[0]["values"]
            .as_array()
            .ok_or("missing Google SDP response values")?;
        let output = values
            .first()
            .and_then(|value| value["stringValue"].as_str());
        if values.len() != 2
            || values[1]["stringValue"] != self.context
            || output.is_none_or(|value| value.is_empty() || value == expected)
        {
            return Err("Google SDP response did not transform the selected cell".into());
        }
        let summaries = response
            .body
            .pointer("/overview/transformationSummaries")
            .and_then(Value::as_array)
            .ok_or("missing Google SDP transformation overview")?;
        let success = summaries.iter().any(|summary| {
            summary["field"]["name"] == self.value_field
                && summary["results"].as_array().is_some_and(|results| {
                    results.len() == 1
                        && results[0]["code"] == "SUCCESS"
                        && results[0]["count"] == "1"
                })
        });
        if !success
            || summaries.iter().any(|summary| {
                summary["results"]
                    .as_array()
                    .is_some_and(|results| results.iter().any(|result| result["code"] == "ERROR"))
            })
        {
            return Err("Google SDP did not report one successful transformation".into());
        }
        Ok(CheckedTableOutput {
            value: output.expect("checked above").to_owned(),
            request_sha256: hex_digest(&request.body)?,
            response_sha256: hex_digest(&response.body)?,
        })
    }

    /// Checks a response body supplied by the authenticated Host transport.
    pub fn check_deidentify_response(
        &self,
        response: &GoogleSdpResponse,
    ) -> Result<CheckedTableOutput, String> {
        let checked = self.check_response(&self.deidentify_body()?, response, &self.value)?;
        self.check_token_format(&checked.value)?;
        Ok(checked)
    }

    /// Checks the returned cell against the selected original value.
    pub fn check_reidentify_response(
        &self,
        token: &str,
        response: &GoogleSdpResponse,
    ) -> Result<CheckedTableOutput, String> {
        self.check_token_format(token)?;
        let checked = self.check_response(&self.reidentify_body(token)?, response, token)?;
        if checked.value != self.value {
            return Err("Google SDP re-identification changed the selected value".into());
        }
        Ok(checked)
    }
}

#[cfg(test)]
#[path = "../tests/unit/google_sdp.rs"]
mod tests;

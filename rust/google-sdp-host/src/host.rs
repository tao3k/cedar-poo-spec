//! In-memory admission and release boundary for a Google SDP table effect.
//! The caller owns authenticated transport, approval facts, and durable storage.

use cedar_poo_pseudonymization::google_sdp::{
    CheckedTableOutput, GoogleSdpResponse, SelectedTabularInput, TabularAesSiv, WrappedKeyBinding,
};
use cedar_poo_runtime::{Case, ValidatedManifest, replay_validated_manifest};
use serde::Serialize;
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};

/// The Google table operation authorized by a concrete Cedar request.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TableEffect {
    Deidentify,
    Reidentify,
}

/// The selected row, resolved key, and requested Google operation.
pub struct TableEffectInput {
    pub selected: SelectedTabularInput,
    pub key: WrappedKeyBinding,
    pub parent: String,
    pub effect: TableEffect,
    pub token: Option<String>,
}

impl TableEffect {
    fn action(self) -> &'static str {
        match self {
            Self::Deidentify => "Action::\"tokenize\"",
            Self::Reidentify => "Action::\"reidentify\"",
        }
    }
}

/// One-time preparation. Private fields prevent a caller from changing its binding.
pub struct PreparedTableEffect {
    epoch: u64,
    approval_revision: u64,
    policies_sha256: String,
    schema_sha256: String,
    cedar_request_sha256: String,
    google_request_sha256: String,
    endpoint: String,
    effect: TableEffect,
    plan: TabularAesSiv,
    token: Option<String>,
    provenance: TokenProvenance,
}

/// Catalog lineage of a token issued by this Host. The token itself is stored
/// only as a digest; wrapping revisions may change without changing the DEK.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
struct TokenProvenance {
    dataset: String,
    tenant: String,
    context: String,
    key_domain: String,
    token_key_version: String,
    transform_version: String,
}

impl TokenProvenance {
    fn same_recipe(&self, other: &Self) -> bool {
        self.tenant == other.tenant
            && self.context == other.context
            && self.key_domain == other.key_domain
            && self.token_key_version == other.token_key_version
            && self.transform_version == other.transform_version
    }
}

impl TokenProvenance {
    fn from_selected(selected: &SelectedTabularInput, tenant: String) -> Self {
        Self {
            dataset: selected.dataset.clone(),
            tenant,
            context: selected.context.clone(),
            key_domain: selected.key_domain.clone(),
            token_key_version: selected.token_key_version.clone(),
            transform_version: selected.transform_version.clone(),
        }
    }
}

/// An audit record containing digests, without a token or recovered plaintext.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TableEffectAudit {
    pub epoch: u64,
    pub approval_revision: u64,
    pub policies_sha256: String,
    pub schema_sha256: String,
    pub cedar_request_sha256: String,
    pub google_request_sha256: String,
    pub endpoint: String,
    pub google_response_sha256: String,
}

/// A finite demonstration of admission and release. It is not a durable store.
pub struct InMemoryGoogleSdpHost {
    epoch: u64,
    approval_revision: u64,
    policies_sha256: String,
    audit_ready: bool,
    audit: Vec<TableEffectAudit>,
    issued_tokens: HashMap<String, HashSet<TokenProvenance>>,
}

fn digest(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

fn unique_case<'a>(manifest: &'a ValidatedManifest, name: &str) -> Result<&'a Case, String> {
    let mut matches = manifest.cases.iter().filter(|case| case.name == name);
    let case = matches.next().ok_or("missing Cedar case")?;
    if matches.next().is_some() {
        return Err("duplicate Cedar case".into());
    }
    Ok(case)
}

fn check_selected(
    case: &Case,
    selected: &SelectedTabularInput,
    effect: TableEffect,
) -> Result<String, String> {
    let dataset_uid = format!("Dataset::\"{}\"", selected.dataset);
    let target = case
        .request
        .context
        .pointer("/targetDataset/__entity/id")
        .and_then(Value::as_str);
    let entity = case.entities.as_array().and_then(|entities| {
        entities.iter().find(|entity| {
            entity.pointer("/uid/type").and_then(Value::as_str) == Some("Dataset")
                && entity.pointer("/uid/id").and_then(Value::as_str)
                    == Some(selected.dataset.as_str())
        })
    });
    let attrs = entity
        .and_then(|entity| entity.get("attrs"))
        .ok_or("missing admitted dataset entity")?;
    let attr = |name: &str| attrs.get(name).and_then(Value::as_str);
    if case.request.action != effect.action()
        || case.request.resource != dataset_uid
        || target != Some(selected.dataset.as_str())
        || case
            .request
            .context
            .get("requestedKeyVersion")
            .and_then(Value::as_str)
            != Some(selected.token_key_version.as_str())
        || attr("mode") != Some("aes-siv")
        || attr("scope") != Some(selected.context.as_str())
        || attr("keyDomain") != Some(selected.key_domain.as_str())
        || attr("tokenKeyVersion") != Some(selected.token_key_version.as_str())
        || attr("transformVersion") != Some(selected.transform_version.as_str())
        || attr("wrappingVersion") != Some(selected.wrapping_version.as_str())
    {
        return Err("selected table input differs from Cedar request or dataset".into());
    }
    let tenant = attr("tenant").ok_or("missing admitted dataset tenant")?;
    if tenant.is_empty() {
        return Err("missing admitted dataset tenant".into());
    }
    Ok(tenant.to_owned())
}

impl InMemoryGoogleSdpHost {
    fn token_issued_for(&self, token: &str, provenance: &TokenProvenance) -> bool {
        self.issued_tokens
            .get(&digest(token.as_bytes()))
            .is_some_and(|issued| issued.contains(provenance))
    }

    fn token_compatible_with_catalog(&self, token: &str, provenance: &TokenProvenance) -> bool {
        self.issued_tokens
            .get(&digest(token.as_bytes()))
            .is_none_or(|issued| {
                issued
                    .iter()
                    .all(|existing| existing.same_recipe(provenance))
            })
    }

    fn catalog_token(&mut self, token: &str, provenance: TokenProvenance) {
        self.issued_tokens
            .entry(digest(token.as_bytes()))
            .or_default()
            .insert(provenance);
    }

    /// Start at a deployed policy digest and approval revision chosen by the Host.
    pub fn new(policies_sha256: String, approval_revision: u64) -> Self {
        Self {
            epoch: 0,
            approval_revision,
            policies_sha256,
            audit_ready: true,
            audit: Vec::new(),
            issued_tokens: HashMap::new(),
        }
    }

    /// Invalidate prepared tickets after an approval change.
    pub fn revise_approval(&mut self) {
        self.approval_revision += 1;
        self.epoch += 1;
    }

    /// Invalidate prepared tickets after a policy deployment.
    pub fn deploy_policy(&mut self, policies_sha256: String) {
        self.policies_sha256 = policies_sha256;
        self.epoch += 1;
    }

    /// Model failure of the audit sink before any value can be released.
    pub fn set_audit_ready(&mut self, ready: bool) {
        if self.audit_ready != ready {
            self.audit_ready = ready;
            self.epoch += 1;
        }
    }

    /// Replay official Cedar, bind a selected row, and prepare exact Google bytes.
    pub fn prepare(
        &self,
        manifest: &ValidatedManifest,
        case_name: &str,
        input: TableEffectInput,
    ) -> Result<(PreparedTableEffect, String, Vec<u8>), String> {
        let TableEffectInput {
            selected,
            key,
            parent,
            effect,
            token,
        } = input;
        let case = unique_case(manifest, case_name)?;
        let tenant = check_selected(case, &selected, effect)?;
        let provenance = TokenProvenance::from_selected(&selected, tenant);
        let receipts = replay_validated_manifest(manifest)?;
        let receipt = receipts
            .iter()
            .find(|receipt| receipt.replay.case_name == case_name)
            .ok_or("missing Cedar replay")?;
        if !receipt.replay.error_free_allow
            || receipt.replay.policies_sha256 != self.policies_sha256
        {
            return Err("Cedar decision is denied or its policy revision is stale".into());
        }
        if effect == TableEffect::Reidentify
            && !self.token_issued_for(token.as_deref().ok_or("missing token")?, &provenance)
        {
            return Err("token was not issued for this dataset and key lineage".into());
        }
        let plan = TabularAesSiv::from_selected(parent, selected, key)?;
        let request = match effect {
            TableEffect::Deidentify if token.is_none() => plan.deidentify_body()?,
            TableEffect::Reidentify => {
                plan.reidentify_body(token.as_deref().ok_or("missing token")?)?
            }
            _ => return Err("token does not match the requested effect".into()),
        };
        let bytes = request.to_json_bytes()?;
        let endpoint = plan.endpoint(effect == TableEffect::Reidentify)?;
        Ok((
            PreparedTableEffect {
                epoch: self.epoch,
                approval_revision: self.approval_revision,
                policies_sha256: receipt.replay.policies_sha256.clone(),
                schema_sha256: receipt.schema_sha256.clone(),
                cedar_request_sha256: receipt.replay.request_sha256.clone(),
                google_request_sha256: digest(&bytes),
                endpoint: endpoint.clone(),
                effect,
                plan,
                token,
                provenance,
            },
            endpoint,
            bytes,
        ))
    }

    /// Check the transport endpoint and caller-supplied response, append an
    /// in-memory audit, then release.
    /// A production Host must authenticate transport and persist audit atomically.
    pub fn commit(
        &mut self,
        ticket: PreparedTableEffect,
        endpoint: &str,
        response_bytes: &[u8],
    ) -> Result<CheckedTableOutput, String> {
        if ticket.epoch != self.epoch
            || ticket.approval_revision != self.approval_revision
            || ticket.policies_sha256 != self.policies_sha256
            || ticket.endpoint != endpoint
            || !self.audit_ready
        {
            return Err("ticket is stale or audit is unavailable".into());
        }
        let response = GoogleSdpResponse::from_json_bytes(response_bytes)?;
        let checked = match ticket.effect {
            TableEffect::Deidentify => ticket.plan.check_deidentify_response(&response)?,
            TableEffect::Reidentify => ticket.plan.check_reidentify_response(
                ticket.token.as_deref().ok_or("missing token")?,
                &response,
            )?,
        };
        if checked.request_sha256 != ticket.google_request_sha256 {
            return Err("Google request changed after admission".into());
        }
        if ticket.effect == TableEffect::Deidentify
            && !self.token_compatible_with_catalog(&checked.value, &ticket.provenance)
        {
            return Err("token collides with another dataset or key lineage".into());
        }
        self.audit.push(TableEffectAudit {
            epoch: self.epoch,
            approval_revision: self.approval_revision,
            policies_sha256: ticket.policies_sha256,
            schema_sha256: ticket.schema_sha256,
            cedar_request_sha256: ticket.cedar_request_sha256,
            google_request_sha256: checked.request_sha256.clone(),
            endpoint: ticket.endpoint,
            google_response_sha256: checked.response_sha256.clone(),
        });
        if ticket.effect == TableEffect::Deidentify {
            self.catalog_token(&checked.value, ticket.provenance);
        }
        self.epoch += 1;
        Ok(checked)
    }

    /// Read digest-only audit entries from this process.
    pub fn audit(&self) -> &[TableEffectAudit] {
        &self.audit
    }
}

#[cfg(test)]
#[path = "../tests/unit/google_sdp_host.rs"]
mod tests;

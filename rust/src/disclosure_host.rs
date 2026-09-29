//! In-memory Host reference for a derived clinical disclosure effect.
//! Authenticated inputs and durable storage remain the deploying Host's duty.

use crate::authority_consumption::{AuthorityId, AuthorityLedger};
use crate::{
    ValidatedManifest, load_policy_set, render_validated_policy_sources, replay_validated_manifest,
};
use cedar_policy::{
    Authorizer, Context, Decision, Entities, EntityUid, PolicySet, Request, Schema,
};
use serde::Serialize;
use serde_json::json;
use std::collections::HashSet;
use std::str::FromStr;
use std::sync::{Arc, Mutex};

/// Proposed disclosure bound to its source lineage, recipient, purpose, output,
/// channel, and cohort evidence. The Host must verify these values independently.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Effect {
    pub sources: Vec<String>,
    pub destination: String,
    pub purpose: String,
    pub channel: String,
    pub payload_digest: String,
    pub candidate_ids: Vec<String>,
}

/// A scoped approval or delegation asserted by an authenticated authority.
#[derive(Clone, Debug)]
pub struct Grant {
    pub issuer: String,
    pub grantee: String,
    pub action: String,
    pub source: String,
    pub destination: String,
    pub purpose: String,
    pub revision: u64,
    pub expires_at: u64,
}

impl Grant {
    fn covers(
        &self,
        effect: &Effect,
        source: &str,
        evidence: &Evidence,
        grantee: &str,
        action: &str,
        revision: u64,
    ) -> bool {
        self.issuer == evidence.trusted_owner
            && self.grantee == grantee
            && self.action == action
            && self.source == source
            && self.destination == effect.destination
            && self.purpose == effect.purpose
            && self.revision == revision
            && evidence.now < self.expires_at
    }
}

/// These values must come from authenticated catalogs, provider receipts,
/// approval stores, and an audit-capable transaction in a real deployment.
#[derive(Clone, Debug)]
pub struct Evidence {
    pub epoch: u64,
    pub policy_revision: u64,
    pub approval_revision: u64,
    pub delegation_revision: u64,
    pub now: u64,
    pub budget: u64,
    pub trusted_sources: Vec<String>,
    pub trusted_owner: String,
    pub allowed_destinations: Vec<String>,
    pub observed_digest: String,
    pub observed_candidate_ids: Vec<String>,
    pub approvals: Vec<Grant>,
    pub delegations: Vec<Grant>,
    pub possible_ids: Vec<String>,
    pub minimum_cohort: usize,
    pub audit_ready: bool,
}

impl Evidence {
    fn narrowed(&self, effect: &Effect) -> Vec<String> {
        let proposed = effect.candidate_ids.iter().collect::<HashSet<_>>();
        let mut seen = HashSet::new();
        self.possible_ids
            .iter()
            .filter(|id| proposed.contains(id) && seen.insert((*id).clone()))
            .cloned()
            .collect()
    }

    fn grants_cover(
        &self,
        effect: &Effect,
        grants: &[Grant],
        grantee: &str,
        action: &str,
        revision: u64,
    ) -> bool {
        effect.sources.iter().all(|source| {
            grants
                .iter()
                .any(|grant| grant.covers(effect, source, self, grantee, action, revision))
        })
    }
}

struct PolicyBundle {
    schema: Schema,
    entities: Entities,
    policies: PolicySet,
    principal: String,
    action: String,
}

/// Validates the Lean export and official Cedar replay once, then shares the
/// immutable policy across independent process-local Host instances.
#[derive(Clone)]
pub struct ValidatedDisclosurePolicy(Arc<PolicyBundle>);

impl ValidatedDisclosurePolicy {
    pub fn from_manifest(manifest: &ValidatedManifest) -> Result<Self, String> {
        Ok(Self(Arc::new(PolicyBundle::from_manifest(manifest)?)))
    }
}

impl PolicyBundle {
    fn from_manifest(manifest: &ValidatedManifest) -> Result<Self, String> {
        replay_validated_manifest(manifest)?;
        render_validated_policy_sources(manifest, "source-governed-study")?;
        let schema = Schema::from_json_value(manifest.schema.clone())
            .map_err(|error| format!("Cedar schema: {error}"))?;
        let mut cases = manifest
            .cases
            .iter()
            .filter(|case| case.name == "source-governed-study");
        let case = cases.next().ok_or("missing governed disclosure case")?;
        if cases.next().is_some() {
            return Err("duplicate governed disclosure case".into());
        }
        let entities = Entities::from_json_value(case.entities.clone(), Some(&schema))
            .map_err(|error| format!("Cedar entities: {error}"))?;
        let policies = load_policy_set(&case.policies)?;
        Ok(Self {
            schema,
            entities,
            policies,
            principal: case.request.principal.clone(),
            action: case.request.action.clone(),
        })
    }

    fn allows(&self, evidence: &Evidence, effect: &Effect) -> Result<bool, String> {
        let lineage = !effect.sources.is_empty()
            && effect.sources == evidence.trusted_sources
            && evidence.allowed_destinations.contains(&effect.destination);
        let approval = evidence.grants_cover(
            effect,
            &evidence.approvals,
            &self.principal,
            &self.action,
            evidence.approval_revision,
        );
        let delegation = evidence.grants_cover(
            effect,
            &evidence.delegations,
            &self.principal,
            &self.action,
            evidence.delegation_revision,
        );
        let cohort = evidence.minimum_cohort == 0
            || (!effect.candidate_ids.is_empty()
                && evidence.narrowed(effect).len() >= evidence.minimum_cohort);
        let bound = !effect.payload_digest.is_empty()
            && effect.payload_digest == evidence.observed_digest
            && effect.candidate_ids == evidence.observed_candidate_ids
            && !effect.channel.is_empty();
        let action = EntityUid::from_str(&self.action).map_err(|error| error.to_string())?;
        let context = Context::from_json_value(
            json!({
                "lineageAllowed": lineage,
                "approvalActive": approval,
                "delegationActive": delegation,
                "cohortSafe": cohort,
                "budgetAvailable": evidence.budget > 0,
                "payloadBound": bound,
                "auditReady": evidence.audit_ready,
            }),
            Some((&self.schema, &action)),
        )
        .map_err(|error| format!("Cedar context: {error}"))?;
        let request = Request::new(
            EntityUid::from_str(&self.principal).map_err(|error| error.to_string())?,
            action,
            EntityUid::from_str(&effect.destination).map_err(|error| error.to_string())?,
            context,
            Some(&self.schema),
        )
        .map_err(|error| format!("Cedar request: {error}"))?;
        let response = Authorizer::new().is_authorized(&request, &self.policies, &self.entities);
        Ok(response.decision() == Decision::Allow
            && response.diagnostics().errors().next().is_none())
    }
}

/// Prepared authority for one exact effect at specific Host state revisions.
#[derive(Clone, Debug)]
pub struct Ticket {
    effect: Effect,
    authority_id: AuthorityId,
    epoch: u64,
    policy_revision: u64,
    approval_revision: u64,
    delegation_revision: u64,
}

/// Process-local audit record emitted after a successful state commit.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommitReceipt {
    pub epoch: u64,
    pub authority_id: String,
    pub authority_used: u64,
    pub sources: Vec<String>,
    pub destination: String,
    pub purpose: String,
    pub payload_digest: String,
    pub channel: String,
    pub policy_revision: u64,
    pub approval_revision: u64,
    pub delegation_revision: u64,
    pub remaining_budget: u64,
    pub remaining_candidates: usize,
}

struct Inner {
    policies: Arc<PolicyBundle>,
    evidence: Evidence,
    authority: AuthorityLedger<Effect>,
    audit: Vec<CommitReceipt>,
}

/// A process-local serializable model. `commit` keeps Cedar reauthorization,
/// approval consumption, budget debit, cohort update, and the audit entry
/// under one mutex.
pub struct InMemoryDisclosureHost {
    inner: Mutex<Inner>,
}

impl InMemoryDisclosureHost {
    pub fn new(
        policy: &ValidatedDisclosurePolicy,
        evidence: Evidence,
        authority: AuthorityLedger<Effect>,
    ) -> Self {
        Self {
            inner: Mutex::new(Inner {
                policies: Arc::clone(&policy.0),
                evidence,
                authority,
                audit: Vec::new(),
            }),
        }
    }

    pub fn prepare(
        &self,
        authority_id: AuthorityId,
        effect: Effect,
    ) -> Result<Option<Ticket>, String> {
        let inner = self.inner.lock().map_err(|_| "Host lock poisoned")?;
        if inner.authority.check(&authority_id, &effect).is_err()
            || !inner.policies.allows(&inner.evidence, &effect)?
        {
            return Ok(None);
        }
        let state = &inner.evidence;
        Ok(Some(Ticket {
            effect,
            authority_id,
            epoch: state.epoch,
            policy_revision: state.policy_revision,
            approval_revision: state.approval_revision,
            delegation_revision: state.delegation_revision,
        }))
    }

    /// Returns a receipt only after the in-memory audit and ledger update.
    /// Durable stores must implement an equivalent single transaction.
    pub fn commit(&self, ticket: Ticket, actual: &Effect) -> Result<Option<CommitReceipt>, String> {
        let mut inner = self.inner.lock().map_err(|_| "Host lock poisoned")?;
        let state = &inner.evidence;
        if ticket.effect != *actual
            || ticket.epoch != state.epoch
            || ticket.policy_revision != state.policy_revision
            || ticket.approval_revision != state.approval_revision
            || ticket.delegation_revision != state.delegation_revision
            || inner.authority.check(&ticket.authority_id, actual).is_err()
            || !inner.policies.allows(state, actual)?
        {
            return Ok(None);
        }
        let narrowed = state.narrowed(actual);
        let update_cohort = state.minimum_cohort != 0;
        let authority_used = inner
            .authority
            .used(&ticket.authority_id)
            .map_err(|error| format!("authority changed during commit: {error:?}"))?
            + 1;
        let receipt = CommitReceipt {
            epoch: state.epoch + 1,
            authority_id: ticket.authority_id.0.clone(),
            authority_used,
            sources: actual.sources.clone(),
            destination: actual.destination.clone(),
            purpose: actual.purpose.clone(),
            payload_digest: actual.payload_digest.clone(),
            channel: actual.channel.clone(),
            policy_revision: state.policy_revision,
            approval_revision: state.approval_revision,
            delegation_revision: state.delegation_revision,
            remaining_budget: state.budget - 1,
            remaining_candidates: if state.minimum_cohort == 0 {
                state.possible_ids.len()
            } else {
                narrowed.len()
            },
        };
        inner
            .authority
            .consume(&ticket.authority_id, actual)
            .map_err(|error| format!("authority changed during commit: {error:?}"))?;
        if update_cohort {
            inner.evidence.possible_ids = narrowed;
        }
        inner.evidence.budget -= 1;
        inner.evidence.epoch += 1;
        inner.audit.push(receipt.clone());
        Ok(Some(receipt))
    }

    pub fn observe_output(&self, digest: String, candidate_ids: Vec<String>) -> Result<(), String> {
        let mut inner = self.inner.lock().map_err(|_| "Host lock poisoned")?;
        inner.evidence.observed_digest = digest;
        inner.evidence.observed_candidate_ids = candidate_ids;
        inner.evidence.epoch += 1;
        Ok(())
    }

    pub fn revoke_delegation(&self) -> Result<(), String> {
        let mut inner = self.inner.lock().map_err(|_| "Host lock poisoned")?;
        inner.evidence.delegation_revision += 1;
        inner.evidence.epoch += 1;
        Ok(())
    }

    pub fn set_audit_ready(&self, ready: bool) -> Result<(), String> {
        let mut inner = self.inner.lock().map_err(|_| "Host lock poisoned")?;
        inner.evidence.audit_ready = ready;
        inner.evidence.epoch += 1;
        Ok(())
    }

    pub fn audit(&self) -> Result<Vec<CommitReceipt>, String> {
        let inner = self.inner.lock().map_err(|_| "Host lock poisoned")?;
        Ok(inner.audit.clone())
    }

    pub fn authority_used(&self, id: &AuthorityId) -> Result<Option<u64>, String> {
        let inner = self.inner.lock().map_err(|_| "Host lock poisoned")?;
        Ok(inner.authority.used(id).ok())
    }
}

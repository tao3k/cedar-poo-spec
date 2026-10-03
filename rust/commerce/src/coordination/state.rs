//! Co-located Checkout gate/journals and a single-record compare-and-swap contract.
//! Identity enrollment, current trust, durable storage and external sends remain Host duties.
use crate::presentation::{
    CLOSED_CHECKOUT_VCT, CheckoutPresentation, OPEN_CHECKOUT_VCT, PresentationLedger,
    VerifiedCheckoutReceipt,
};
use serde::Serialize;
use std::collections::BTreeMap;

/// Refusals before any persistence operation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CoordinationError {
    InvalidIdentity,
    InvalidTransition,
    InvalidSnapshot,
    Limit,
}

/// Host-enrolled grouping, not a token-derived or caller-supplied request scope.
/// Authorization aliases must resolve to the same canonical authorization ID.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct CheckoutCoordinationIdentity {
    enrollment_namespace: String,
    authorization_id: String,
    agent_id: String,
    policy_id: String,
}
impl CheckoutCoordinationIdentity {
    /// Bind independently authenticated registry values. This validates shape only;
    /// it does not enroll authority or prove that aliases were canonicalized.
    /// # Errors
    /// Refuses empty or oversized registry components.
    pub fn enrolled(
        namespace: &str,
        authorization: &str,
        agent: &str,
        policy: &str,
    ) -> Result<Self, CoordinationError> {
        if [namespace, authorization, agent, policy]
            .iter()
            .any(|s| s.is_empty() || s.len() > 256)
        {
            return Err(CoordinationError::InvalidIdentity);
        }
        Ok(Self {
            enrollment_namespace: namespace.into(),
            authorization_id: authorization.into(),
            agent_id: agent.into(),
            policy_id: policy.into(),
        })
    }
    /// Versioned, domain-separated local storage key. Tuple encoding preserves
    /// component boundaries; hashing does not resolve registry aliases.
    pub fn storage_key(&self) -> String {
        let encoded = serde_json::to_vec(&(
            "cedar-poo.checkout-coordination.v1",
            &self.enrollment_namespace,
            &self.authorization_id,
            &self.agent_id,
            &self.policy_id,
        ))
        .expect("string tuple serialization");
        crate::signatures::sha256_hex(&encoded)
    }
}

/// One whole record owns both shared authority and all alias journals.
/// Private fields prevent constructing mismatched gate/journal proposals.
/// No public Deserialize: restore only through bounded structural validation.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct SharedCheckoutState {
    pub(super) identity: CheckoutCoordinationIdentity,
    pub(super) revision: u64,
    pub(super) pending_journal: Option<String>,
    pub(super) spent: bool,
    pub(super) journals: BTreeMap<String, PresentationLedger>,
}
impl SharedCheckoutState {
    /// Initial state. The backend must create it only if the key never existed;
    /// replacing a spent/pending record with fresh state is forbidden.
    pub fn fresh(identity: CheckoutCoordinationIdentity) -> Self {
        Self {
            identity,
            revision: 0,
            pending_journal: None,
            spent: false,
            journals: BTreeMap::new(),
        }
    }
    pub fn identity(&self) -> &CheckoutCoordinationIdentity {
        &self.identity
    }
    pub fn revision(&self) -> u64 {
        self.revision
    }
    pub fn spent(&self) -> bool {
        self.spent
    }
    pub fn pending(&self) -> Option<(&str, &CheckoutPresentation)> {
        let journal = self.pending_journal.as_deref()?;
        Some((journal, self.journals.get(journal)?.pending.as_ref()?))
    }
    pub fn journal(&self, journal: &str) -> Option<&PresentationLedger> {
        self.journals.get(journal)
    }
    fn present(
        &self,
        journal: &str,
        presentation: CheckoutPresentation,
    ) -> Result<Self, CoordinationError> {
        if self.spent || self.pending_journal.is_some() || journal.is_empty() || journal.len() > 256
        {
            return Err(CoordinationError::InvalidTransition);
        }
        if presentation.reference.len() > 256 || presentation.merchant_issuer.len() > 256 {
            return Err(CoordinationError::Limit);
        }
        // Tombstones are global to the canonical grouping, not each alias journal.
        if self
            .journals
            .values()
            .any(|j| j.seen.contains(&presentation.reference))
        {
            return Err(CoordinationError::InvalidTransition);
        }
        if self.journals.values().map(|j| j.seen.len()).sum::<usize>() >= 256
            || (!self.journals.contains_key(journal) && self.journals.len() >= 16)
        {
            return Err(CoordinationError::Limit);
        }
        let fresh = PresentationLedger {
            open_mandate_scope: self.identity.storage_key(),
            revision: 0,
            pending: None,
            spent: false,
            seen: Vec::new(),
        };
        let ledger = self.journals.get(journal).unwrap_or(&fresh);
        let proposed = ledger
            .present(OPEN_CHECKOUT_VCT, CLOSED_CHECKOUT_VCT, presentation)
            .ok_or(CoordinationError::InvalidTransition)?;
        let mut next = self.clone();
        next.revision = self
            .revision
            .checked_add(1)
            .ok_or(CoordinationError::Limit)?;
        next.pending_journal = Some(journal.into());
        next.journals.insert(journal.into(), proposed);
        Ok(next)
    }
    fn complete(
        &self,
        journal: &str,
        receipt: &VerifiedCheckoutReceipt,
    ) -> Result<Self, CoordinationError> {
        if self.spent || self.pending_journal.as_deref() != Some(journal) {
            return Err(CoordinationError::InvalidTransition);
        }
        let ledger = self
            .journals
            .get(journal)
            .ok_or(CoordinationError::InvalidTransition)?;
        let proposed = ledger
            .complete(receipt)
            .ok_or(CoordinationError::InvalidTransition)?;
        let mut next = self.clone();
        next.revision = self
            .revision
            .checked_add(1)
            .ok_or(CoordinationError::Limit)?;
        next.pending_journal = None;
        next.spent = proposed.spent;
        next.journals.insert(journal.into(), proposed);
        Ok(next)
    }
}

/// Persistence outcome only. None of these values is a network send capability.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CoordinationCommit {
    /// A fresh whole-record write was durably committed.
    Applied,
    /// Expected snapshot no longer matches; exact retries do not grant a fresh write.
    Conflict,
    /// Durability/ACK is unknown. Reconcile; never infer rejection or resend.
    Unknown,
}

/// Backend must atomically compare the full expected record and replace it with
/// the whole proposed record at identity.storage_key(). It must preserve monotonic
/// revisions and never create/reset authority during this call. Applied is returned
/// only for a fresh durable write; lost ACK returns Unknown. Separate gate/journal
/// writes do not implement this trait's contract. Host authority must be refreshed
/// at the protected persistence boundary before granting any external send.
pub trait SharedCheckoutStore {
    fn compare_exchange(
        &self,
        expected: &SharedCheckoutState,
        proposed: &SharedCheckoutState,
    ) -> CoordinationCommit;
}

/// Compute one whole-record presentation proposal and issue exactly one CAS.
/// Host must independently verify mandate, constraints, reference and current
/// enrollment/policy before using this state transition.
/// # Errors
/// Refuses occupied/spent authority, old references, malformed journals and bounds.
pub fn commit_presentation(
    store: &impl SharedCheckoutStore,
    expected: &SharedCheckoutState,
    journal: &str,
    presentation: CheckoutPresentation,
) -> Result<CoordinationCommit, CoordinationError> {
    let proposed = expected.present(journal, presentation)?;
    Ok(store.compare_exchange(expected, &proposed))
}

/// Complete only the exact pending journal using a verified merchant receipt.
/// Receipt trust must still be current at the protected persistence boundary.
/// # Errors
/// Refuses another journal, stale references, spent authority or revision overflow.
pub fn commit_receipt(
    store: &impl SharedCheckoutStore,
    expected: &SharedCheckoutState,
    journal: &str,
    receipt: &VerifiedCheckoutReceipt,
) -> Result<CoordinationCommit, CoordinationError> {
    let proposed = expected.complete(journal, receipt)?;
    Ok(store.compare_exchange(expected, &proposed))
}

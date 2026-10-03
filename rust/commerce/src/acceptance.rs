//! Pure single-root fence transitions and exact request eligibility.
//! Provider endpoints authenticate and persist fence updates and check eligibility
//! atomically with protected acceptance. These values alone authorize no effect.
use serde::{Deserialize, Serialize};

/// Scope is an independently authenticated namespace for this root incarnation.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct AuthorizationRoot {
    pub budget_scope: String,
    pub mandate_id: String,
}

/// Monotonic provider-local authority; retirement is permanent for this root.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct RootFence {
    pub root: AuthorizationRoot,
    pub generation: u64,
    pub retired: bool,
}

/// Claim-time snapshot bound to one provider, operation and exact request body.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct AcceptanceTicket {
    pub root: AuthorizationRoot,
    pub generation: u64,
    pub provider_id: String,
    pub operation_id: String,
    pub request_commitment: String,
}
impl RootFence {
    /// Apply a strictly newer authenticated update; roots never share a counter.
    #[must_use]
    pub fn advance(&self, next: &Self) -> Option<Self> {
        (next.root == self.root
            && next.generation > self.generation
            && (!self.retired || next.retired))
            .then(|| next.clone())
    }

    /// Check inside the provider's serialized acceptance transaction. Existing
    /// accepted requests may be queried after retirement without a new acceptance.
    #[must_use]
    pub fn accepts(
        &self,
        ticket: &AcceptanceTicket,
        provider: &str,
        operation: &str,
        commitment: &str,
    ) -> bool {
        !self.retired
            && ticket.root == self.root
            && ticket.generation == self.generation
            && !self.root.budget_scope.is_empty()
            && !self.root.mandate_id.is_empty()
            && !provider.is_empty()
            && !operation.is_empty()
            && !commitment.is_empty()
            && ticket.provider_id == provider
            && ticket.operation_id == operation
            && ticket.request_commitment == commitment
    }
}

//! Process-local admission reference for signed agent-commerce claims.
//!
//! Every call re-verifies signatures and checkout bytes against the Host's
//! current keys before checking time, epoch, revocation, scope, and policy.
//! The deploying Host must authenticate registry updates and its clock, use a
//! real policy evaluator, and recheck these facts when reserving or effecting
//! a purchase. This process-local reference is not a durable authority store.

use crate::lean_mandate_offer_projection::{
    LeanMandateClaims, LeanOfferClaims, mandate_claims, mandate_matches, offer_claims,
    offer_matches,
};
use crate::mandate_offer_signatures::{
    MandateId, MandateOfferTrust, MandatePayload, MerchantId, OfferId, OfferPayload, PrincipalId,
    VerifiedMandate, VerifiedOffer,
};
use p256::ecdsa::VerifyingKey;
use std::collections::{HashMap, HashSet};

/// A failed check in the process-local admission sequence.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum AdmissionError {
    InactivePrincipalKey,
    InactiveMerchantKey,
    MandateVerification(String),
    OfferVerification(String),
    MissingPolicyEpoch,
    StalePolicyEpoch,
    PolicyEpochRollback,
    RevokedMandate,
    RevokedOffer,
    ExpiredMandate,
    ExpiredOffer,
    MandateClaimsMismatch,
    OfferClaimsMismatch,
    OutsideMandateScope,
    PolicyDenied,
}

/// Fresh claims for the Host to project into Lean with `verified = true`.
/// A later reservation or external effect needs a fresh state check.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AdmittedClaims {
    mandate: LeanMandateClaims,
    offer: LeanOfferClaims,
}

impl AdmittedClaims {
    pub fn mandate(&self) -> &LeanMandateClaims {
        &self.mandate
    }

    pub fn offer(&self) -> &LeanOfferClaims {
        &self.offer
    }
}

/// Exact signed input and Lean claims for one root mandate and merchant offer.
/// The deploying Host must obtain `now` from its own clock.
pub struct AdmissionRequest<'a> {
    pub mandate: MandatePayload,
    pub mandate_signature: &'a [u8],
    pub offer: OfferPayload,
    pub checkout_bytes: &'a [u8],
    pub offer_signature: &'a [u8],
    pub lean_mandate: &'a LeanMandateClaims,
    pub lean_offer: &'a LeanOfferClaims,
    pub now: u64,
}

/// Host-controlled, process-local admission state. The key sets track current
/// active status; re-enrollment rotates a key and old signatures fail on use.
#[derive(Default)]
pub struct AgentCommerceAdmissionHost {
    trust: MandateOfferTrust,
    active_principals: HashSet<PrincipalId>,
    active_merchants: HashSet<MerchantId>,
    policy_epochs: HashMap<PrincipalId, u64>,
    revoked_mandates: HashSet<(PrincipalId, MandateId)>,
    revoked_offers: HashSet<(MerchantId, OfferId)>,
}

impl AgentCommerceAdmissionHost {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn enroll_principal_key(&mut self, principal: PrincipalId, key: VerifyingKey) {
        self.trust.trust_principal(principal.clone(), key);
        self.active_principals.insert(principal);
    }

    pub fn enroll_merchant_key(&mut self, merchant: MerchantId, key: VerifyingKey) {
        self.trust.trust_merchant(merchant.clone(), key);
        self.active_merchants.insert(merchant);
    }

    pub fn deactivate_principal_key(&mut self, principal: &PrincipalId) {
        self.active_principals.remove(principal);
    }

    pub fn deactivate_merchant_key(&mut self, merchant: &MerchantId) {
        self.active_merchants.remove(merchant);
    }

    /// The current epoch is exact. Lower values cannot reopen old authority.
    pub fn set_policy_epoch(
        &mut self,
        principal: PrincipalId,
        epoch: u64,
    ) -> Result<(), AdmissionError> {
        if self
            .policy_epochs
            .get(&principal)
            .is_some_and(|current| epoch < *current)
        {
            return Err(AdmissionError::PolicyEpochRollback);
        }
        self.policy_epochs.insert(principal, epoch);
        Ok(())
    }

    pub fn revoke_mandate(&mut self, principal: PrincipalId, mandate: MandateId) {
        self.revoked_mandates.insert((principal, mandate));
    }

    pub fn revoke_offer(&mut self, merchant: MerchantId, offer: OfferId) {
        self.revoked_offers.insert((merchant, offer));
    }

    /// Re-verify signed root evidence and current Host state before projecting
    /// claims. `policy_allows` must evaluate current policy over these claims.
    pub fn admit<F>(
        &self,
        request: AdmissionRequest<'_>,
        policy_allows: F,
    ) -> Result<AdmittedClaims, AdmissionError>
    where
        F: FnOnce(&LeanMandateClaims, &LeanOfferClaims) -> bool,
    {
        let (verified_mandate, verified_offer) = self.verify_signatures(&request)?;
        self.check_current_state(&verified_mandate, &verified_offer, request.now)?;
        Self::check_claims_and_scope(&verified_mandate, &verified_offer, &request)?;
        if !policy_allows(request.lean_mandate, request.lean_offer) {
            return Err(AdmissionError::PolicyDenied);
        }
        Ok(AdmittedClaims {
            mandate: mandate_claims(&verified_mandate),
            offer: offer_claims(&verified_offer),
        })
    }

    fn verify_signatures(
        &self,
        request: &AdmissionRequest<'_>,
    ) -> Result<(VerifiedMandate, VerifiedOffer), AdmissionError> {
        if !self.active_principals.contains(&request.mandate.principal) {
            return Err(AdmissionError::InactivePrincipalKey);
        }
        if !self.active_merchants.contains(&request.offer.merchant_id) {
            return Err(AdmissionError::InactiveMerchantKey);
        }
        let verified_mandate = self
            .trust
            .verify_mandate(request.mandate.clone(), request.mandate_signature)
            .map_err(AdmissionError::MandateVerification)?;
        let verified_offer = self
            .trust
            .verify_offer(
                request.offer.clone(),
                request.checkout_bytes,
                request.offer_signature,
            )
            .map_err(AdmissionError::OfferVerification)?;
        Ok((verified_mandate, verified_offer))
    }

    fn check_current_state(
        &self,
        verified_mandate: &VerifiedMandate,
        verified_offer: &VerifiedOffer,
        now: u64,
    ) -> Result<(), AdmissionError> {
        let mandate = verified_mandate.payload();
        let offer = verified_offer.payload();
        match self.policy_epochs.get(&mandate.principal) {
            None => return Err(AdmissionError::MissingPolicyEpoch),
            Some(epoch) if *epoch != mandate.policy_epoch => {
                return Err(AdmissionError::StalePolicyEpoch);
            }
            Some(_) => {}
        }
        if self
            .revoked_mandates
            .contains(&(mandate.principal.clone(), mandate.mandate_id.clone()))
        {
            return Err(AdmissionError::RevokedMandate);
        }
        if self
            .revoked_offers
            .contains(&(offer.merchant_id.clone(), offer.offer_id.clone()))
        {
            return Err(AdmissionError::RevokedOffer);
        }
        if now >= mandate.expires_at {
            return Err(AdmissionError::ExpiredMandate);
        }
        if now >= offer.expires_at {
            return Err(AdmissionError::ExpiredOffer);
        }
        Ok(())
    }

    fn check_claims_and_scope(
        verified_mandate: &VerifiedMandate,
        verified_offer: &VerifiedOffer,
        request: &AdmissionRequest<'_>,
    ) -> Result<(), AdmissionError> {
        let mandate = verified_mandate.payload();
        let offer = verified_offer.payload();
        if !mandate_matches(verified_mandate, request.lean_mandate) {
            return Err(AdmissionError::MandateClaimsMismatch);
        }
        if !offer_matches(verified_offer, request.lean_offer) {
            return Err(AdmissionError::OfferClaimsMismatch);
        }
        if !mandate.allowed_merchants.contains(&offer.merchant_id)
            || !mandate.allowed_products.contains(&offer.product_id)
            || mandate.asset != offer.asset
            || offer.amount_minor > mandate.per_purchase_cap
        {
            return Err(AdmissionError::OutsideMandateScope);
        }
        Ok(())
    }
}

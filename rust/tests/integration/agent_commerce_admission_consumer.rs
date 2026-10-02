use cedar_poo_bridge::agent_commerce_admission::{
    AdmissionError, AdmissionRequest, AgentCommerceAdmissionHost,
};
use cedar_poo_bridge::lean_mandate_offer_projection::{
    LeanMandateClaims, LeanOfferClaims, mandate_claims, offer_claims,
};
use cedar_poo_bridge::mandate_offer_signatures::{
    MandateOfferTrust, MandatePayload, OfferPayload, PrincipalId, sha256_hex,
};
use p256::ecdsa::{Signature, SigningKey, signature::Signer};

fn signer(seed: u8) -> SigningKey {
    SigningKey::from_bytes((&[seed; 32]).into()).expect("test key")
}

fn key_hex(key: &SigningKey) -> String {
    key.verifying_key()
        .to_encoded_point(true)
        .as_bytes()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

struct Fixture {
    principal_key: SigningKey,
    merchant_key: SigningKey,
    mandate: MandatePayload,
    offer: OfferPayload,
    checkout: Vec<u8>,
}

impl Fixture {
    fn new() -> Self {
        let principal_key = signer(1);
        let agent_key = signer(2);
        let merchant_key = signer(3);
        let checkout = br#"{"ride":"airport","total_minor":30000}"#.to_vec();
        Self {
            principal_key,
            merchant_key,
            mandate: MandatePayload {
                mandate_id: "trip-root".into(),
                principal: PrincipalId {
                    entity_type_id: "Account".into(),
                    entity_type_path: vec!["finance".into()],
                    entity_id: "buyer".into(),
                },
                agent_id: "travel-agent".into(),
                agent_public_key: key_hex(&agent_key).into(),
                allowed_merchants: vec!["ride-seller".into()],
                allowed_products: vec!["airport-ride".into()],
                asset: "HKD".into(),
                per_purchase_cap: 50_000,
                total_cap: 80_000,
                policy_epoch: 4,
                expires_at: 30,
            },
            offer: OfferPayload {
                merchant_id: "ride-seller".into(),
                product_id: "airport-ride".into(),
                offer_id: "quote-42".into(),
                checkout_sha256: sha256_hex(&checkout),
                amount_minor: 30_000,
                asset: "HKD".into(),
                expires_at: 20,
            },
            checkout,
        }
    }

    fn trust(&self) -> MandateOfferTrust {
        let mut trust = MandateOfferTrust::new();
        trust.trust_principal(
            self.mandate.principal.clone(),
            *self.principal_key.verifying_key(),
        );
        trust.trust_merchant(
            self.offer.merchant_id.clone(),
            *self.merchant_key.verifying_key(),
        );
        trust
    }

    fn host(&self) -> AgentCommerceAdmissionHost {
        let mut host = AgentCommerceAdmissionHost::new();
        host.enroll_principal_key(
            self.mandate.principal.clone(),
            *self.principal_key.verifying_key(),
        );
        host.enroll_merchant_key(
            self.offer.merchant_id.clone(),
            *self.merchant_key.verifying_key(),
        );
        host.set_policy_epoch(self.mandate.principal.clone(), 4)
            .unwrap();
        host
    }

    fn claims(&self) -> (LeanMandateClaims, LeanOfferClaims) {
        let trust = self.trust();
        let mandate_signature: Signature = self.principal_key.sign(&self.mandate.signing_bytes());
        let offer_signature: Signature = self.merchant_key.sign(&self.offer.signing_bytes());
        let mandate = trust
            .verify_mandate(
                self.mandate.clone(),
                mandate_signature.to_bytes().as_slice(),
            )
            .unwrap();
        let offer = trust
            .verify_offer(
                self.offer.clone(),
                &self.checkout,
                offer_signature.to_bytes().as_slice(),
            )
            .unwrap();
        (mandate_claims(&mandate), offer_claims(&offer))
    }

    fn admit(
        &self,
        host: &AgentCommerceAdmissionHost,
        claims: (&LeanMandateClaims, &LeanOfferClaims),
        now: u64,
        policy_allows: bool,
    ) -> Result<cedar_poo_bridge::agent_commerce_admission::AdmittedClaims, AdmissionError> {
        let mandate_signature: Signature = self.principal_key.sign(&self.mandate.signing_bytes());
        let offer_signature: Signature = self.merchant_key.sign(&self.offer.signing_bytes());
        host.admit(
            AdmissionRequest {
                mandate: self.mandate.clone(),
                mandate_signature: mandate_signature.to_bytes().as_slice(),
                offer: self.offer.clone(),
                checkout_bytes: &self.checkout,
                offer_signature: offer_signature.to_bytes().as_slice(),
                lean_mandate: claims.0,
                lean_offer: claims.1,
                now,
            },
            |_, _| policy_allows,
        )
    }
}

#[test]
fn fresh_signed_claims_admit_and_policy_denial_blocks() {
    let fixture = Fixture::new();
    let host = fixture.host();
    let (mandate, offer) = fixture.claims();
    let admitted = fixture.admit(&host, (&mandate, &offer), 10, true).unwrap();
    assert_eq!(admitted.mandate(), &mandate);
    assert_eq!(admitted.offer(), &offer);
    assert_eq!(
        fixture.admit(&host, (&mandate, &offer), 10, false),
        Err(AdmissionError::PolicyDenied)
    );
    let mut changed = mandate.clone();
    changed.agent_id = "other-agent".into();
    assert_eq!(
        fixture.admit(&host, (&changed, &offer), 10, true),
        Err(AdmissionError::MandateClaimsMismatch)
    );
    let mut changed_offer = offer.clone();
    changed_offer.terms.amount_minor += 1;
    assert_eq!(
        fixture.admit(&host, (&mandate, &changed_offer), 10, true),
        Err(AdmissionError::OfferClaimsMismatch)
    );
}

#[test]
fn expiry_and_current_epoch_are_rechecked_at_admission() {
    let fixture = Fixture::new();
    let mut host = fixture.host();
    let (mandate, offer) = fixture.claims();
    assert_eq!(
        fixture.admit(&host, (&mandate, &offer), 20, true),
        Err(AdmissionError::ExpiredOffer)
    );
    assert_eq!(
        fixture.admit(&host, (&mandate, &offer), 30, true),
        Err(AdmissionError::ExpiredMandate)
    );
    host.set_policy_epoch(fixture.mandate.principal.clone(), 5)
        .unwrap();
    assert_eq!(
        fixture.admit(&host, (&mandate, &offer), 10, true),
        Err(AdmissionError::StalePolicyEpoch)
    );
    assert_eq!(
        host.set_policy_epoch(fixture.mandate.principal.clone(), 4),
        Err(AdmissionError::PolicyEpochRollback)
    );
    let mut missing_epoch = AgentCommerceAdmissionHost::new();
    missing_epoch.enroll_principal_key(
        fixture.mandate.principal.clone(),
        *fixture.principal_key.verifying_key(),
    );
    missing_epoch.enroll_merchant_key(
        fixture.offer.merchant_id.clone(),
        *fixture.merchant_key.verifying_key(),
    );
    assert_eq!(
        fixture.admit(&missing_epoch, (&mandate, &offer), 10, true),
        Err(AdmissionError::MissingPolicyEpoch)
    );
}

#[test]
fn key_rotation_and_revocation_invalidate_old_signed_evidence() {
    let fixture = Fixture::new();
    let (mandate, offer) = fixture.claims();
    let mut host = fixture.host();
    assert!(fixture.admit(&host, (&mandate, &offer), 10, true).is_ok());
    host.deactivate_principal_key(&fixture.mandate.principal);
    assert_eq!(
        fixture.admit(&host, (&mandate, &offer), 10, true),
        Err(AdmissionError::InactivePrincipalKey)
    );
    host.enroll_principal_key(
        fixture.mandate.principal.clone(),
        *signer(4).verifying_key(),
    );
    assert!(matches!(
        fixture.admit(&host, (&mandate, &offer), 10, true),
        Err(AdmissionError::MandateVerification(_))
    ));
    host.enroll_principal_key(
        fixture.mandate.principal.clone(),
        *fixture.principal_key.verifying_key(),
    );
    host.deactivate_merchant_key(&fixture.offer.merchant_id);
    assert_eq!(
        fixture.admit(&host, (&mandate, &offer), 10, true),
        Err(AdmissionError::InactiveMerchantKey)
    );
    host.enroll_merchant_key(
        fixture.offer.merchant_id.clone(),
        *signer(5).verifying_key(),
    );
    assert!(matches!(
        fixture.admit(&host, (&mandate, &offer), 10, true),
        Err(AdmissionError::OfferVerification(_))
    ));
    host.enroll_merchant_key(
        fixture.offer.merchant_id.clone(),
        *fixture.merchant_key.verifying_key(),
    );
    host.revoke_mandate(
        fixture.mandate.principal.clone(),
        fixture.mandate.mandate_id.clone(),
    );
    assert_eq!(
        fixture.admit(&host, (&mandate, &offer), 10, true),
        Err(AdmissionError::RevokedMandate)
    );
    let mut other = fixture.host();
    other.revoke_offer(
        fixture.offer.merchant_id.clone(),
        fixture.offer.offer_id.clone(),
    );
    assert_eq!(
        fixture.admit(&other, (&mandate, &offer), 10, true),
        Err(AdmissionError::RevokedOffer)
    );
}

#[test]
fn verified_offer_outside_mandate_scope_still_denied() {
    let mut fixture = Fixture::new();
    fixture.offer.amount_minor = 50_001;
    let (mandate, offer) = fixture.claims();
    let host = fixture.host();
    assert_eq!(
        fixture.admit(&host, (&mandate, &offer), 10, true),
        Err(AdmissionError::OutsideMandateScope)
    );
}

#[test]
fn changed_checkout_fails_before_policy_evaluation() {
    let fixture = Fixture::new();
    let (mandate, offer) = fixture.claims();
    let host = fixture.host();
    let mandate_signature: Signature = fixture.principal_key.sign(&fixture.mandate.signing_bytes());
    let offer_signature: Signature = fixture.merchant_key.sign(&fixture.offer.signing_bytes());
    let mut policy_called = false;
    let result = host.admit(
        AdmissionRequest {
            mandate: fixture.mandate.clone(),
            mandate_signature: mandate_signature.to_bytes().as_slice(),
            offer: fixture.offer.clone(),
            checkout_bytes: b"changed checkout bytes",
            offer_signature: offer_signature.to_bytes().as_slice(),
            lean_mandate: &mandate,
            lean_offer: &offer,
            now: 10,
        },
        |_, _| {
            policy_called = true;
            true
        },
    );
    assert!(matches!(result, Err(AdmissionError::OfferVerification(_))));
    assert!(!policy_called);
}

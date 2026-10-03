use super::{
    MandateOfferTrust, MandatePayload, OfferPayload, PrincipalId, delegation_signing_bytes,
    hex_lower, sha256_hex,
};
use p256::ecdsa::{Signature, SigningKey, signature::Signer};

fn signer(seed: u8) -> SigningKey {
    SigningKey::from_bytes((&[seed; 32]).into()).expect("test private key")
}

fn mandate() -> MandatePayload {
    let agent = signer(5);
    MandatePayload {
        mandate_id: "trip-2026".into(),
        principal: PrincipalId {
            entity_type_id: "Account".into(),
            entity_type_path: vec![],
            entity_id: "approved".into(),
        },
        agent_id: "travel-agent-7".into(),
        agent_public_key: hex_lower(agent.verifying_key().to_encoded_point(true).as_bytes()).into(),
        allowed_merchants: vec!["ride-provider".into()],
        allowed_products: vec!["airport-ride".into()],
        asset: "HKD".into(),
        per_purchase_cap: 50_000,
        total_cap: 80_000,
        policy_epoch: 4,
        expires_at: 30,
    }
}

fn offer(checkout: &[u8]) -> OfferPayload {
    OfferPayload {
        merchant_id: "ride-provider".into(),
        product_id: "airport-ride".into(),
        offer_id: "quote-42".into(),
        checkout_sha256: sha256_hex(checkout),
        amount_minor: 30_000,
        asset: "HKD".into(),
        expires_at: 20,
    }
}

#[test]
fn exact_mandate_and_offer_are_authenticated() {
    let principal = signer(1);
    let merchant = signer(2);
    let mut trust = MandateOfferTrust::new();
    trust.trust_principal(mandate().principal, *principal.verifying_key());
    trust.trust_merchant("ride-provider".into(), *merchant.verifying_key());
    let mandate = mandate();
    let mandate_signature: Signature = principal.sign(&mandate.signing_bytes());
    let checkout = br#"{"ride":"airport","total_minor":30000}"#;
    let offer = offer(checkout);
    let offer_signature: Signature = merchant.sign(&offer.signing_bytes());
    assert_eq!(
        trust
            .verify_mandate(mandate.clone(), mandate_signature.to_bytes().as_slice())
            .unwrap()
            .payload(),
        &mandate
    );
    assert_eq!(
        trust
            .verify_offer(
                offer.clone(),
                checkout,
                offer_signature.to_bytes().as_slice()
            )
            .unwrap()
            .payload(),
        &offer
    );
    assert!(
        trust
            .verify_offer(
                offer.clone(),
                br#"{"ride":"other","total_minor":30000}"#,
                offer_signature.to_bytes().as_slice()
            )
            .is_err()
    );
    assert!(
        trust
            .verify_offer(
                OfferPayload {
                    amount_minor: 30_001,
                    ..offer
                },
                checkout,
                offer_signature.to_bytes().as_slice()
            )
            .is_err()
    );
    assert!(
        trust
            .verify_mandate(
                MandatePayload {
                    agent_id: "other-agent".into(),
                    ..mandate.clone()
                },
                mandate_signature.to_bytes().as_slice()
            )
            .is_err()
    );
    assert!(
        trust
            .verify_mandate(
                MandatePayload {
                    principal: PrincipalId {
                        entity_id: "reserve".into(),
                        ..mandate.principal
                    },
                    ..mandate
                },
                mandate_signature.to_bytes().as_slice()
            )
            .is_err()
    );
}

#[test]
fn issuer_role_and_domain_are_bound() {
    let principal = signer(3);
    let merchant = signer(4);
    let mut trust = MandateOfferTrust::new();
    trust.trust_principal(mandate().principal, *principal.verifying_key());
    trust.trust_merchant("ride-provider".into(), *merchant.verifying_key());
    let mandate = mandate();
    let checkout = b"exact checkout";
    let offer = offer(checkout);
    let wrong_mandate_signature: Signature = merchant.sign(&mandate.signing_bytes());
    let wrong_offer_signature: Signature = principal.sign(&offer.signing_bytes());
    assert!(
        trust
            .verify_mandate(mandate, wrong_mandate_signature.to_bytes().as_slice())
            .is_err()
    );
    assert!(
        trust
            .verify_offer(offer, checkout, wrong_offer_signature.to_bytes().as_slice())
            .is_err()
    );
}

#[test]
fn child_delegation_is_signed_and_attenuated() {
    let principal = signer(1);
    let parent_agent = signer(5);
    let child_agent = signer(6);
    let mut trust = MandateOfferTrust::new();
    trust.trust_principal(mandate().principal, *principal.verifying_key());
    let parent = mandate();
    let parent_signature: Signature = principal.sign(&parent.signing_bytes());
    let verified_parent = trust
        .verify_mandate(parent.clone(), parent_signature.to_bytes().as_slice())
        .unwrap();
    let child = MandatePayload {
        mandate_id: "trip-child".into(),
        agent_id: "booking-agent-8".into(),
        agent_public_key: hex_lower(
            child_agent
                .verifying_key()
                .to_encoded_point(true)
                .as_bytes(),
        )
        .into(),
        per_purchase_cap: 40_000,
        total_cap: 60_000,
        expires_at: 25,
        ..parent.clone()
    };
    let signature: Signature = parent_agent.sign(&delegation_signing_bytes(&parent, &child));
    let verified_child = trust
        .verify_delegation(
            &verified_parent,
            child.clone(),
            signature.to_bytes().as_slice(),
        )
        .unwrap();
    assert_eq!(verified_child.payload(), &child);

    let grandchild_agent = signer(7);
    let grandchild = MandatePayload {
        mandate_id: "trip-grandchild".into(),
        agent_id: "quote-agent-9".into(),
        agent_public_key: hex_lower(
            grandchild_agent
                .verifying_key()
                .to_encoded_point(true)
                .as_bytes(),
        )
        .into(),
        per_purchase_cap: 35_000,
        total_cap: 50_000,
        expires_at: 22,
        ..child.clone()
    };
    let grandchild_signature: Signature =
        child_agent.sign(&delegation_signing_bytes(&child, &grandchild));
    assert!(
        trust
            .verify_delegation(
                &verified_child,
                grandchild.clone(),
                grandchild_signature.to_bytes().as_slice()
            )
            .is_ok()
    );
    for reused in [
        MandatePayload {
            mandate_id: parent.mandate_id.clone(),
            ..grandchild.clone()
        },
        MandatePayload {
            agent_id: parent.agent_id.clone(),
            ..grandchild.clone()
        },
        MandatePayload {
            agent_public_key: parent.agent_public_key.clone(),
            ..grandchild.clone()
        },
    ] {
        let reused_signature: Signature =
            child_agent.sign(&delegation_signing_bytes(&child, &reused));
        assert!(
            trust
                .verify_delegation(
                    &verified_child,
                    reused,
                    reused_signature.to_bytes().as_slice()
                )
                .is_err()
        );
    }
    let widened = MandatePayload {
        allowed_merchants: vec!["ride-provider".into(), "other".into()],
        ..child.clone()
    };
    let widened_signature: Signature =
        parent_agent.sign(&delegation_signing_bytes(&parent, &widened));
    assert!(
        trust
            .verify_delegation(
                &verified_parent,
                widened,
                widened_signature.to_bytes().as_slice()
            )
            .is_err()
    );
    let wrong_signer: Signature = child_agent.sign(&delegation_signing_bytes(&parent, &child));
    assert!(
        trust
            .verify_delegation(&verified_parent, child, wrong_signer.to_bytes().as_slice())
            .is_err()
    );
}

use cedar_poo_bridge::mandate_offer_signatures::{
    MandateOfferTrust, MandatePayload, OfferPayload, PrincipalId, delegation_signing_bytes,
    sha256_hex,
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

#[test]
fn downstream_consumer_uses_feature_gated_public_api() {
    let principal_key = signer(1);
    let parent_key = signer(2);
    let child_key = signer(3);
    let merchant_key = signer(4);
    let principal = PrincipalId {
        entity_type_id: "Account".into(),
        entity_type_path: vec!["finance".into()],
        entity_id: "buyer".into(),
    };
    let root = MandatePayload {
        mandate_id: "trip-root".into(),
        principal: principal.clone(),
        agent_id: "travel-agent".into(),
        agent_public_key: key_hex(&parent_key).into(),
        allowed_merchants: vec!["ride-seller".into()],
        allowed_products: vec!["airport-ride".into()],
        asset: "HKD".into(),
        per_purchase_cap: 50_000,
        total_cap: 80_000,
        policy_epoch: 4,
        expires_at: 30,
    };
    let root_signature: Signature = principal_key.sign(&root.signing_bytes());
    let mut trust = MandateOfferTrust::new();
    trust.trust_principal(principal, *principal_key.verifying_key());
    trust.trust_merchant("ride-seller".into(), *merchant_key.verifying_key());
    let verified_root = trust
        .verify_mandate(root.clone(), root_signature.to_bytes().as_slice())
        .expect("signed root");

    let child = MandatePayload {
        mandate_id: "trip-child".into(),
        agent_id: "booking-agent".into(),
        agent_public_key: key_hex(&child_key).into(),
        per_purchase_cap: 40_000,
        total_cap: 60_000,
        expires_at: 25,
        ..root
    };
    let child_signature: Signature =
        parent_key.sign(&delegation_signing_bytes(verified_root.payload(), &child));
    let verified_child = trust
        .verify_delegation(&verified_root, child, child_signature.to_bytes().as_slice())
        .expect("signed child");
    assert_eq!(verified_child.payload().agent_id.as_str(), "booking-agent");

    let checkout = br#"{"ride":"airport","total_minor":30000}"#;
    let offer = OfferPayload {
        merchant_id: "ride-seller".into(),
        product_id: "airport-ride".into(),
        offer_id: "quote-42".into(),
        checkout_sha256: sha256_hex(checkout),
        amount_minor: 30_000,
        asset: "HKD".into(),
        expires_at: 20,
    };
    let offer_signature: Signature = merchant_key.sign(&offer.signing_bytes());
    assert!(
        trust
            .verify_offer(offer, checkout, offer_signature.to_bytes().as_slice())
            .is_ok()
    );
}

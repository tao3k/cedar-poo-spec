use cedar_poo_commerce::projection::{
    LeanMandateClaims, LeanOfferClaims, mandate_claims, mandate_matches, offer_claims,
    offer_matches,
};
use cedar_poo_commerce::signatures::{
    MandateOfferTrust, MandatePayload, OfferPayload, PrincipalId, delegation_signing_bytes,
    sha256_hex,
};
use p256::ecdsa::{Signature, SigningKey, signature::Signer};
use serde_json::{Value, json};
use std::fs;

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

fn verified_evidence() -> (
    cedar_poo_commerce::signatures::VerifiedMandate,
    cedar_poo_commerce::signatures::VerifiedOffer,
) {
    let principal_key = signer(1);
    let agent_key = signer(2);
    let merchant_key = signer(3);
    let principal = PrincipalId {
        entity_type_id: "Account".into(),
        entity_type_path: vec!["finance".into()],
        entity_id: "buyer".into(),
    };
    let mandate = MandatePayload {
        mandate_id: "trip-root".into(),
        principal: principal.clone(),
        agent_id: "travel-agent".into(),
        agent_public_key: key_hex(&agent_key).into(),
        allowed_merchants: vec!["ride-seller".into()],
        allowed_products: vec!["airport-ride".into()],
        asset: "HKD".into(),
        per_purchase_cap: 50_000,
        total_cap: 80_000,
        policy_epoch: 4,
        expires_at: 30,
    };
    let mandate_signature: Signature = principal_key.sign(&mandate.signing_bytes());
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
    let mut trust = MandateOfferTrust::new();
    trust.trust_principal(principal, *principal_key.verifying_key());
    trust.trust_merchant("ride-seller".into(), *merchant_key.verifying_key());
    (
        trust
            .verify_mandate(mandate, mandate_signature.to_bytes().as_slice())
            .expect("principal signature"),
        trust
            .verify_offer(offer, checkout, offer_signature.to_bytes().as_slice())
            .expect("merchant signature and checkout bytes"),
    )
}

fn changed_at(original: &Value, pointer: &str, replacement: Value) -> Value {
    let mut changed = original.clone();
    *changed.pointer_mut(pointer).expect("known projected field") = replacement;
    changed
}

#[test]
fn lean_claims_match_live_verified_rust_evidence() {
    let fixture_path = std::env::var("LEAN_PROJECTION_FIXTURE")
        .expect("run with a Lean-generated fixture from check-projection");
    let fixture: Value = serde_json::from_slice(&fs::read(fixture_path).unwrap()).unwrap();
    let (mandate, offer) = verified_evidence();
    let mandate_claims: LeanMandateClaims =
        serde_json::from_value(fixture["mandate"].clone()).unwrap();
    let offer_claims: LeanOfferClaims = serde_json::from_value(fixture["offer"].clone()).unwrap();
    assert!(mandate_matches(&mandate, &mandate_claims));
    assert!(offer_matches(&offer, &offer_claims));
    assert_eq!(
        serde_json::to_value(mandate_claims).unwrap(),
        fixture["mandate"]
    );
    assert_eq!(
        serde_json::to_value(offer_claims).unwrap(),
        fixture["offer"]
    );

    let child_agent_key = signer(4);
    let child = MandatePayload {
        mandate_id: "trip-child".into(),
        agent_id: "booking-agent".into(),
        agent_public_key: key_hex(&child_agent_key).into(),
        per_purchase_cap: 40_000,
        total_cap: 60_000,
        expires_at: 25,
        ..mandate.payload().clone()
    };
    let parent_agent_key = signer(2);
    let child_signature: Signature =
        parent_agent_key.sign(&delegation_signing_bytes(mandate.payload(), &child));
    let verified_child = MandateOfferTrust::new()
        .verify_delegation(&mandate, child, child_signature.to_bytes().as_slice())
        .unwrap();
    let child_claims: LeanMandateClaims =
        serde_json::from_value(fixture["lineage"][1].clone()).unwrap();
    assert_eq!(fixture["lineage"][0], fixture["mandate"]);
    assert!(mandate_matches(&verified_child, &child_claims));
}

#[test]
fn all_mandate_fields_are_checked_before_lean_verified_flag() {
    let (mandate, _) = verified_evidence();
    let projected = mandate_claims(&mandate);
    assert!(mandate_matches(&mandate, &projected));
    let json = serde_json::to_value(&projected).unwrap();
    assert_eq!(json["principal"]["ty"]["path"], json!(["finance"]));
    for (pointer, replacement) in [
        ("/mandateId", json!("other")),
        ("/principal/ty/id", json!("OtherType")),
        ("/principal/ty/path/0", json!("other")),
        ("/principal/eid", json!("other-buyer")),
        ("/agentId", json!("other-agent")),
        ("/agentPublicKey", json!("other-key")),
        ("/allowedMerchants/0", json!("other-merchant")),
        ("/allowedProducts/0", json!("other-product")),
        ("/asset", json!("USD")),
        ("/perPurchaseCap", json!(50_001)),
        ("/totalCap", json!(80_001)),
        ("/policyEpoch", json!(5)),
        ("/expiresAt", json!(31)),
    ] {
        let changed: LeanMandateClaims =
            serde_json::from_value(changed_at(&json, pointer, replacement)).unwrap();
        assert!(!mandate_matches(&mandate, &changed), "{pointer}");
    }
    let encoded = json.to_string();
    assert!(encoded.contains("\"totalCap\":80000"));
    let oversized = encoded.replace("\"totalCap\":80000", "\"totalCap\":18446744073709551616");
    assert!(serde_json::from_str::<LeanMandateClaims>(&oversized).is_err());
    let mut with_flag = json;
    with_flag["verified"] = json!(true);
    assert!(serde_json::from_value::<LeanMandateClaims>(with_flag).is_err());
}

#[test]
fn all_offer_fields_and_checkout_commitment_are_checked() {
    let (_, offer) = verified_evidence();
    let projected = offer_claims(&offer);
    assert!(offer_matches(&offer, &projected));
    let json = serde_json::to_value(&projected).unwrap();
    for (pointer, replacement) in [
        ("/terms/merchantId", json!("other-merchant")),
        ("/terms/productId", json!("other-product")),
        ("/terms/offerId", json!("other-offer")),
        ("/terms/checkoutCommitment", json!("other-digest")),
        ("/terms/amountMinor", json!(30_001)),
        ("/terms/asset", json!("USD")),
        ("/expiresAt", json!(21)),
    ] {
        let changed: LeanOfferClaims =
            serde_json::from_value(changed_at(&json, pointer, replacement)).unwrap();
        assert!(!offer_matches(&offer, &changed), "{pointer}");
    }
    let mut with_flag = json;
    with_flag["verified"] = json!(true);
    assert!(serde_json::from_value::<LeanOfferClaims>(with_flag).is_err());
}

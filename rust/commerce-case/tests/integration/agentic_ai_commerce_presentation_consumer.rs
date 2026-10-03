use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use cedar_poo_commerce::presentation::{
    AP2_SOURCE_REVISION, CLOSED_CHECKOUT_VCT, CheckoutPresentation, CheckoutReceiptTrust,
    OPEN_CHECKOUT_VCT, PresentationLedger,
};
use p256::ecdsa::{Signature, SigningKey, signature::Signer};
use serde_json::{Value, json};

fn key(seed: u8) -> SigningKey {
    SigningKey::from_bytes((&[seed; 32]).into()).unwrap()
}
fn trust() -> CheckoutReceiptTrust {
    let mut trust = CheckoutReceiptTrust::default();
    trust.enroll("merchant".into(), "key-7".into(), *key(7).verifying_key());
    trust
        .allow_rejection("merchant", "checkout_unavailable".into())
        .unwrap();
    trust
}
fn sign_raw(header: &str, payload: &str, seed: u8) -> String {
    let signing = format!(
        "{}.{}",
        URL_SAFE_NO_PAD.encode(header),
        URL_SAFE_NO_PAD.encode(payload)
    );
    let signature: Signature = key(seed).sign(signing.as_bytes());
    format!(
        "{}.{}",
        signing,
        URL_SAFE_NO_PAD.encode(signature.to_bytes())
    )
}
fn jwt(payload: &Value) -> String {
    sign_raw(
        r#"{"alg":"ES256","typ":"JWT","kid":"key-7"}"#,
        &payload.to_string(),
        7,
    )
}
fn state(name: &str) -> PresentationLedger {
    let fixture: Value = serde_json::from_slice(include_bytes!(
        "../../../../Tests/Conformance/commerce-presentation-v1.json"
    ))
    .unwrap();
    assert_eq!(fixture["ap2Revision"], AP2_SOURCE_REVISION);
    serde_json::from_value(fixture[name].clone()).unwrap()
}
fn rejection() -> Value {
    json!({"status":"Error", "iss":"merchant", "iat":11,
    "reference":"closed-A", "error":"checkout_unavailable", "error_description":"Unavailable"})
}
fn success() -> Value {
    json!({"status":"Success", "iss":"merchant", "iat":11,
    "reference":"closed-A", "order_id":"order-42"})
}

#[test]
fn independent_scopes_do_not_supply_shared_authorization_serialization() {
    let first = state("fresh");
    let alias = PresentationLedger {
        open_mandate_scope: "alias/open-mandate-A".into(),
        ..first.clone()
    };
    let presentation = state("pending").pending.unwrap();
    assert_ne!(first.open_mandate_scope, alias.open_mandate_scope);
    // Both calls succeed. A Host that aliases one authenticated authorization
    // into these scopes must provide a shared atomic gate before either send.
    assert!(
        first
            .present(OPEN_CHECKOUT_VCT, CLOSED_CHECKOUT_VCT, presentation.clone())
            .is_some()
    );
    assert!(
        alias
            .present(OPEN_CHECKOUT_VCT, CLOSED_CHECKOUT_VCT, presentation)
            .is_some()
    );
}

#[test]
fn lean_lifecycle_matches_signed_checkout_receipts() {
    let pending = state("pending");
    let p = pending.pending.as_ref().unwrap();
    assert_eq!(
        state("fresh").present(OPEN_CHECKOUT_VCT, CLOSED_CHECKOUT_VCT, p.clone()),
        Some(pending.clone())
    );
    assert!(
        pending
            .present(OPEN_CHECKOUT_VCT, CLOSED_CHECKOUT_VCT, p.clone())
            .is_none()
    );
    let rejected = trust().verify(&jwt(&rejection()), p, 12).unwrap();
    assert_eq!(pending.complete(&rejected), Some(state("rejected")));
    let accepted = trust().verify(&jwt(&success()), p, 12).unwrap();
    assert_eq!(pending.complete(&accepted), Some(state("succeeded")));
    assert!(
        state("succeeded")
            .present(
                OPEN_CHECKOUT_VCT,
                CLOSED_CHECKOUT_VCT,
                CheckoutPresentation {
                    reference: "closed-B".into(),
                    ..p.clone()
                }
            )
            .is_none()
    );
}
#[test]
fn old_rejection_and_timeout_cannot_unlock_another_presentation() {
    let pending = state("pending");
    let p = pending.pending.as_ref().unwrap();
    let rejected = trust().verify(&jwt(&rejection()), p, 12).unwrap();
    let clear = pending.complete(&rejected).unwrap();
    assert!(
        clear
            .present(OPEN_CHECKOUT_VCT, CLOSED_CHECKOUT_VCT, p.clone())
            .is_none()
    );
    let next = clear
        .present(
            OPEN_CHECKOUT_VCT,
            CLOSED_CHECKOUT_VCT,
            CheckoutPresentation {
                reference: "closed-B".into(),
                presented_at: 12,
                ..p.clone()
            },
        )
        .unwrap();
    assert!(next.complete(&rejected).is_none());
    assert!(
        next.present(OPEN_CHECKOUT_VCT, CLOSED_CHECKOUT_VCT, p.clone())
            .is_none()
    );
}
#[test]
fn schema_role_and_status_confusion_fail_closed() {
    let pending = state("pending");
    let p = pending.pending.as_ref().unwrap();
    let mut cases = vec![];
    for (field, value) in [
        ("status", json!("error")),
        ("error", json!("timeout_unknown")),
        ("error", Value::Null),
        ("order_id", json!("order")),
        ("payment_id", json!("payment")),
        ("verified", json!(true)),
    ] {
        let mut payload = rejection();
        payload[field] = value;
        cases.push(payload);
    }
    let mut no_description = rejection();
    no_description
        .as_object_mut()
        .unwrap()
        .remove("error_description");
    cases.push(no_description);
    let mut mixed = success();
    mixed["error"] = json!("oops");
    cases.push(mixed);
    for payload in cases {
        assert!(trust().verify(&jwt(&payload), p, 12).is_err(), "{payload}");
    }
    let duplicate = r#"{"status":"Error","iss":"merchant","iat":11,"reference":"closed-B","reference":"closed-A","error":"x","error_description":"x"}"#;
    assert!(
        trust()
            .verify(&sign_raw(r#"{"alg":"ES256"}"#, duplicate, 7), p, 12)
            .is_err()
    );
}
#[test]
fn issuer_reference_time_and_signatures_are_independently_bound() {
    let pending = state("pending");
    let p = pending.pending.as_ref().unwrap();
    for (field, value) in [
        ("iss", json!("attacker")),
        ("reference", json!("other")),
        ("iat", json!(9)),
        ("iat", json!(13)),
    ] {
        let mut payload = rejection();
        payload[field] = value;
        assert!(trust().verify(&jwt(&payload), p, 12).is_err());
    }
    assert!(
        trust()
            .verify(
                &sign_raw(r#"{"alg":"ES256"}"#, &rejection().to_string(), 8),
                p,
                12
            )
            .is_err()
    );
    for header in [
        r#"{"alg":"none"}"#,
        r#"{"alg":"HS256"}"#,
        r#"{"alg":"ES256","crit":["b64"],"b64":false}"#,
        r#"{"alg":"ES256","kid":"foreign"}"#,
        r#"{"alg":"ES256","alg":"ES256"}"#,
    ] {
        assert!(
            trust()
                .verify(&sign_raw(header, &rejection().to_string(), 7), p, 12)
                .is_err()
        );
    }
}
#[test]
fn rotation_revocation_and_exact_vct_matching_are_enforced() {
    let pending = state("pending");
    let p = pending.pending.as_ref().unwrap();
    let mut keys = trust();
    keys.enroll("merchant".into(), "key-8".into(), *key(8).verifying_key());
    assert!(keys.verify(&jwt(&rejection()), p, 12).is_err());
    keys.revoke("merchant");
    assert!(keys.verify(&jwt(&rejection()), p, 12).is_err());
    assert!(
        state("fresh")
            .present("mandate.checkout.open.2", CLOSED_CHECKOUT_VCT, p.clone())
            .is_none()
    );
    assert!(
        state("fresh")
            .present(OPEN_CHECKOUT_VCT, "mandate.payment.1", p.clone())
            .is_none()
    );
    let exhausted = PresentationLedger {
        revision: u64::MAX,
        ..state("fresh")
    };
    assert!(
        exhausted
            .present(OPEN_CHECKOUT_VCT, CLOSED_CHECKOUT_VCT, p.clone())
            .is_none()
    );
}

#[test]
fn wire_payloads_match_pinned_upstream_required_schema() {
    let schema: Value = serde_json::from_slice(include_bytes!(
        "../../../../Tests/Conformance/ap2-upstream/checkout_receipt.json"
    ))
    .unwrap();
    let status: Value = serde_json::from_slice(include_bytes!(
        "../../../../Tests/Conformance/ap2-upstream/types/receipt_status.json"
    ))
    .unwrap();
    for payload in [rejection(), success()] {
        assert!(
            status["enum"]
                .as_array()
                .unwrap()
                .contains(&payload["status"])
        );
        for field in schema["required"].as_array().unwrap() {
            assert!(payload.get(field.as_str().unwrap()).is_some());
        }
        let branch = schema["oneOf"]
            .as_array()
            .unwrap()
            .iter()
            .find(|b| b["properties"]["status"]["const"] == payload["status"])
            .unwrap();
        for field in branch["required"].as_array().unwrap() {
            assert!(payload.get(field.as_str().unwrap()).is_some());
        }
        for (name, value) in payload.as_object().unwrap() {
            match schema["properties"][name]["type"].as_str() {
                Some("string") => assert!(value.is_string()),
                Some("integer") => assert!(value.is_u64()),
                None => assert_eq!(name, "status"),
                _ => panic!("unsupported pinned field: {name}"),
            }
        }
    }
}

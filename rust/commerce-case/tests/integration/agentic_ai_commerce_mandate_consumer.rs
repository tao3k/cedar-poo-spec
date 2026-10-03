use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use cedar_poo_commerce_mandate::checkout::{
    AP2_SOURCE_REVISION, Audience, CheckoutConstraintCoverage, CheckoutContext, MandateError,
    MerchantId, ServerNonce, TransactionContext,
};
use p256::ecdsa::{Signature, SigningKey, VerifyingKey, signature::Signer};
use serde_json::{Value, json};

fn corpus() -> Value {
    serde_json::from_slice(include_bytes!(
        "../../../../Tests/Conformance/ap2-mandate-wire-v1.json"
    ))
    .unwrap()
}
fn key(value: &Value) -> VerifyingKey {
    let mut point = vec![4];
    for name in ["x", "y"] {
        point.extend(
            URL_SAFE_NO_PAD
                .decode(value[name].as_str().unwrap())
                .unwrap(),
        );
    }
    VerifyingKey::from_sec1_bytes(&point).unwrap()
}
fn context(vector: &Value) -> CheckoutContext {
    CheckoutContext {
        root_key: key(&vector["root_jwk"]),
        merchant_key: key(&vector["merchant_jwk"]),
        now: vector["context"]["now"].as_u64().unwrap(),
        transaction: TransactionContext {
            audience: Audience(vector["context"]["aud"].as_str().unwrap_or("").into()),
            nonce: ServerNonce(vector["context"]["nonce"].as_str().unwrap_or("").into()),
            merchant: MerchantId("merchant-1".into()),
        },
    }
}
#[test]
fn frozen_sdk_corpus_matches_strict_profile_expectations() {
    let corpus = corpus();
    assert_eq!(corpus["ap2_revision"], AP2_SOURCE_REVISION);
    let mut accepted = 0;
    let mut rejected = 0;
    for vector in corpus["vectors"].as_array().unwrap() {
        let tokens: Vec<_> = vector["tokens"]
            .as_array()
            .unwrap()
            .iter()
            .map(|t| t.as_str().unwrap())
            .collect();
        let result = context(vector).verify(&tokens);
        if vector["contract_expectation"] == "accept" {
            let binding = result.unwrap_or_else(|e| panic!("{}: {e:?}", vector["id"]));
            assert_eq!(
                binding.checkout_hash(),
                vector["context"]["checkout_hash"].as_str().unwrap()
            );
            assert_eq!(binding.merchant_checkout().checkout_id(), "checkout-1");
            assert_eq!(
                binding.constraint_coverage(),
                CheckoutConstraintCoverage::SeedBindingOnly
            );
            assert!(!binding.root_jws_digest().is_empty());
            assert!(!binding.closed_jws_digest().is_empty());
            assert!(!binding.agent_key_digest().is_empty());
            accepted += 1;
        } else {
            assert!(
                result.is_err(),
                "negative vector admitted: {}",
                vector["id"]
            );
            rejected += 1;
        }
    }
    assert_eq!((accepted, rejected), (3, 14));
}
fn signing(seed: u8) -> SigningKey {
    SigningKey::from_bytes((&[seed; 32]).into()).unwrap()
}
fn sign(header: &str, payload: &str, key: &SigningKey) -> String {
    let bytes = format!(
        "{}.{}",
        URL_SAFE_NO_PAD.encode(header),
        URL_SAFE_NO_PAD.encode(payload)
    );
    let signature: Signature = key.sign(bytes.as_bytes());
    format!("{bytes}.{}", URL_SAFE_NO_PAD.encode(signature.to_bytes()))
}
struct Sample {
    context: CheckoutContext,
    open: Value,
    closed: Value,
}
impl Sample {
    fn new() -> Self {
        let corpus = corpus();
        let vector = &corpus["vectors"][0];
        let agent = signing(11).verifying_key().to_encoded_point(false);
        let mut open = vector["sdk_observation"]["payloads"][0].clone();
        open["cnf"]["jwk"] = json!({"kty":"EC", "crv":"P-256", "x":URL_SAFE_NO_PAD.encode(agent.x().unwrap()), "y":URL_SAFE_NO_PAD.encode(agent.y().unwrap())});
        let mut context = context(vector);
        context.root_key = *signing(10).verifying_key();
        Self {
            context,
            open,
            closed: vector["sdk_observation"]["payloads"][1].clone(),
        }
    }
    fn tokens(&self, change: impl FnOnce(&mut Value)) -> Vec<String> {
        let root = format!(
            "{}~",
            sign(
                r#"{"alg":"ES256","typ":"example+sd-jwt"}"#,
                &json!({"delegate_payload":[self.open]}).to_string(),
                &signing(10)
            )
        );
        // Parent hash is obtained through the existing independently qualified SHA helper.
        let digest = cedar_poo_commerce::signatures::sha256_hex(root.as_bytes());
        let bytes: Vec<_> = digest
            .as_bytes()
            .as_chunks::<2>()
            .0
            .iter()
            .map(|b| u8::from_str_radix(std::str::from_utf8(b).unwrap(), 16).unwrap())
            .collect();
        let mut payload = json!({"delegate_payload":[self.closed], "iat":1800000000u64, "aud":"https://merchant.example", "nonce":"server-nonce-1", "sd_hash":URL_SAFE_NO_PAD.encode(bytes)});
        change(&mut payload);
        let leaf = format!(
            "{}~",
            sign(
                r#"{"alg":"ES256","typ":"kb+sd-jwt"}"#,
                &payload.to_string(),
                &signing(11)
            )
        );
        vec![root, leaf]
    }
    fn outcome(&self, change: impl FnOnce(&mut Value)) -> Result<(), MandateError> {
        let tokens = self.tokens(change);
        self.context
            .verify(&tokens.iter().map(String::as_str).collect::<Vec<_>>())
            .map(|_| ())
    }
}
#[test]
fn independently_signed_claim_mutations_are_refused() {
    let mut sample = Sample::new();
    assert_eq!(sample.outcome(|_| {}), Ok(()));
    assert_eq!(
        sample.outcome(|p| p["delegate_payload"][0]["checkout_hash"] = "other".into()),
        Err(MandateError::Binding)
    );
    assert_eq!(
        sample.outcome(|p| p["delegate_payload"][0]["exp"] = 1800000601u64.into()),
        Err(MandateError::Time)
    );
    assert_eq!(
        sample.outcome(|p| p["delegate_payload"][0]["verified"] = true.into()),
        Err(MandateError::Unsupported)
    );
    sample.open["constraints"] = json!([{"type":"unknown.constraint"}]);
    assert_eq!(sample.outcome(|_| {}), Err(MandateError::Unsupported));
}
#[test]
fn exclusive_expiry_and_authenticated_merchant_context_are_enforced() {
    let mut sample = Sample::new();
    sample.context.now = 1800000600;
    assert_eq!(sample.outcome(|_| {}), Err(MandateError::Time));
    sample.context.now = 1800000000;
    sample.context.transaction.merchant = MerchantId("other-merchant".into());
    assert_eq!(sample.outcome(|_| {}), Err(MandateError::Context));
}
#[test]
fn duplicate_members_and_unsupported_jose_cannot_be_hidden_by_signatures() {
    let sample = Sample::new();
    let mut tokens = sample.tokens(|_| {});
    tokens[0] = format!(
        "{}~",
        sign(
            r#"{"alg":"ES256","typ":"example+sd-jwt","alg":"ES256"}"#,
            &json!({"delegate_payload":[sample.open]}).to_string(),
            &signing(10)
        )
    );
    assert_eq!(
        sample
            .context
            .verify(&tokens.iter().map(String::as_str).collect::<Vec<_>>())
            .err(),
        Some(MandateError::Malformed)
    );
    tokens[0] = format!(
        "{}~",
        sign(
            r#"{"alg":"ES256","typ":"example+sd-jwt","jwk":{}}"#,
            "{}",
            &signing(10)
        )
    );
    assert_eq!(
        sample
            .context
            .verify(&tokens.iter().map(String::as_str).collect::<Vec<_>>())
            .err(),
        Some(MandateError::Unsupported)
    );
    tokens[0] = format!(
        "{}~",
        sign(
            r#"{"alg":"ES256","typ":"example+sd-jwt"}"#,
            r#"{"delegate_payload":[],"delegate_payload":[]}"#,
            &signing(10)
        )
    );
    assert_eq!(
        sample
            .context
            .verify(&tokens.iter().map(String::as_str).collect::<Vec<_>>())
            .err(),
        Some(MandateError::Malformed)
    );
}
#[test]
fn malformed_bounds_and_empty_host_inputs_refuse_verification() {
    let mut sample = Sample::new();
    assert_eq!(
        sample.context.verify(&[]).err(),
        Some(MandateError::Unsupported)
    );
    assert_eq!(
        sample.context.verify(&[&"a".repeat(16385), "x~"]).err(),
        Some(MandateError::Limit)
    );
    sample.context.transaction.nonce = ServerNonce(String::new());
    assert_eq!(sample.outcome(|_| {}), Err(MandateError::Context));
}

fn hash_bytes(bytes: &[u8]) -> String {
    let hex = cedar_poo_commerce::signatures::sha256_hex(bytes);
    let decoded: Vec<_> = hex
        .as_bytes()
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap())
        .collect();
    URL_SAFE_NO_PAD.encode(decoded)
}
fn with_root(sample: &Sample, root: String) -> Vec<String> {
    let base = sample.tokens(|_| {});
    let payload_segment = base[1].split('.').nth(1).unwrap();
    let mut payload: Value =
        serde_json::from_slice(&URL_SAFE_NO_PAD.decode(payload_segment).unwrap()).unwrap();
    payload["sd_hash"] = hash_bytes(root.as_bytes()).into();
    vec![
        root,
        format!(
            "{}~",
            sign(
                r#"{"alg":"ES256","typ":"kb+sd-jwt"}"#,
                &payload.to_string(),
                &signing(11)
            )
        ),
    ]
}
#[test]
fn signed_disclosure_graphs_reject_unmatched_reused_and_reserved_claims() {
    let sample = Sample::new();
    let disclosure = URL_SAFE_NO_PAD.encode(json!(["salt", sample.open]).to_string());
    let digest = hash_bytes(disclosure.as_bytes());
    let make = |payload: Value, disclosures: &str| {
        format!(
            "{}~{disclosures}",
            sign(
                r#"{"alg":"ES256","typ":"example+sd-jwt"}"#,
                &payload.to_string(),
                &signing(10)
            )
        )
    };
    let positive = make(
        json!({"delegate_payload":[{"...":digest}]}),
        &format!("{disclosure}~"),
    );
    let tokens = with_root(&sample, positive.clone());
    assert!(
        sample
            .context
            .verify(&tokens.iter().map(String::as_str).collect::<Vec<_>>())
            .is_ok()
    );
    let unused = URL_SAFE_NO_PAD.encode(json!(["salt", "unused", 1]).to_string());
    let tokens = with_root(&sample, format!("{positive}{unused}~"));
    assert_eq!(
        sample
            .context
            .verify(&tokens.iter().map(String::as_str).collect::<Vec<_>>())
            .err(),
        Some(MandateError::Disclosure)
    );
    let repeated = make(
        json!({"delegate_payload":[{"...":digest}, {"...":digest}]}),
        &format!("{disclosure}~"),
    );
    let tokens = with_root(&sample, repeated);
    assert_eq!(
        sample
            .context
            .verify(&tokens.iter().map(String::as_str).collect::<Vec<_>>())
            .err(),
        Some(MandateError::Disclosure)
    );
    let reserved = URL_SAFE_NO_PAD.encode(json!(["salt", "_sd", []]).to_string());
    let root = make(
        json!({"_sd":[hash_bytes(reserved.as_bytes())],"delegate_payload":[sample.open]}),
        &format!("{reserved}~"),
    );
    let tokens = with_root(&sample, root);
    assert_eq!(
        sample
            .context
            .verify(&tokens.iter().map(String::as_str).collect::<Vec<_>>())
            .err(),
        Some(MandateError::Disclosure)
    );
}
#[test]
fn signature_aliases_change_evidence_but_not_signed_content_identity() {
    let sample = Sample::new();
    let tokens = sample.tokens(|_| {});
    let original = sample
        .context
        .verify(&tokens.iter().map(String::as_str).collect::<Vec<_>>())
        .unwrap();
    let issuer = tokens[0].trim_end_matches('~');
    let (content, signature) = issuer.rsplit_once('.').unwrap();
    let mut raw = URL_SAFE_NO_PAD.decode(signature).unwrap();
    // s -> n-s is an alternative valid P-256 ECDSA signature. The verifier's
    // signed-content identity must not confuse this encoding with a new mandate.
    let order = [
        0xffu8, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xbc, 0xe6, 0xfa, 0xad, 0xa7, 0x17, 0x9e, 0x84, 0xf3, 0xb9, 0xca, 0xc2, 0xfc, 0x63,
        0x25, 0x51,
    ];
    let mut borrow = 0i16;
    for i in (0..32).rev() {
        let difference = i16::from(order[i]) - i16::from(raw[32 + i]) - borrow;
        raw[32 + i] = difference.rem_euclid(256) as u8;
        borrow = i16::from(difference < 0);
    }
    let alias_tokens = with_root(
        &sample,
        format!("{content}.{}~", URL_SAFE_NO_PAD.encode(raw)),
    );
    let alias = sample
        .context
        .verify(&alias_tokens.iter().map(String::as_str).collect::<Vec<_>>())
        .unwrap();
    assert_ne!(original.root_jws_digest(), alias.root_jws_digest());
    assert_eq!(
        original.root_signed_content_digest(),
        alias.root_signed_content_digest()
    );
    assert_eq!(original.root_key_digest(), alias.root_key_digest());
}

#[test]
fn pinned_constraint_cases_match_selected_policy_after_all_signatures() {
    let corpus: Value = serde_json::from_slice(include_bytes!(
        "../../../../Tests/Conformance/ap2-checkout-constraints-v1.json"
    ))
    .unwrap();
    assert_eq!(corpus["ap2_revision"], AP2_SOURCE_REVISION);
    let mut accepted = 0;
    let mut rejected = 0;
    for case in corpus["cases"].as_array().unwrap() {
        let mut sample = Sample::new();
        sample.context.merchant_key = *signing(12).verifying_key();
        sample.open["constraints"] = case["constraints"].clone();
        let checkout = sign(
            r#"{"alg":"ES256","typ":"JWT"}"#,
            &case["checkout"].to_string(),
            &signing(12),
        );
        sample.closed["checkout_hash"] = hash_bytes(checkout.as_bytes()).into();
        sample.closed["checkout_jwt"] = checkout.into();
        let tokens = sample.tokens(|_| {});
        let result = sample
            .context
            .verify(&tokens.iter().map(String::as_str).collect::<Vec<_>>())
            .map(|binding| binding.constraint_coverage());
        if case["contract_expectation"] == "accept" {
            assert_eq!(
                result,
                Ok(CheckoutConstraintCoverage::ItemConstraintsChecked),
                "{}",
                case["id"]
            );
            accepted += 1;
        } else {
            assert!(
                result.is_err(),
                "negative constraint admitted: {}",
                case["id"]
            );
            rejected += 1;
        }
    }
    assert_eq!((accepted, rejected), (3, 12));
}
fn constrained_sample(requirements: Value, lines: Value) -> Sample {
    let mut sample = Sample::new();
    sample.context.merchant_key = *signing(12).verifying_key();
    sample.open["constraints"] = json!([{"type":"checkout.line_items","items":requirements}]);
    let checkout = json!({"id":"checkout-bounds","merchant":{"id":"merchant-1","name":"Shop"},"line_items":lines});
    let jwt = sign(
        r#"{"alg":"ES256","typ":"JWT"}"#,
        &checkout.to_string(),
        &signing(12),
    );
    sample.closed["checkout_hash"] = hash_bytes(jwt.as_bytes()).into();
    sample.closed["checkout_jwt"] = jwt.into();
    sample
}
#[test]
fn oversized_and_ambiguous_requirements_fail_closed() {
    let requirement = json!({"id":"r","quantity":1,"acceptable_items":[{"id":"A","title":"A"}]});
    let lines =
        json!([{"id":"l","item":{"id":"A","title":"A","price":1},"quantity":1,"totals":[]}]);
    let sample = constrained_sample(json!(vec![requirement.clone(); 9]), lines.clone());
    assert_eq!(sample.outcome(|_| {}), Err(MandateError::Limit));
    let mut too_large = requirement.clone();
    too_large["quantity"] = 1_000_001u64.into();
    assert_eq!(
        constrained_sample(json!([too_large]), lines.clone()).outcome(|_| {}),
        Err(MandateError::Limit)
    );
    let mut duplicate = requirement.clone();
    duplicate["acceptable_items"] = json!([{"id":"A","title":"A"},{"id":"A","title":"alias"}]);
    assert_eq!(
        constrained_sample(json!([duplicate]), lines.clone()).outcome(|_| {}),
        Err(MandateError::Claims)
    );
    let mut extra = requirement;
    extra["minimum_price"] = 1.into();
    assert_eq!(
        constrained_sample(json!([extra]), lines).outcome(|_| {}),
        Err(MandateError::Unsupported)
    );
}
#[test]
fn exhausting_assignment_budget_never_returns_a_verified_binding() {
    let items: Vec<_> = (b'A'..=b'H')
        .map(|sku| {
            let id = char::from(sku).to_string();
            json!({"id":id,"item":{"id":id,"title":id,"price":1},"quantity":1,"totals":[]})
        })
        .collect();
    let alternatives: Vec<_> = (b'A'..=b'G')
        .map(|sku| {
            let id = char::from(sku).to_string();
            json!({"id":id,"title":id})
        })
        .collect();
    let mut requirements: Vec<_> = (0..7)
        .map(|i| json!({"id":format!("r{i}"),"quantity":1,"acceptable_items":alternatives}))
        .collect();
    requirements
        .push(json!({"id":"last","quantity":1,"acceptable_items":[{"id":"A","title":"A"}]}));
    assert_eq!(
        constrained_sample(json!(requirements), json!(items)).outcome(|_| {}),
        Err(MandateError::Limit)
    );
}

#[test]
fn selective_omission_cannot_erase_constraints_or_requirement_slots() {
    let hidden = json!({"...":hash_bytes(b"hidden-requirement")});
    let mut sample = Sample::new();
    sample.open["constraints"] = json!([hidden]);
    assert_eq!(sample.outcome(|_| {}), Err(MandateError::Unsupported));
    let requirements =
        json!([{"id":"r","quantity":1,"acceptable_items":[{"id":"A","title":"A"}]},hidden]);
    let lines =
        json!([{"id":"l","item":{"id":"A","title":"A","price":1},"quantity":1,"totals":[]}]);
    assert_eq!(
        constrained_sample(requirements, lines).outcome(|_| {}),
        Err(MandateError::Unsupported)
    );
}

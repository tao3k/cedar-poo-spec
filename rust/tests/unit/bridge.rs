use super::{Case, Manifest, check_manifest, load_policy_set, render_artifacts};
use serde_json::json;

fn receipt() -> Case {
    serde_json::from_value(json!({
            "name": "allow-all",
            "revision": "published",
            "policy_ids": ["base"],
        "policies": {
            "staticPolicies": {
                "base": {
                    "effect": "permit",
                    "principal": { "op": "All" },
                    "action": { "op": "All" },
                    "resource": { "op": "All" },
                    "conditions": []
                }
            },
            "templates": {},
            "templateLinks": []
        },
        "entities": [],
        "request": {
            "principal": "User::\"alice\"",
            "action": "Action::\"view\"",
            "resource": "Document::\"one\"",
            "context": {}
        },
        "expected": "allow",
        "expected_errors": 0
    }))
    .expect("valid local receipt")
}

#[test]
fn accepts_materialized_receipt_and_preserves_id() {
    let case = receipt();
    let policies = load_policy_set(&case.policies).expect("materialized policy set");
    assert_eq!(policies.policies().next().unwrap().id().to_string(), "base");
    check_manifest(&Manifest { cases: vec![case] }).expect("same Cedar decision");
}

#[test]
fn rejects_decision_drift_and_duplicate_case_names() {
    let mut case = receipt();
    case.expected = "deny".into();
    assert!(
        check_manifest(&Manifest { cases: vec![case] })
            .unwrap_err()
            .contains("expected deny")
    );

    let first = receipt();
    let second = receipt();
    assert!(
        check_manifest(&Manifest {
            cases: vec![first, second]
        })
        .unwrap_err()
        .contains("duplicate case name")
    );
}

#[test]
fn rejects_policy_id_drift_from_lean_receipt() {
    let mut case = receipt();
    case.policy_ids = vec!["missing".into()];
    assert!(
        check_manifest(&Manifest { cases: vec![case] })
            .unwrap_err()
            .contains("loaded policy IDs differ")
    );
}

#[test]
fn rejects_template_payload_at_materialized_boundary() {
    let mut case = receipt();
    let mut value = case.policies.as_value().clone();
    value["templateLinks"] = json!([{}]);
    case.policies = serde_json::from_value(value).expect("JSON artifact");
    assert!(
        load_policy_set(&case.policies)
            .unwrap_err()
            .contains("only materialized policies")
    );
}

#[test]
fn rejects_conflicting_revision_artifacts() {
    let first = receipt();
    let mut second = receipt();
    second.name = "other".into();
    let mut value = second.policies.as_value().clone();
    value["staticPolicies"]["base"]["effect"] = json!("forbid");
    second.policies = serde_json::from_value(value).expect("JSON artifact");
    assert!(
        render_artifacts(&Manifest {
            cases: vec![first, second]
        })
        .unwrap_err()
        .contains("conflicting revision output")
    );
}

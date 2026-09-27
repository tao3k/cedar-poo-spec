use super::{
    Case, Manifest, check_direct_sources, check_manifest, check_template_source, load_policy_set,
    load_template_source, render_artifacts,
};
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
        "expected_reasons": ["base"],
        "expected_error_policies": []
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
fn rejects_reason_drift_with_unchanged_decision() {
    let mut case = receipt();
    case.expected_reasons.clear();
    assert!(
        check_manifest(&Manifest { cases: vec![case] })
            .unwrap_err()
            .contains("reasons")
    );
}

#[test]
fn rejects_error_policy_drift_with_unchanged_count() {
    let mut case = receipt();
    case.expected_error_policies = vec!["other".into()];
    assert!(
        check_manifest(&Manifest { cases: vec![case] })
            .unwrap_err()
            .contains("errors")
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

#[test]
fn cached_revision_requires_identical_policy_artifacts() {
    let first = receipt();
    let mut second = receipt();
    second.name = "second request".into();
    check_manifest(&Manifest {
        cases: vec![first, second],
    })
    .expect("same revision is reusable");

    let first = receipt();
    let mut second = receipt();
    second.name = "second request".into();
    second.expected = "deny".into();
    assert!(
        check_manifest(&Manifest {
            cases: vec![first, second]
        })
        .unwrap_err()
        .contains("expected deny")
    );

    let first = receipt();
    let mut changed = receipt();
    changed.name = "changed body".into();
    let mut value = changed.policies.as_value().clone();
    value["staticPolicies"]["base"]["conditions"] = json!([{
        "kind": "when",
        "body": { "type": "Boolean", "value": true }
    }]);
    changed.policies = serde_json::from_value(value).expect("JSON artifact");
    assert!(
        check_manifest(&Manifest {
            cases: vec![first, changed]
        })
        .unwrap_err()
        .contains("conflicting revision output")
    );
}

#[test]
fn direct_cedar_check_detects_policy_drift() {
    let directory =
        std::env::temp_dir().join(format!("cedar-poo-direct-check-{}", std::process::id()));
    std::fs::create_dir_all(&directory).expect("temporary directory");
    let path = directory.join("published.cedar");
    let manifest = Manifest {
        cases: vec![receipt()],
    };
    std::fs::write(&path, "permit(principal, action, resource);").expect("direct permit");
    check_direct_sources(&manifest, &directory).expect("matching decision");
    std::fs::write(&path, "permit(principal, action, resource) when { true };")
        .expect("different body with the same decision");
    assert!(
        check_direct_sources(&manifest, &directory)
            .unwrap_err()
            .contains("direct policy bodies differ")
    );
    std::fs::write(&path, "forbid(principal, action, resource);").expect("direct forbid");
    assert!(
        check_direct_sources(&manifest, &directory)
            .unwrap_err()
            .contains("direct policy bodies differ")
    );
    std::fs::remove_dir_all(directory).expect("remove temporary directory");
}

fn template_source_fixture() -> (serde_json::Value, super::CompiledPolicyJson) {
    let source = json!({
        "staticPolicies": {},
        "templates": {
            "grant": {
                "effect": "permit",
                "principal": { "op": "==", "slot": "?principal" },
                "action": { "op": "All" },
                "resource": { "op": "All" },
                "conditions": []
            }
        },
        "templateLinks": [{
            "templateId": "grant",
            "newId": "base",
            "values": { "?principal": { "type": "User", "id": "alice" } }
        }]
    });
    let mut materialized = receipt().policies.as_value().clone();
    materialized["staticPolicies"]["base"]["principal"] =
        json!({ "op": "==", "entity": { "type": "User", "id": "alice" } });
    let materialized = serde_json::from_value(materialized).expect("policy set JSON");
    (source, materialized)
}

#[test]
fn template_source_requires_exact_linked_policy_bodies() {
    let (source, materialized) = template_source_fixture();
    let typed_source = serde_json::from_value(source.clone()).expect("template source JSON");
    check_template_source(&typed_source, &materialized).expect("matching linked policy");

    let mut changed = source.clone();
    changed["templates"]["grant"]["effect"] = json!("forbid");
    let typed_changed = serde_json::from_value(changed).expect("changed template source JSON");
    assert!(
        check_template_source(&typed_changed, &materialized)
            .unwrap_err()
            .contains("differ from Lean materialization")
    );
    let mut changed = source;
    changed["templateLinks"][0]["values"] = json!({});
    let typed_changed = serde_json::from_value(changed).expect("incomplete template source JSON");
    assert!(
        check_template_source(&typed_changed, &materialized)
            .unwrap_err()
            .contains("template source parse")
    );
}

#[test]
fn template_source_rejects_unlinked_templates() {
    let (mut source, materialized) = template_source_fixture();
    source["templates"]["unused"] = source["templates"]["grant"].clone();
    source["templates"]["unused"]["effect"] = json!("forbid");
    let source = serde_json::from_value(source).expect("template source JSON");
    let parsed = load_template_source(&source).expect("Cedar accepts an unused template");
    assert_eq!(parsed.templates().count(), 2);
    assert!(
        check_template_source(&source, &materialized)
            .unwrap_err()
            .contains("template has no linked policy: unused")
    );
}

#[test]
fn mixed_template_source_checks_static_bodies_and_id_collisions() {
    let (mut source, materialized) = template_source_fixture();
    let static_body = json!({
        "effect": "forbid",
        "principal": { "op": "All" },
        "action": { "op": "All" },
        "resource": { "op": "All" },
        "conditions": []
    });
    source["staticPolicies"]["static-veto"] = static_body.clone();
    let mut expected = materialized.as_value().clone();
    expected["staticPolicies"]["static-veto"] = static_body;
    let expected = serde_json::from_value(expected).expect("mixed materialized JSON");
    let typed_source = serde_json::from_value(source.clone()).expect("mixed source JSON");
    check_template_source(&typed_source, &expected).expect("mixed source matches");

    let mut changed = source.clone();
    changed["staticPolicies"]["static-veto"]["effect"] = json!("permit");
    let changed = serde_json::from_value(changed).expect("changed mixed source JSON");
    assert!(
        check_template_source(&changed, &expected)
            .unwrap_err()
            .contains("differ from Lean materialization")
    );

    source["staticPolicies"]["base"] = source["staticPolicies"]["static-veto"].clone();
    let collision = serde_json::from_value(source).expect("collision source JSON");
    assert!(
        check_template_source(&collision, &expected)
            .unwrap_err()
            .contains("template source parse")
    );
}

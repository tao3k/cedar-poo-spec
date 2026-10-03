use cedar_poo_commerce::acceptance::{AcceptanceTicket, RootFence};

#[test]
fn lean_acceptance_decisions_match() {
    let fixture: serde_json::Value = serde_json::from_slice(include_bytes!(
        "../../../../Tests/Conformance/commerce-acceptance-v1.json"
    ))
    .unwrap();
    for row in fixture["cases"].as_array().unwrap() {
        let fence: RootFence = serde_json::from_value(row["fence"].clone()).unwrap();
        let ticket: AcceptanceTicket = serde_json::from_value(row["ticket"].clone()).unwrap();
        assert_eq!(
            fence.accepts(
                &ticket,
                row["provider"].as_str().unwrap(),
                row["operation"].as_str().unwrap(),
                row["commitment"].as_str().unwrap()
            ),
            row["accepted"].as_bool().unwrap(),
            "{}",
            row["name"]
        );
    }
}

#[test]
fn irreversible_retirement_and_independent_roots() {
    use cedar_poo_commerce::acceptance::AuthorizationRoot;
    let active = RootFence {
        root: AuthorizationRoot {
            budget_scope: "scope".into(),
            mandate_id: "root".into(),
        },
        generation: 7,
        retired: false,
    };
    let retired = RootFence {
        generation: 8,
        retired: true,
        ..active.clone()
    };
    assert_eq!(active.advance(&retired), Some(retired.clone()));
    assert!(
        retired
            .advance(&RootFence {
                generation: 9,
                ..active.clone()
            })
            .is_none()
    );
    assert!(retired.advance(&active).is_none());
    let other = RootFence {
        root: AuthorizationRoot {
            budget_scope: "other".into(),
            mandate_id: "root".into(),
        },
        generation: 99,
        retired: true,
    };
    assert!(active.advance(&other).is_none());
    assert!(active.advance(&active).is_none());
}

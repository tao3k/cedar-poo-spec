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

#[test]
fn takeover_fences_old_owner_and_acceptance_is_irreversible() {
    use cedar_poo_commerce::acceptance::DispatchOwnership;
    let ready = DispatchOwnership {
        request_commitment: "body".into(),
        generation: 0,
        owner: "fresh".into(),
        accepted: false,
    };
    let old = ready.acquire(0, "old").unwrap();
    let new = old.acquire(1, "new").unwrap();
    assert!(new.accept(1, "old", "body").is_none());
    assert!(new.accept(2, "new", "other-body").is_none());
    assert!(new.acquire(1, "race-loser").is_none());
    let accepted = new.accept(2, "new", "body").unwrap();
    assert!(accepted.acquire(2, "restart").is_none());
    assert!(accepted.accept(2, "new", "body").is_none());
    assert!(
        DispatchOwnership {
            generation: u64::MAX,
            ..ready
        }
        .acquire(u64::MAX, "next")
        .is_none()
    );
}

#[test]
fn lean_ownership_trace_matches_rust() {
    use cedar_poo_commerce::acceptance::DispatchOwnership;
    let fixture: serde_json::Value = serde_json::from_slice(include_bytes!(
        "../../../../Tests/Conformance/commerce-acceptance-v1.json"
    ))
    .unwrap();
    let state = |name: &str| -> DispatchOwnership {
        serde_json::from_value(fixture["ownership"][name].clone()).unwrap()
    };
    assert_eq!(state("ready").acquire(0, "old"), Some(state("old")));
    assert_eq!(state("old").acquire(1, "new"), Some(state("new")));
    assert!(state("new").accept(1, "old", "body-42").is_none());
    assert_eq!(
        state("new").accept(2, "new", "body-42"),
        Some(state("accepted"))
    );
    assert!(state("accepted").acquire(2, "restart").is_none());
}

use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use cedar_poo_commerce::{
    coordination::{
        CheckoutCoordinationIdentity, CoordinationCommit, SharedCheckoutState, SharedCheckoutStore,
        commit_presentation, commit_receipt,
    },
    presentation::{CheckoutPresentation, CheckoutReceiptTrust, VerifiedCheckoutReceipt},
};
use p256::ecdsa::{Signature, SigningKey, signature::Signer};
use serde_json::json;
use std::sync::{
    Arc, Barrier, Mutex,
    atomic::{AtomicBool, Ordering},
};

struct Store {
    record: Mutex<SharedCheckoutState>,
    lose_ack: AtomicBool,
}
impl Store {
    fn new(record: SharedCheckoutState) -> Self {
        Self {
            record: Mutex::new(record),
            lose_ack: AtomicBool::new(false),
        }
    }
    fn read(&self) -> SharedCheckoutState {
        self.record.lock().unwrap().clone()
    }
}
impl SharedCheckoutStore for Store {
    fn compare_exchange(
        &self,
        expected: &SharedCheckoutState,
        proposed: &SharedCheckoutState,
    ) -> CoordinationCommit {
        let mut record = self.record.lock().unwrap();
        if *record != *expected {
            return CoordinationCommit::Conflict;
        }
        assert_eq!(proposed.identity(), expected.identity());
        assert_eq!(proposed.revision(), expected.revision() + 1);
        *record = proposed.clone();
        if self.lose_ack.swap(false, Ordering::SeqCst) {
            CoordinationCommit::Unknown
        } else {
            CoordinationCommit::Applied
        }
    }
}
fn identity() -> CheckoutCoordinationIdentity {
    CheckoutCoordinationIdentity::enrolled("registry", "canonical-open-1", "agent-1", "policy-1")
        .unwrap()
}
fn presentation(reference: &str, time: u64) -> CheckoutPresentation {
    CheckoutPresentation {
        reference: reference.into(),
        merchant_issuer: "merchant".into(),
        presented_at: time,
    }
}
fn receipt(p: &CheckoutPresentation, success: bool) -> VerifiedCheckoutReceipt {
    let key = SigningKey::from_bytes((&[7; 32]).into()).unwrap();
    let mut trust = CheckoutReceiptTrust::default();
    trust.enroll("merchant".into(), "key".into(), *key.verifying_key());
    trust
        .allow_rejection("merchant", "terminal_rejection".into())
        .unwrap();
    let body = if success {
        json!({"status":"Success","iss":"merchant","iat":p.presented_at,"reference":p.reference,"order_id":"order-1"})
    } else {
        json!({"status":"Error","iss":"merchant","iat":p.presented_at,"reference":p.reference,"error":"terminal_rejection","error_description":"Not accepted"})
    };
    let message = format!(
        "{}.{}",
        URL_SAFE_NO_PAD.encode(r#"{"alg":"ES256","typ":"JWT"}"#),
        URL_SAFE_NO_PAD.encode(body.to_string())
    );
    let signature: Signature = key.sign(message.as_bytes());
    let jwt = format!(
        "{}.{}",
        message,
        URL_SAFE_NO_PAD.encode(signature.to_bytes())
    );
    trust.verify(&jwt, p, p.presented_at).unwrap()
}

#[test]
fn enrolled_tuple_boundaries_and_policy_dimensions_define_grouping() {
    assert_eq!(identity().storage_key(), identity().storage_key());
    assert!(CheckoutCoordinationIdentity::enrolled("", "a", "b", "c").is_err());
    assert!(CheckoutCoordinationIdentity::enrolled("r", &"x".repeat(257), "b", "c").is_err());
    for other in [
        CheckoutCoordinationIdentity::enrolled(
            "other-registry",
            "canonical-open-1",
            "agent-1",
            "policy-1",
        )
        .unwrap(),
        CheckoutCoordinationIdentity::enrolled("registry", "other-open", "agent-1", "policy-1")
            .unwrap(),
        CheckoutCoordinationIdentity::enrolled(
            "registry",
            "canonical-open-1",
            "other-agent",
            "policy-1",
        )
        .unwrap(),
        CheckoutCoordinationIdentity::enrolled(
            "registry",
            "canonical-open-1",
            "agent-1",
            "other-policy",
        )
        .unwrap(),
    ] {
        assert_ne!(identity().storage_key(), other.storage_key());
    }
    let a = CheckoutCoordinationIdentity::enrolled("a/b", "c", "d", "e").unwrap();
    let b = CheckoutCoordinationIdentity::enrolled("a", "b/c", "d", "e").unwrap();
    assert_ne!(a.storage_key(), b.storage_key());
}

#[test]
fn two_concurrent_alias_journals_commit_one_whole_record() {
    let initial = SharedCheckoutState::fresh(identity());
    let store = Arc::new(Store::new(initial.clone()));
    let barrier = Arc::new(Barrier::new(2));
    let workers: Vec<_> = ["alias-A", "alias-B"]
        .into_iter()
        .map(|alias| {
            let (store, barrier, expected) = (store.clone(), barrier.clone(), initial.clone());
            std::thread::spawn(move || {
                barrier.wait();
                commit_presentation(store.as_ref(), &expected, alias, presentation(alias, 10))
                    .unwrap()
            })
        })
        .collect();
    let results: Vec<_> = workers.into_iter().map(|w| w.join().unwrap()).collect();
    assert_eq!(
        results
            .iter()
            .filter(|r| **r == CoordinationCommit::Applied)
            .count(),
        1
    );
    assert_eq!(
        results
            .iter()
            .filter(|r| **r == CoordinationCommit::Conflict)
            .count(),
        1
    );
    let current = store.read();
    let (journal, p) = current.pending().unwrap();
    assert_eq!(current.journal(journal).unwrap().pending.as_ref(), Some(p));
    assert_eq!(current.revision(), 1);
    assert!(
        commit_presentation(
            store.as_ref(),
            &current,
            "third-alias",
            presentation("other", 11)
        )
        .is_err()
    );
}

#[test]
fn lost_ack_is_pending_and_retry_is_not_a_new_commit() {
    let initial = SharedCheckoutState::fresh(identity());
    let store = Store::new(initial.clone());
    store.lose_ack.store(true, Ordering::SeqCst);
    assert_eq!(
        commit_presentation(&store, &initial, "A", presentation("closed-A", 10)).unwrap(),
        CoordinationCommit::Unknown
    );
    assert!(store.read().pending().is_some());
    assert_eq!(
        commit_presentation(&store, &initial, "A", presentation("closed-A", 10)).unwrap(),
        CoordinationCommit::Conflict
    );
    assert!(commit_presentation(&store, &store.read(), "B", presentation("closed-B", 11)).is_err());
}

#[test]
fn rejection_tombstones_are_global_and_old_receipts_cannot_clear_an_alias() {
    let store = Store::new(SharedCheckoutState::fresh(identity()));
    let a = presentation("closed-A", 10);
    commit_presentation(&store, &store.read(), "A", a.clone()).unwrap();
    let rejection = receipt(&a, false);
    let pending = store.read();
    assert!(commit_receipt(&store, &pending, "B", &rejection).is_err());
    assert_eq!(
        commit_receipt(&store, &pending, "A", &rejection).unwrap(),
        CoordinationCommit::Applied
    );
    let released = store.read();
    assert!(released.pending().is_none());
    assert!(commit_presentation(&store, &released, "B", a).is_err());
    let b = presentation("closed-B", 11);
    commit_presentation(&store, &released, "B", b.clone()).unwrap();
    let pending = store.read();
    assert!(commit_receipt(&store, &pending, "B", &rejection).is_err());
    assert_eq!(store.read(), pending);
    commit_receipt(&store, &pending, "B", &receipt(&b, true)).unwrap();
    let spent = store.read();
    assert!(spent.spent());
    assert!(spent.pending().is_none());
    assert!(commit_presentation(&store, &spent, "C", presentation("closed-C", 12)).is_err());
}

#[test]
fn journal_limit_refuses_without_eviction_or_partial_update() {
    let store = Store::new(SharedCheckoutState::fresh(identity()));
    for index in 0..16 {
        let alias = format!("alias-{index}");
        let p = presentation(&format!("closed-{index}"), 10 + index);
        commit_presentation(&store, &store.read(), &alias, p.clone()).unwrap();
        commit_receipt(&store, &store.read(), &alias, &receipt(&p, false)).unwrap();
    }
    let before = store.read();
    assert!(
        commit_presentation(&store, &before, "alias-17", presentation("closed-17", 30)).is_err()
    );
    assert_eq!(before, store.read());
    assert!(
        before
            .journal("alias-0")
            .unwrap()
            .seen
            .contains(&"closed-0".into())
    );
}

#[test]
fn changing_policy_identity_can_create_an_independent_fresh_gate() {
    // Boundary witness: key derivation cannot enforce the Host's migration policy.
    // No deployed Host or external send is involved.
    let old = Store::new(SharedCheckoutState::fresh(identity()));
    let new_policy = CheckoutCoordinationIdentity::enrolled(
        "registry",
        "canonical-open-1",
        "agent-1",
        "policy-2",
    )
    .unwrap();
    assert_ne!(identity().storage_key(), new_policy.storage_key());
    let new = Store::new(SharedCheckoutState::fresh(new_policy));
    let same = presentation("closed-A", 10);
    assert_eq!(
        commit_presentation(&old, &old.read(), "A", same.clone()).unwrap(),
        CoordinationCommit::Applied
    );
    assert_eq!(
        commit_presentation(&new, &new.read(), "B", same).unwrap(),
        CoordinationCommit::Applied
    );
    assert!(old.read().pending().is_some());
    assert!(new.read().pending().is_some());
}

fn restored(
    value: &serde_json::Value,
) -> Result<SharedCheckoutState, cedar_poo_commerce::coordination::CoordinationError> {
    SharedCheckoutState::restore_snapshot(&serde_json::to_vec(value).unwrap(), &identity())
}
fn two_journal_snapshot() -> serde_json::Value {
    let store = Store::new(SharedCheckoutState::fresh(identity()));
    let a = presentation("closed-A", 10);
    commit_presentation(&store, &store.read(), "A", a.clone()).unwrap();
    commit_receipt(&store, &store.read(), "A", &receipt(&a, false)).unwrap();
    commit_presentation(&store, &store.read(), "B", presentation("closed-B", 11)).unwrap();
    serde_json::from_slice(&store.read().snapshot_bytes()).unwrap()
}

#[test]
fn snapshots_round_trip_all_selected_lifecycle_states_and_resume_cas() {
    let store = Store::new(SharedCheckoutState::fresh(identity()));
    let check = |state: SharedCheckoutState| {
        let copy =
            SharedCheckoutState::restore_snapshot(&state.snapshot_bytes(), &identity()).unwrap();
        assert_eq!(copy, state);
        copy
    };
    check(store.read());
    let a = presentation("closed-A", 10);
    commit_presentation(&store, &store.read(), "A", a.clone()).unwrap();
    let pending = check(store.read());
    commit_receipt(&store, &pending, "A", &receipt(&a, false)).unwrap();
    let rejected = check(store.read());
    let b = presentation("closed-B", 11);
    commit_presentation(&store, &rejected, "B", b.clone()).unwrap();
    let retried = check(store.read());
    commit_receipt(&store, &retried, "B", &receipt(&b, true)).unwrap();
    let spent = check(store.read());
    assert!(commit_presentation(&store, &spent, "C", presentation("closed-C", 12)).is_err());
    let other =
        CheckoutCoordinationIdentity::enrolled("registry", "other", "agent-1", "policy-1").unwrap();
    assert!(SharedCheckoutState::restore_snapshot(&spent.snapshot_bytes(), &other).is_err());
}

#[test]
fn snapshot_wire_rejects_duplicates_schema_confusion_and_unbounded_input() {
    let base = two_journal_snapshot();
    for change in [
        ("version", json!("future")),
        ("state", json!(null)),
        ("unknown", json!(1)),
    ] {
        let mut bad = base.clone();
        bad[change.0] = change.1;
        assert!(restored(&bad).is_err());
    }
    for revision in [json!(-1), json!(3.0), json!("3")] {
        let mut bad = base.clone();
        bad["state"]["revision"] = revision;
        assert!(restored(&bad).is_err());
    }
    let mut omitted = base.clone();
    omitted["state"]
        .as_object_mut()
        .unwrap()
        .remove("pending_journal");
    assert!(restored(&omitted).is_err());
    let mut omitted = base.clone();
    omitted["state"]["journals"]["A"]
        .as_object_mut()
        .unwrap()
        .remove("pending");
    assert!(restored(&omitted).is_err());
    let original = base.to_string();
    let duplicate = original.replacen(
        "\"A\":",
        &format!("\"\\u0041\":{},\"A\":", base["state"]["journals"]["A"]),
        1,
    );
    assert!(SharedCheckoutState::restore_snapshot(duplicate.as_bytes(), &identity()).is_err());
    let duplicate = original.replacen("\"revision\":3", "\"revision\":3,\"revision\":3", 1);
    assert_ne!(duplicate, original);
    assert!(SharedCheckoutState::restore_snapshot(duplicate.as_bytes(), &identity()).is_err());
    assert!(
        SharedCheckoutState::restore_snapshot(format!("{original} true").as_bytes(), &identity())
            .is_err()
    );
    assert!(SharedCheckoutState::restore_snapshot(&vec![b' '; 524_289], &identity()).is_err());
    let mut deep = json!(0);
    for _ in 0..14 {
        deep = json!([deep]);
    }
    assert!(restored(&deep).is_err());
}

#[test]
fn restored_gate_journals_and_transition_counters_cannot_disagree() {
    let base = two_journal_snapshot();
    for change in 0..11 {
        let mut bad = base.clone();
        let state = &mut bad["state"];
        match change {
            0 => state["revision"] = json!(2),
            1 => state["pending_journal"] = json!("A"),
            2 => state["spent"] = json!(true),
            3 => state["journals"]["A"]["openMandateScope"] = json!("other"),
            4 => state["journals"]["A"]["revision"] = json!(u64::MAX),
            5 => state["journals"]["B"]["seen"] = json!(["closed-A"]),
            6 => state["journals"]["B"]["pending"]["reference"] = json!("old"),
            7 => state["journals"]["B"]["pending"]["merchantIssuer"] = json!(""),
            8 => state["journals"]["A"]["spent"] = json!(true),
            9 => state["journals"]["A"]["seen"] = json!([]),
            _ => state["journals"]["A"]["seen"] = json!(["closed-A", "closed-A"]),
        }
        assert!(restored(&bad).is_err(), "mutation {change}");
    }
    let mut bad = base.clone();
    bad["state"]["journals"]["A"]["pending"] = base["state"]["journals"]["B"]["pending"].clone();
    bad["state"]["journals"]["A"]["pending"]["reference"] = json!("closed-A");
    bad["state"]["journals"]["A"]["revision"] = json!(1);
    bad["state"]["revision"] = json!(2);
    assert!(restored(&bad).is_err());
}

#[test]
fn restoration_limits_preserve_maximum_tombstones_and_do_not_prove_authenticity() {
    let fresh = SharedCheckoutState::fresh(identity());
    // Even a structurally fresh snapshot restores: trusted-head continuity is an
    // external prerequisite, not something this structural parser can establish.
    assert_eq!(
        SharedCheckoutState::restore_snapshot(&fresh.snapshot_bytes(), &identity()).unwrap(),
        fresh
    );
    let mut value = two_journal_snapshot();
    let mut ledger = value["state"]["journals"]["A"].clone();
    let references: Vec<_> = (0..256)
        .map(|n| format!("{n:03}{}", "\0".repeat(253)))
        .collect();
    ledger["seen"] = json!(references);
    ledger["revision"] = json!(512);
    value["state"]["journals"] = json!({"A":ledger});
    value["state"]["pending_journal"] = json!(null);
    value["state"]["revision"] = json!(512);
    let boundary = restored(&value).unwrap();
    assert!(boundary.snapshot_bytes().len() <= 524_288);
    assert_eq!(
        SharedCheckoutState::restore_snapshot(&boundary.snapshot_bytes(), &identity()).unwrap(),
        boundary
    );
    value["state"]["journals"]["A"]["seen"]
        .as_array_mut()
        .unwrap()
        .push(json!("extra"));
    value["state"]["journals"]["A"]["revision"] = json!(514);
    value["state"]["revision"] = json!(514);
    assert!(restored(&value).is_err());
    let mut value = two_journal_snapshot();
    let ledger = value["state"]["journals"]["A"].clone();
    let entries: serde_json::Map<_, _> = (0..17)
        .map(|n| {
            let mut item = ledger.clone();
            item["seen"] = json!([format!("ref-{n}")]);
            (format!("alias-{n}"), item)
        })
        .collect();
    value["state"]["journals"] = entries.into();
    value["state"]["pending_journal"] = json!(null);
    value["state"]["revision"] = json!(34);
    assert!(restored(&value).is_err());
}

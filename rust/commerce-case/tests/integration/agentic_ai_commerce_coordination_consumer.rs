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

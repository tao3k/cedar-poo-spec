use super::{OperationError, OperationId, OperationLedger};

#[test]
fn retry_with_new_approval_cannot_reopen_the_same_operation() {
    let mut ledger = OperationLedger::default();
    let original = OperationId::from("release-one");
    ledger.admit(&original, &"same-payload".to_owned()).unwrap();
    assert_eq!(
        ledger.check(&original, &"same-payload".to_owned()),
        Err(OperationError::AlreadyAdmitted)
    );
    assert_eq!(
        ledger.check(&original, &"changed-payload".to_owned()),
        Err(OperationError::EffectMismatch)
    );
    ledger
        .admit(
            &OperationId::from("release-two"),
            &"same-payload".to_owned(),
        )
        .unwrap();
    assert_eq!(
        ledger.admitted(&OperationId::from("release-two")),
        Some(&"same-payload".to_owned())
    );
}

#[test]
fn empty_operation_identity_fails_closed() {
    let ledger = OperationLedger::<String>::default();
    assert_eq!(
        ledger.check(&OperationId::from(""), &"payload".into()),
        Err(OperationError::EmptyId)
    );
}

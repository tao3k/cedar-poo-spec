use super::{AuthorityError, AuthorityGrant, AuthorityId, AuthorityLedger};

fn grant(id: &str, effect: &str, max_uses: u64) -> AuthorityGrant<String> {
    AuthorityGrant {
        id: AuthorityId::from(id),
        effect: effect.into(),
        max_uses,
        used: 0,
    }
}

#[test]
fn exact_effect_and_stable_id_are_consumed() {
    let mut ledger = AuthorityLedger {
        grants: vec![
            grant("first", "effect-a", 1),
            grant("second", "effect-a", 1),
        ],
    };
    assert_eq!(
        ledger.check(&"first".into(), &"effect-b".into()),
        Err(AuthorityError::EffectMismatch)
    );
    ledger.consume(&"first".into(), &"effect-a".into()).unwrap();
    assert_eq!(
        ledger.check(&"first".into(), &"effect-a".into()),
        Err(AuthorityError::Exhausted)
    );
    assert_eq!(ledger.used(&"first".into()), Ok(1));
    ledger
        .consume(&"second".into(), &"effect-a".into())
        .unwrap();
    assert_eq!(ledger.used(&"second".into()), Ok(1));
}

#[test]
fn missing_duplicate_and_zero_use_grants_fail_closed() {
    let mut ledger = AuthorityLedger {
        grants: vec![grant("same", "effect", 1), grant("same", "effect", 1)],
    };
    assert_eq!(
        ledger.check(&"absent".into(), &"effect".into()),
        Err(AuthorityError::Missing)
    );
    assert_eq!(
        ledger.consume(&"same".into(), &"effect".into()),
        Err(AuthorityError::Duplicate)
    );
    assert_eq!(ledger.grants.iter().map(|grant| grant.used).sum::<u64>(), 0);
    let zero = AuthorityLedger {
        grants: vec![grant("zero", "effect", 0)],
    };
    assert_eq!(
        zero.check(&"zero".into(), &"effect".into()),
        Err(AuthorityError::Exhausted)
    );
}

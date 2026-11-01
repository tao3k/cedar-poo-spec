use crate::EntitySourceJson;
use std::ops::Deref;

#[test]
fn shared_encoding_does_not_change_value_equality_or_public_wire() {
    let value = serde_json::json!([{"uid":{"type":"User","id":"雪"},"attrs":{},"parents":[]}]);
    let a: EntitySourceJson = serde_json::from_value(value.clone()).unwrap();
    let b: EntitySourceJson = serde_json::from_value(value.clone()).unwrap();
    let shared = a.clone();
    let wire = a.source_identity().unwrap();
    assert_eq!(a, b, "a memoized encoding is not entity value state");
    assert!(std::ptr::eq(a.deref(), shared.deref()));
    assert!(std::ptr::eq(wire, shared.source_identity().unwrap()));
    assert_eq!(serde_json::to_value(&a).unwrap(), value);
    assert_eq!(wire, serde_json::to_string(&value).unwrap());
    assert_eq!(wire, b.source_identity().unwrap());
}

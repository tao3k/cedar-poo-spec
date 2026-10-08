use super::{Mode, TokenLineage, TokenProfile};

fn profile<'a>(mode: Mode, scope: &'a str, wrapping_version: &'a str) -> TokenProfile<'a> {
    TokenProfile {
        mode,
        scope,
        lineage: TokenLineage {
            tenant: "tenant-a",
            key_domain: "study-key",
            token_key_version: "key-1",
            transform_version: "normalization-1",
            wrapping_version,
        },
    }
}

#[test]
fn mode_capabilities_match_lean_catalog() {
    assert_eq!(Mode::AesSiv.label(), "aes-siv");
    assert!(Mode::AesSiv.reversible());
    assert!(Mode::AesSiv.linkable());
    assert!(!Mode::AesGcm.linkable());
    assert!(!Mode::HmacSha256.reversible());
    assert!(Mode::HmacSha256.linkable());
}

#[test]
fn recipe_equality_ignores_wrapper_rotation_but_requires_scope() {
    let first = profile(Mode::AesSiv, "study-a", "wrapping-1");
    let rewrapped = profile(Mode::AesSiv, "study-a", "wrapping-2");
    let other_scope = profile(Mode::AesSiv, "study-b", "wrapping-1");
    assert!(first.same_recipe(&rewrapped));
    assert!(!first.same_recipe(&other_scope));
}

#[test]
fn hmac_key_reuse_across_scopes_is_visible() {
    let first = profile(Mode::HmacSha256, "study-a", "wrapping-1");
    let second = profile(Mode::HmacSha256, "study-b", "wrapping-2");
    assert!(first.hmac_key_reuse_across_scopes(&second));
    assert!(!first.hmac_key_reuse_across_scopes(&first));
}

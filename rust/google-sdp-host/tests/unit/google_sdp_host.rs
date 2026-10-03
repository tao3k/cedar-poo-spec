use super::{InMemoryGoogleSdpHost, TokenProvenance};

fn provenance(dataset: &str) -> TokenProvenance {
    TokenProvenance {
        dataset: dataset.into(),
        tenant: "hospital".into(),
        context: "hospital-a".into(),
        key_domain: "hospital-key".into(),
        token_key_version: "dek-v1".into(),
        transform_version: "patient-id-v1".into(),
    }
}

#[test]
fn issued_tokens_bind_dataset_and_recipe_without_blocking_cross_dataset_joins() {
    let mut host = InMemoryGoogleSdpHost::new("policy-digest".into(), 1);
    let hospital = provenance("hospital-patients");
    let research = provenance("research-patients");
    let token = "synthetic-ciphertext";

    assert!(!host.token_issued_for(token, &hospital));
    host.catalog_token(token, hospital.clone());
    assert!(host.token_issued_for(token, &hospital));
    assert!(!host.token_issued_for(token, &research));

    // The same deterministic token may occur in two datasets sharing a recipe.
    assert!(host.token_compatible_with_catalog(token, &research));
    host.catalog_token(token, research.clone());
    assert!(host.token_issued_for(token, &research));

    for incompatible in [
        TokenProvenance {
            tenant: "other-hospital".into(),
            ..hospital.clone()
        },
        TokenProvenance {
            context: "study-b".into(),
            ..hospital.clone()
        },
        TokenProvenance {
            key_domain: "other-key".into(),
            ..hospital.clone()
        },
        TokenProvenance {
            token_key_version: "dek-v2".into(),
            ..hospital.clone()
        },
        TokenProvenance {
            transform_version: "patient-id-v2".into(),
            ..hospital.clone()
        },
    ] {
        assert!(!host.token_issued_for(token, &incompatible));
        assert!(!host.token_compatible_with_catalog(token, &incompatible));
    }
}

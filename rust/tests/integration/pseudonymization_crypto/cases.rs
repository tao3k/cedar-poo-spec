use aes_gcm::{
    Aes256Gcm, Nonce,
    aead::{Aead, KeyInit as _},
};
use aes_siv::siv::Aes256Siv;
use cedar_poo_bridge::google_sdp::{SelectedTabularInput, TabularAesSiv, WrappedKeyBinding};
use hmac::{Hmac, Mac};
use sha2::Sha256;

type TabularFixture = SelectedTabularInput;

const PATIENT_ID: &[u8] = b"synthetic-patient-0001";

fn siv_token(key: &[u8; 64], scope: &str, value: &[u8]) -> Vec<u8> {
    Aes256Siv::new_from_slice(key)
        .expect("test key length")
        .encrypt([scope.as_bytes()], value)
        .expect("synthetic value is long enough")
}

fn hmac_token(key: &[u8], value: &[u8]) -> Vec<u8> {
    let mut mac = <Hmac<Sha256> as hmac::KeyInit>::new_from_slice(key).expect("test key length");
    mac.update(value);
    mac.finalize().into_bytes().to_vec()
}

#[test]
fn aes_siv_context_and_key_lineage_change_actual_tokens() {
    let data_key = [7_u8; 64];
    let rotated_data_key = [8_u8; 64];
    let local = siv_token(&data_key, "study-one", PATIENT_ID);
    assert_eq!(local, siv_token(&data_key, "study-one", PATIENT_ID));
    assert_ne!(local, siv_token(&data_key, "study-two", PATIENT_ID));
    assert_ne!(local, siv_token(&rotated_data_key, "study-one", PATIENT_ID));
    assert_ne!(local, siv_token(&data_key, "study-one", b"PATIENT-0001"));

    // Rewrapping the same data key changes no AES-SIV input.
    let _new_wrapping_version = "kek-v2";
    assert_eq!(local, siv_token(&data_key, "study-one", PATIENT_ID));
    assert_eq!(
        Aes256Siv::new_from_slice(&data_key)
            .unwrap()
            .decrypt([b"study-one".as_slice()], &local)
            .unwrap(),
        PATIENT_ID
    );
    assert!(
        Aes256Siv::new_from_slice(&data_key)
            .unwrap()
            .decrypt([b"study-two".as_slice()], &local)
            .is_err()
    );
}

#[test]
fn lean_selected_table_fields_are_actual_siv_inputs() {
    let fixture: TabularFixture = serde_json::from_str(include_str!(
        "../../../../Examples/Health/Pseudonymization/Fixtures/tabular-aes-siv.json"
    ))
    .unwrap();
    assert_eq!(fixture.dataset, "hospital-patients");
    assert_eq!(fixture.value_field, "patient_id");
    assert_eq!(fixture.context_field, "tenant_scope");
    assert_eq!(fixture.key_domain, "key-a");
    assert_eq!(fixture.token_key_version, "dek-v1");
    assert_eq!(fixture.transform_version, "patient-id-v1");
    assert_eq!(fixture.wrapping_version, "kek-v1");
    assert!(fixture.surrogate_info_type.is_none());

    let key = [7_u8; 64];
    let token = siv_token(&key, &fixture.context, fixture.value.as_bytes());
    assert_eq!(token, siv_token(&key, "hospital-a", PATIENT_ID));
    assert!(
        Aes256Siv::new_from_slice(&key)
            .unwrap()
            .decrypt([b"study-two".as_slice()], &token)
            .is_err()
    );
}

#[test]
fn lean_selected_table_fields_build_google_sdp_request_with_bound_key_lineage() {
    let fixture: TabularFixture = serde_json::from_str(include_str!(
        "../../../../Examples/Health/Pseudonymization/Fixtures/tabular-aes-siv.json"
    ))
    .unwrap();
    let binding = WrappedKeyBinding {
        key_domain: fixture.key_domain.clone(),
        token_key_version: fixture.token_key_version.clone(),
        wrapping_version: fixture.wrapping_version.clone(),
        kms_key_name:
            "projects/synthetic-project/locations/us-central1/keyRings/test/cryptoKeys/dek".into(),
        wrapped_key_base64: "c3ludGhldGlj".into(),
    };
    let plan = TabularAesSiv::from_selected(
        "projects/synthetic-project/locations/us-central1".into(),
        fixture,
        binding,
    )
    .unwrap();
    let body: serde_json::Value =
        serde_json::from_slice(&plan.deidentify_body().unwrap().to_json_bytes().unwrap()).unwrap();
    assert_eq!(body["item"]["table"]["headers"][0]["name"], "patient_id");
    assert_eq!(
        body["item"]["table"]["rows"][0]["values"][1]["stringValue"],
        "hospital-a"
    );
    assert_eq!(
        body["deidentifyConfig"]["recordTransformations"]["fieldTransformations"][0]["primitiveTransformation"]
            ["cryptoDeterministicConfig"]["context"]["name"],
        "tenant_scope"
    );
}

#[test]
fn hmac_has_no_context_tweak_and_requires_key_separation() {
    let shared_key = [3_u8; 32];
    let separate_key = [4_u8; 32];
    let hospital_token = hmac_token(&shared_key, PATIENT_ID);
    let unsafe_study_token = hmac_token(&shared_key, PATIENT_ID);
    assert_eq!(hospital_token, unsafe_study_token);
    assert_ne!(hospital_token, hmac_token(&separate_key, PATIENT_ID));
}

#[test]
fn gcm_nonce_changes_ciphertext_and_is_required_for_recovery() {
    let cipher = Aes256Gcm::new_from_slice(&[9_u8; 32]).unwrap();
    let first = Nonce::from_slice(&[1_u8; 12]);
    let second = Nonce::from_slice(&[2_u8; 12]);
    let ciphertext = cipher.encrypt(first, PATIENT_ID).unwrap();
    assert_ne!(ciphertext, cipher.encrypt(second, PATIENT_ID).unwrap());
    assert_eq!(
        cipher.decrypt(first, ciphertext.as_ref()).unwrap(),
        PATIENT_ID
    );
    assert!(cipher.decrypt(second, ciphertext.as_ref()).is_err());
}

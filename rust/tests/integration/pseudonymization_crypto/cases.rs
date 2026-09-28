use aes_gcm::{
    Aes256Gcm, Nonce,
    aead::{Aead, KeyInit as _},
};
use aes_siv::siv::Aes256Siv;
use hmac::{Hmac, Mac};
use sha2::Sha256;

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

//! Synthetic local execution after official Cedar replay. This is not a
//! Google provider receipt or a durable Host transaction.

use aes_siv::{KeyInit, siv::Aes256Siv};
use cedar_poo_runtime::{ValidatedManifest, replay_validated_manifest};
use hmac::{Hmac, Mac};
use serde::Deserialize;
use serde_json::json;
use sha2::{Digest, Sha256};
use std::{env, fs, process};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct TabularInput {
    dataset: String,
    value_field: String,
    context_field: String,
    value: String,
    context: String,
    key_domain: String,
    token_key_version: String,
    transform_version: String,
    wrapping_version: String,
    surrogate_info_type: Option<String>,
}

fn hex(bytes: impl AsRef<[u8]>) -> String {
    bytes
        .as_ref()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

fn run() -> Result<(), String> {
    let mut args = env::args().skip(1);
    let manifest_path = args.next().ok_or("expected validated manifest path")?;
    let input_path = args.next().ok_or("expected tabular input path")?;
    if args.next().is_some() {
        return Err("expected exactly two paths".into());
    }
    let manifest: ValidatedManifest = serde_json::from_str(
        &fs::read_to_string(manifest_path).map_err(|error| error.to_string())?,
    )
    .map_err(|error| error.to_string())?;
    let input: TabularInput =
        serde_json::from_str(&fs::read_to_string(input_path).map_err(|error| error.to_string())?)
            .map_err(|error| error.to_string())?;

    let mut cases = manifest
        .cases
        .iter()
        .filter(|case| case.name == "hospital-tokenize");
    let case = cases.next().ok_or("missing hospital-tokenize case")?;
    if cases.next().is_some() || case.revision != "HospitalSiv" {
        return Err("ambiguous or ungoverned hospital-tokenize case".into());
    }
    let dataset_uid = format!("Dataset::\"{}\"", input.dataset);
    let target_id = case
        .request
        .context
        .pointer("/targetDataset/__entity/id")
        .and_then(serde_json::Value::as_str);
    let dataset_entity = case.entities.as_array().and_then(|entities| {
        entities.iter().find(|entity| {
            entity
                .pointer("/uid/type")
                .and_then(serde_json::Value::as_str)
                == Some("Dataset")
                && entity
                    .pointer("/uid/id")
                    .and_then(serde_json::Value::as_str)
                    == Some(input.dataset.as_str())
        })
    });
    let attrs = dataset_entity
        .and_then(|entity| entity.get("attrs"))
        .ok_or("missing admitted dataset entity")?;
    let attr = |name: &str| attrs.get(name).and_then(serde_json::Value::as_str);
    if case.request.resource != dataset_uid
        || target_id != Some(input.dataset.as_str())
        || case
            .request
            .context
            .get("requestedKeyVersion")
            .and_then(serde_json::Value::as_str)
            != Some(input.token_key_version.as_str())
        || attr("mode") != Some("aes-siv")
        || attr("scope") != Some(input.context.as_str())
        || attr("keyDomain") != Some(input.key_domain.as_str())
        || attr("tokenKeyVersion") != Some(input.token_key_version.as_str())
        || attr("transformVersion") != Some(input.transform_version.as_str())
        || attr("wrappingVersion") != Some(input.wrapping_version.as_str())
    {
        return Err("tabular input differs from the admitted Cedar entity or request".into());
    }
    if input.value.is_empty()
        || input.value_field.is_empty()
        || input.context_field.is_empty()
        || input.value_field == input.context_field
        || input.surrogate_info_type.is_some()
    {
        return Err("invalid local structured AES-SIV input".into());
    }

    let reidentify_case = manifest
        .cases
        .iter()
        .find(|case| case.name == "steward-reidentify" && case.revision == "HospitalSiv")
        .ok_or("missing governed steward-reidentify case")?;
    if reidentify_case.request.resource != case.request.resource
        || reidentify_case.request.context.get("requestedKeyVersion")
            != case.request.context.get("requestedKeyVersion")
        || reidentify_case.request.context.get("targetDataset")
            != case.request.context.get("targetDataset")
    {
        return Err("re-identification request targets a different token domain".into());
    }
    let receipts = replay_validated_manifest(&manifest)?;
    let mut selected = receipts
        .iter()
        .filter(|receipt| receipt.replay.case_name == "hospital-tokenize");
    let replay = selected
        .next()
        .ok_or("missing hospital-tokenize Cedar replay")?;
    if selected.next().is_some() || !replay.replay.error_free_allow {
        return Err("hospital-tokenize replay is ambiguous or denied".into());
    }
    let mut recovery = receipts
        .iter()
        .filter(|receipt| receipt.replay.case_name == "steward-reidentify");
    let recovery_replay = recovery
        .next()
        .ok_or("missing steward-reidentify Cedar replay")?;
    if recovery.next().is_some() || !recovery_replay.replay.error_free_allow {
        return Err("steward-reidentify replay is ambiguous or denied".into());
    }
    let key = [7_u8; 64];
    let token = Aes256Siv::new_from_slice(&key)
        .map_err(|error| error.to_string())?
        .encrypt([input.context.as_bytes()], input.value.as_bytes())
        .map_err(|error| error.to_string())?;
    let recovered = Aes256Siv::new_from_slice(&key)
        .map_err(|error| error.to_string())?
        .decrypt([input.context.as_bytes()], &token)
        .map_err(|error| error.to_string())?;
    if recovered != input.value.as_bytes() {
        return Err("local AES-SIV round trip changed the selected value".into());
    }
    if Aes256Siv::new_from_slice(&key)
        .map_err(|error| error.to_string())?
        .decrypt([b"wrong-context".as_slice()], &token)
        .is_ok()
    {
        return Err("local AES-SIV accepted a different context".into());
    }
    let mut input_mac = <Hmac<Sha256> as hmac::KeyInit>::new_from_slice(&[5_u8; 32])
        .map_err(|error| error.to_string())?;
    input_mac.update(input.value.as_bytes());
    let result = json!({
        "kind": "synthetic-local-aes-siv",
        "caseName": replay.replay.case_name,
        "decision": replay.replay.decision,
        "reidentifyDecision": recovery_replay.replay.decision,
        "reidentifyRequestSha256": recovery_replay.replay.request_sha256,
        "schemaSha256": replay.schema_sha256,
        "policiesSha256": replay.replay.policies_sha256,
        "entitiesSha256": replay.replay.entities_sha256,
        "requestSha256": replay.replay.request_sha256,
        "dataset": input.dataset,
        "valueField": input.value_field,
        "contextField": input.context_field,
        "context": input.context,
        "keyDomain": input.key_domain,
        "tokenKeyVersion": input.token_key_version,
        "transformVersion": input.transform_version,
        "wrappingVersion": input.wrapping_version,
        "inputHmacSha256": hex(input_mac.finalize().into_bytes()),
        "tokenSha256": hex(Sha256::digest(&token)),
        "tokenBytes": token.len(),
        "roundTripMatches": true
    });
    println!("{result}");
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        process::exit(1);
    }
}

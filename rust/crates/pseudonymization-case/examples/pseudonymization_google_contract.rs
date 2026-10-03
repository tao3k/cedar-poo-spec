//! Offline Google SDP REST contract example. No provider call is made.

use cedar_poo_pseudonymization::google_sdp::{
    GoogleSdpResponse, SelectedTabularInput, TabularAesSiv, WrappedKeyBinding,
};
use serde_json::{Value, json};
use std::{env, fs, process};

fn read_json(path: &str) -> Result<Vec<u8>, String> {
    fs::read(path).map_err(|error| error.to_string())
}

fn run() -> Result<(), String> {
    let mut args = env::args().skip(1);
    let input_path = args.next().ok_or("expected selected Lean fixture")?;
    let token_path = args
        .next()
        .ok_or("expected synthetic de-identify response")?;
    let recovery_path = args
        .next()
        .ok_or("expected synthetic re-identify response")?;
    if args.next().is_some() {
        return Err("expected exactly three fixture paths".into());
    }
    let selected_bytes = read_json(&input_path)?;
    let selected: SelectedTabularInput =
        serde_json::from_slice(&selected_bytes).map_err(|error| error.to_string())?;
    let expected_value_field = selected.value_field.clone();
    let expected_context_field = selected.context_field.clone();
    let expected_context = selected.context.clone();
    let same_input: SelectedTabularInput =
        serde_json::from_slice(&selected_bytes).map_err(|error| error.to_string())?;
    let mismatched_key = WrappedKeyBinding {
        key_domain: same_input.key_domain.clone(),
        token_key_version: "dek-v2".into(),
        wrapping_version: same_input.wrapping_version.clone(),
        kms_key_name:
            "projects/synthetic-project/locations/us-central1/keyRings/test/cryptoKeys/dek".into(),
        wrapped_key_base64: "c3ludGhldGlj".into(),
    };
    if TabularAesSiv::from_selected(
        "projects/synthetic-project/locations/us-central1".into(),
        same_input,
        mismatched_key,
    )
    .is_ok()
    {
        return Err("Google request accepted a different token key version".into());
    }
    let binding = WrappedKeyBinding {
        key_domain: selected.key_domain.clone(),
        token_key_version: selected.token_key_version.clone(),
        wrapping_version: selected.wrapping_version.clone(),
        kms_key_name:
            "projects/synthetic-project/locations/us-central1/keyRings/test/cryptoKeys/dek".into(),
        wrapped_key_base64: "c3ludGhldGlj".into(),
    };
    let plan = TabularAesSiv::from_selected(
        "projects/synthetic-project/locations/us-central1".into(),
        selected,
        binding,
    )?;
    let deidentify: Value = serde_json::from_slice(&plan.deidentify_body()?.to_json_bytes()?)
        .map_err(|error| error.to_string())?;
    let field = deidentify
        .pointer("/deidentifyConfig/recordTransformations/fieldTransformations/0")
        .ok_or("missing Google record transformation")?;
    if field["fields"][0]["name"] != expected_value_field
        || field["primitiveTransformation"]["cryptoDeterministicConfig"]["context"]["name"]
            != expected_context_field
        || deidentify["item"]["table"]["rows"][0]["values"][1]["stringValue"] != expected_context
    {
        return Err("Google request differs from the selected Lean columns".into());
    }
    let token_bytes = read_json(&token_path)?;
    let token_response = GoogleSdpResponse::from_json_bytes(&token_bytes)?;
    let checked_token = plan.check_deidentify_response(&token_response)?;
    let reidentify: Value = serde_json::from_slice(
        &plan
            .reidentify_body(&checked_token.value)?
            .to_json_bytes()?,
    )
    .map_err(|error| error.to_string())?;
    if reidentify["reidentifyConfig"] != deidentify["deidentifyConfig"]
        || reidentify["item"]["table"]["rows"][0]["values"][0]["stringValue"] != checked_token.value
    {
        return Err("Google re-identification request changed the token recipe".into());
    }
    let recovery_bytes = read_json(&recovery_path)?;
    let recovery_response = GoogleSdpResponse::from_json_bytes(&recovery_bytes)?;
    let checked_recovery =
        plan.check_reidentify_response(&checked_token.value, &recovery_response)?;
    let mut changed_context: Value =
        serde_json::from_slice(&token_bytes).map_err(|error| error.to_string())?;
    changed_context["item"]["table"]["rows"][0]["values"][1]["stringValue"] =
        json!(format!("{expected_context}-other"));
    let rejected = GoogleSdpResponse::from_json_bytes(
        &serde_json::to_vec(&changed_context).map_err(|error| error.to_string())?,
    )?;
    if plan.check_deidentify_response(&rejected).is_ok() {
        return Err("Google response with changed context was accepted".into());
    }
    changed_context["item"]["table"]["rows"][0]["values"][1]["stringValue"] =
        json!(expected_context);
    changed_context["item"]["table"]["rows"][0]["values"][0]["stringValue"] = json!("not-base64");
    let malformed = GoogleSdpResponse::from_json_bytes(
        &serde_json::to_vec(&changed_context).map_err(|error| error.to_string())?,
    )?;
    if plan.check_deidentify_response(&malformed).is_ok() {
        return Err("Google response with malformed token was accepted".into());
    }
    println!(
        "{}",
        json!({
            "kind": "offline-google-sdp-rest-contract",
            "providerCalled": false,
            "deidentifyEndpoint": plan.endpoint(false)?,
            "reidentifyEndpoint": plan.endpoint(true)?,
            "deidentifyRequestSha256": checked_token.request_sha256,
            "deidentifyResponseSha256": checked_token.response_sha256,
            "reidentifyRequestSha256": checked_recovery.request_sha256,
            "reidentifyResponseSha256": checked_recovery.response_sha256,
            "contextSwapRejected": true,
            "keyLineageMismatchRejected": true,
            "malformedTokenRejected": true,
            "syntheticRoundTripShapeChecked": true
        })
    );
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        process::exit(1);
    }
}

use super::{
    GoogleSdpResponse, SelectedTabularInput, SurrogateInfoType, TabularAesSiv, WrappedKeyBinding,
};
use serde_json::json;

const TOKEN: &str = "c3ludGhldGljLWNpcGhlcnRleHQ=";

fn plan() -> TabularAesSiv {
    TabularAesSiv {
        parent: "projects/synthetic-project/locations/us-central1".into(),
        value_field: "patient_id".into(),
        context_field: "tenant_scope".into(),
        value: "synthetic-patient-0001".into(),
        context: "hospital-a".into(),
        kms_key_name:
            "projects/synthetic-project/locations/us-central1/keyRings/test/cryptoKeys/dek".into(),
        wrapped_key_base64: "c3ludGhldGlj".into(),
        surrogate_info_type: None,
    }
}

fn response(value: &str, context: &str) -> GoogleSdpResponse {
    GoogleSdpResponse {
        body: json!({
            "item": {"table": {
                "headers": [{"name": "patient_id"}, {"name": "tenant_scope"}],
                "rows": [{"values": [
                    {"stringValue": value}, {"stringValue": context}
                ]}]
            }},
            "overview": {"transformationSummaries": [{
                "field": {"name": "patient_id"},
                "results": [{"count": "1", "code": "SUCCESS"}]
            }]}
        }),
    }
}

#[test]
fn request_uses_google_record_transformations_and_context_column() {
    let plan = plan();
    let body = plan.deidentify_body().unwrap().body;
    assert_eq!(
        body["item"]["table"]["rows"][0]["values"][0]["stringValue"],
        plan.value
    );
    assert_eq!(
        body["deidentifyConfig"]["recordTransformations"]["fieldTransformations"][0]["fields"][0]["name"],
        plan.value_field
    );
    assert_eq!(
        body["deidentifyConfig"]["recordTransformations"]["fieldTransformations"][0]["primitiveTransformation"]
            ["cryptoDeterministicConfig"]["context"]["name"],
        plan.context_field
    );
    assert_eq!(
        body["deidentifyConfig"]["recordTransformations"]["fieldTransformations"][0]["primitiveTransformation"]
            ["cryptoDeterministicConfig"]["cryptoKey"]["kmsWrapped"]["cryptoKeyName"],
        plan.kms_key_name
    );
    assert_eq!(
        plan.endpoint(false).unwrap(),
        "https://dlp.googleapis.com/v2/projects/synthetic-project/locations/us-central1/content:deidentify"
    );
    let reverse = plan.reidentify_body(TOKEN).unwrap().body;
    assert_eq!(
        reverse["item"]["table"]["rows"][0]["values"][0]["stringValue"],
        TOKEN
    );
    assert_eq!(reverse["reidentifyConfig"], body["deidentifyConfig"]);
}

#[test]
fn response_check_requires_exact_cell_context_and_success_summary() {
    let plan = plan();
    let checked = plan
        .check_deidentify_response(&response(TOKEN, "hospital-a"))
        .unwrap();
    assert_eq!(checked.value, TOKEN);
    assert_eq!(checked.request_sha256.len(), 64);
    assert_eq!(checked.response_sha256.len(), 64);
    assert!(
        plan.check_deidentify_response(&response(TOKEN, "other-tenant"))
            .is_err()
    );
    assert!(
        plan.check_deidentify_response(&response(&plan.value, "hospital-a"))
            .is_err()
    );
    assert!(
        plan.check_deidentify_response(&response("not-base64", "hospital-a"))
            .is_err()
    );
    let mut bad = response(TOKEN, "hospital-a");
    bad.body["overview"]["transformationSummaries"][0]["results"][0]["code"] = json!("ERROR");
    assert!(plan.check_deidentify_response(&bad).is_err());
    assert!(
        plan.check_reidentify_response(TOKEN, &response(&plan.value, "hospital-a"))
            .is_ok()
    );
    assert!(
        plan.check_reidentify_response(TOKEN, &response("wrong-value", "hospital-a"))
            .is_err()
    );
}

#[test]
fn selected_lineage_and_wrapped_key_must_agree() {
    let selected: SelectedTabularInput = serde_json::from_value(json!({
        "dataset": "synthetic-dataset", "valueField": "patient_id",
        "contextField": "tenant_scope", "value": "synthetic-patient-0001",
        "context": "hospital-a", "keyDomain": "key-a",
        "tokenKeyVersion": "dek-v1", "transformVersion": "patient-id-v1",
        "wrappingVersion": "kek-v1", "surrogateInfoType": null
    }))
    .unwrap();
    let key = WrappedKeyBinding {
        key_domain: "key-a".into(),
        token_key_version: "dek-v2".into(),
        wrapping_version: "kek-v1".into(),
        kms_key_name: plan().kms_key_name,
        wrapped_key_base64: "c3ludGhldGlj".into(),
    };
    assert!(
        TabularAesSiv::from_selected(
            "projects/synthetic-project/locations/us-central1".into(),
            selected,
            key
        )
        .is_err()
    );
}

#[test]
fn surrogate_annotation_requires_the_declared_name_and_encoded_length() {
    let mut plan = plan();
    plan.surrogate_info_type = Some(SurrogateInfoType("HOSPITAL_TOKEN".into()));
    let tagged = format!("HOSPITAL_TOKEN({}):{TOKEN}", TOKEN.len());
    assert!(
        plan.check_deidentify_response(&response(&tagged, "hospital-a"))
            .is_ok()
    );
    assert!(
        plan.check_deidentify_response(&response(TOKEN, "hospital-a"))
            .is_err()
    );
    assert!(
        plan.check_deidentify_response(&response(
            &format!("HOSPITAL_TOKEN(1):{TOKEN}"),
            "hospital-a"
        ))
        .is_err()
    );
}

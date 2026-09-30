set shell := ["sh", "-eu", "-c"]
export CARGO_TARGET_DIR := "rust/target"

# Example recipes follow the source publisher or project area.
mod example 'Examples/Justfile'

default:
    @just --list

update:
    lake update

sync: update
    just check

# Inspect the public module inventory of the exact LeanPOO revision in Lake.
lean-poo-api:
    @rg -n '^import LeanPoo\.' .lake/packages/LeanPoo/LeanPoo.lean

# Search that same revision by declaration name or API term.
lean-poo-api-find query:
    @rg -n -i --glob '*.lean' -e {{quote(query)}} .lake/packages/LeanPoo/LeanPoo

build:
    lake build CedarPooSpec

build-examples: build
    lake build Examples

build-productions: build-examples
    lake build Productions

check-docs:
    emacs --batch -Q --eval '(progn (require (quote org-element)) (dolist (file (append (list "README.org") (directory-files-recursively "CedarPooSpec" "\\.org$") (directory-files-recursively "docs" "\\.org$") (directory-files-recursively "Examples" "\\.org$") (directory-files-recursively "Productions" "\\.org$") (directory-files-recursively "rust" "\\.org$") (directory-files-recursively "Tests" "\\.org$") (directory-files-recursively "Benchmarks" "\\.org$"))) (with-temp-buffer (insert-file-contents file) (org-mode) (org-element-parse-buffer))) (princ "ORG-OK"))'

check: check-tests check-docs
    just check-conformance
    just check-policy-reuse
    just example governance attested-views
    just check-cedar-language
    just check-mission-comparison
    just example aws financial-services lakehouse
    just example aws financial-services multi-account-banking
    just example aws financial-services claim-settlement
    just example aws financial-services reconciliation
    just example aws agentic-platform expense
    just example enterprise agent cross-agent-egress
    just example enterprise agent department-synthesis
    just example health prior-authorization
    just example health prior-authorization-internal-channels
    just example health pseudonymization
    just example health multi-hospital-ai
    just example health model-stewardship
    just example cloud pipeline-google-threat
    just example cloud pipeline-google-deployment
    just example cloud data-protection-google-sdp
    just example health my-health-record
    just example health australian-emr
    just example health united-states-payer
    just check-authorization-delta-proof

# Lean and ORG feedback without running every Cedar/Rust scenario.
check-quick: check-docs
    lake build CedarPooSpec Tests

check-lean: check-tests check-authorization-delta-proof check-policy-reuse

# Generate Lean inputs, replay Cedar decisions, then run Tests/Conformance.
check-conformance: check-replay-receipts check-schema-bound-receipts check-schema-bound-scenarios check-attested-schema-evolution check-authorization-delta check-payment-delta check-health-authorization-impact check-personnel-governance

check-personnel-governance:
    lake build Productions.Manifests Tests.Enterprise.Personnel.SourceCustody
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean source-custody-validated > .lake/build/source-custody-validated-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-validated-receipts < .lake/build/source-custody-validated-manifest.json > .lake/build/source-custody-validated-receipts.json
    jq -e -f Tests/Conformance/personnel-governance-receipts.jq .lake/build/source-custody-validated-receipts.json > /dev/null

check-tests: build-productions check-storage-effect-v1 check-protected-storage-v1 check-storage-profiles-v1 check-google-table-batch-v1
    lake build Tests

check-storage-effect-v1:
    lake env lean --run Productions/Data/StorageEffectFixtureMain.lean | diff -u Tests/Conformance/storage-effect-v1.json -

check-protected-storage-v1:
    lake env lean --run Productions/Data/ProtectedStorageFixtureMain.lean | diff -u Tests/Conformance/protected-storage-v1.json -

check-storage-profiles-v1:
    lake env lean --run Productions/Data/StorageProfileMatrixMain.lean | diff -u Tests/Conformance/storage-profiles-v1.json -

check-google-table-batch-v1:
    lake env lean --run Productions/Pseudonymization/TableBatchFixtureMain.lean | diff -u Tests/Conformance/google-table-batch-v1.json -

check-delta: check-authorization-delta check-payment-delta check-health-authorization-impact

check-replay-receipts: prepare-agent-payment-manifest
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-receipts < .lake/build/agent-payment-manifest.json > .lake/build/agent-payment-replay-receipts.json
    jq -e --slurpfile manifest .lake/build/agent-payment-manifest.json -f Tests/Conformance/agent-payment-replay-receipts.jq .lake/build/agent-payment-replay-receipts.json > /dev/null

prepare-agent-payment-validated-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean agent-payment-validated > .lake/build/agent-payment-validated-manifest.json

check-schema-bound-receipts: prepare-agent-payment-validated-manifest
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-validated-receipts < .lake/build/agent-payment-validated-manifest.json > .lake/build/agent-payment-validated-receipts.json
    jq -e --slurpfile manifest .lake/build/agent-payment-validated-manifest.json -f Tests/Conformance/agent-payment-validated-receipts.jq .lake/build/agent-payment-validated-receipts.json > /dev/null

prepare-schema-bound-scenarios: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean scope-pattern-validated > .lake/build/scope-pattern-validated-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean namespaced-enum-validated > .lake/build/namespaced-enum-validated-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean agent-data-flow-validated > .lake/build/agent-data-flow-validated-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean network-validated > .lake/build/network-validated-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean country-approval-validated > .lake/build/country-approval-validated-manifest.json

check-schema-bound-scenarios: prepare-schema-bound-scenarios
    jq -e -f Tests/Conformance/scope-pattern-validated-manifest.jq .lake/build/scope-pattern-validated-manifest.json > /dev/null
    jq -e -f Tests/Conformance/namespaced-enum-validated-manifest.jq .lake/build/namespaced-enum-validated-manifest.json > /dev/null
    jq -e -f Tests/Conformance/agent-data-flow-validated-manifest.jq .lake/build/agent-data-flow-validated-manifest.json > /dev/null
    jq -e -f Tests/Conformance/network-validated-manifest.jq .lake/build/network-validated-manifest.json > /dev/null
    jq -e -f Tests/Conformance/country-approval-validated-manifest.jq .lake/build/country-approval-validated-manifest.json > /dev/null
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-validated-receipts < .lake/build/agent-data-flow-validated-manifest.json > .lake/build/agent-data-flow-validated-receipts.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-validated-receipts < .lake/build/network-validated-manifest.json > .lake/build/network-validated-receipts.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-validated-receipts < .lake/build/country-approval-validated-manifest.json > .lake/build/country-approval-validated-receipts.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-validated-receipts < .lake/build/scope-pattern-validated-manifest.json > .lake/build/scope-pattern-validated-receipts.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-validated-receipts < .lake/build/namespaced-enum-validated-manifest.json > .lake/build/namespaced-enum-validated-receipts.json
    jq -e -f Tests/Conformance/scope-pattern-validated-receipts.jq .lake/build/scope-pattern-validated-receipts.json > /dev/null
    jq -e -f Tests/Conformance/namespaced-enum-validated-receipts.jq .lake/build/namespaced-enum-validated-receipts.json > /dev/null
    jq -e -f Tests/Conformance/agent-data-flow-validated-receipts.jq .lake/build/agent-data-flow-validated-receipts.json > /dev/null
    jq -e -f Tests/Conformance/agent-data-flow-validated-receipts-dispatch.jq .lake/build/agent-data-flow-validated-receipts.json > /dev/null
    jq -e -f Tests/Conformance/network-validated-receipts.jq .lake/build/network-validated-receipts.json > /dev/null
    jq -e -f Tests/Conformance/country-approval-validated-receipts.jq .lake/build/country-approval-validated-receipts.json > /dev/null

prepare-attested-schema-evolution: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean attested-schema-evolution > .lake/build/attested-schema-evolution.json

check-attested-schema-evolution: prepare-attested-schema-evolution
    jq -e -f Tests/Conformance/attested-schema-evolution.jq .lake/build/attested-schema-evolution.json > /dev/null
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-schema-only-revision < .lake/build/attested-schema-evolution.json > .lake/build/attested-schema-evolution-receipt.json
    jq -e -f Tests/Conformance/attested-schema-evolution-receipt.jq .lake/build/attested-schema-evolution-receipt.json > /dev/null

check-authorization-delta: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Governance/AuthorizationDelta.lean > .lake/build/authorization-delta.json
    jq -e -f Tests/Conformance/authorization-delta.jq .lake/build/authorization-delta.json > /dev/null
    jq '.manifest' .lake/build/authorization-delta.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml

check-health-authorization-impact:
    lake build Productions.Health.Pseudonymization.AuthorizationImpact
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Health/Pseudonymization/AuthorizationImpact.lean > .lake/build/health-authorization-impact.json
    jq -e -f Tests/Conformance/health-authorization-impact.jq .lake/build/health-authorization-impact.json > /dev/null
    jq '.suspended_manifest' .lake/build/health-authorization-impact.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml
    jq '.restored_manifest' .lake/build/health-authorization-impact.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml
    jq '.approval_manifest' .lake/build/health-authorization-impact.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml
    jq '{cases: [.lineage_changes[].manifest.cases[]]}' .lake/build/health-authorization-impact.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml

check-authorization-delta-proof:
    lake build CedarPooSpec.AuthorizationDeltaProof

check-payment-delta: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Enterprise/Agent/Payment/AuthorizationDelta.lean > .lake/build/payment-delta.json
    jq -e -f Tests/Conformance/payment-delta.jq .lake/build/payment-delta.json > /dev/null
    jq '.manifest' .lake/build/payment-delta.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml

[parallel]
check-examples: example::core::evaluation example::core::composition example::core::authorization example::cloud::pipeline-google-threat example::cloud::pipeline-google-deployment example::cloud::data-protection-google-sdp example::scenarios::tenant-device example::health::clinical-break-glass example::health::wearable-triage example::health::prior-authorization-lean example::health::prior-authorization-internal-channels-lean example::governance::attested-data example::governance::trusted-network example::governance::country-approval example::governance::ticket-sharing example::language::scope-and-enum example::language::extension-coverage example::enterprise::agent::delegation example::enterprise::agent::chain example::enterprise::agent::payment example::enterprise::agent::data-flow example::enterprise::agent::session example::enterprise::agent::fanout example::enterprise::agent::cross-agent-egress-lean example::enterprise::agent::department-synthesis-lean example::enterprise::payment::release example::enterprise::procurement::purchase-approval example::enterprise::procurement::delegated-approval example::enterprise::vehicle::supplier-transition example::enterprise::vehicle::vla-command example::enterprise::vehicle::mission-successor example::enterprise::vehicle::mission-replay example::enterprise::vehicle::mission-maintenance example::enterprise::vehicle::tara

prepare-cedar-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean ticket-sharing > .lake/build/ticket-sharing-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Governance/ExpandedPolicy.lean > .lake/build/expanded-policy.json

prepare-source-case-manifests: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean clinical > .lake/build/clinical-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean attested > .lake/build/attested-manifest.json

prepare-wearable-triage-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean wearable-triage > .lake/build/wearable-triage-manifest.json

prepare-language-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean scope-pattern > .lake/build/scope-pattern-manifest.json

prepare-network-manifest: prepare-source-case-manifests
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean network > .lake/build/network-manifest.json

prepare-country-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean country-approval > .lake/build/country-approval-manifest.json

prepare-purchase-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean purchase-approval > .lake/build/purchase-approval-manifest.json

prepare-delegated-manifest: prepare-purchase-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean delegated-approval > .lake/build/delegated-approval-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Enterprise/Procurement/PublishedPolicy.lean > .lake/build/delegated-published.json

prepare-delegated-matrix: prepare-delegated-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean delegated-matrix > .lake/build/delegated-matrix-manifest.json

prepare-payment-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean payment-release > .lake/build/payment-release-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Enterprise/Payment/PublishedPayment.lean > .lake/build/payment-published.json

prepare-agent-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean agent-delegation > .lake/build/agent-delegation-manifest.json

prepare-agent-chain-manifest: prepare-agent-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean agent-chain > .lake/build/agent-chain-manifest.json

prepare-agent-payment-manifest: prepare-agent-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean agent-payment > .lake/build/agent-payment-manifest.json

prepare-agent-data-flow-manifest: prepare-agent-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean agent-data-flow > .lake/build/agent-data-flow-manifest.json

prepare-bounded-session-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean bounded-session > .lake/build/bounded-session-manifest.json

prepare-shared-budget-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean shared-budget > .lake/build/shared-budget-manifest.json

prepare-supplier-transition-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean supplier-transition > .lake/build/supplier-transition-manifest.json

prepare-vla-command-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean vla-command > .lake/build/vla-command-manifest.json

prepare-mission-successor-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean mission-successor > .lake/build/mission-successor-manifest.json

check-mission-comparison: prepare-mission-successor-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Enterprise/Vehicle/Mission/MaintenanceComparison.lean > .lake/build/mission-maintenance-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-direct Examples/Enterprise/Vehicle/Mission/DirectPolicies < .lake/build/mission-successor-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-direct Examples/Enterprise/Vehicle/Mission/DirectChangePolicies < .lake/build/mission-maintenance-manifest.json

prepare-extension-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean extension-coverage > .lake/build/extension-coverage-manifest.json

prepare-tenant-device-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean tenant-device > .lake/build/tenant-device-manifest.json

prepare-all-manifests: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Manifests.lean all
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Governance/ExpandedPolicy.lean > .lake/build/expanded-policy.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Enterprise/Procurement/PublishedPolicy.lean > .lake/build/delegated-published.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Enterprise/Payment/PublishedPayment.lean > .lake/build/payment-published.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Governance/TemplateSourceExport.lean > .lake/build/template-source-bundle.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Productions/Governance/TemplateSourceExport.lean mixed > .lake/build/mixed-template-source-bundle.json

export-cedar-language: prepare-all-manifests
    mkdir -p Examples/Governance/TemplateSources
    jq -S .source .lake/build/template-source-bundle.json > Examples/Governance/TemplateSources/posture.json
    jq -S .source .lake/build/mixed-template-source-bundle.json > Examples/Governance/TemplateSources/posture-mixed.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Governance/Policies < .lake/build/ticket-sharing-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Governance/AttestedPolicies < .lake/build/attested-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Health/Policies < .lake/build/clinical-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Health/WearablePolicies < .lake/build/wearable-triage-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Language/Policies < .lake/build/scope-pattern-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Governance/NetworkPolicies < .lake/build/network-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Governance/CountryPolicies < .lake/build/country-approval-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/Procurement/Policies < .lake/build/purchase-approval-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/Procurement/DelegatedPolicies < .lake/build/delegated-approval-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/Payment/PaymentPolicies < .lake/build/payment-release-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/Agent/Delegation/AgentPolicies < .lake/build/agent-delegation-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/Agent/Chain/AgentChainPolicies < .lake/build/agent-chain-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/Agent/Payment/AgentPaymentPolicies < .lake/build/agent-payment-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/Agent/DataFlow/AgentDataFlowPolicies < .lake/build/agent-data-flow-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/Agent/Session/SessionPolicies < .lake/build/bounded-session-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/Agent/Fanout/FanoutPolicies < .lake/build/shared-budget-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/Vehicle/Uptane/SupplierTransitionPolicies < .lake/build/supplier-transition-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/Vehicle/VLA/CommandPolicies < .lake/build/vla-command-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/Vehicle/Mission/MissionPolicies < .lake/build/mission-successor-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Language/ExtensionPolicies < .lake/build/extension-coverage-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Scenarios/TenantDevicePolicies < .lake/build/tenant-device-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- render < .lake/build/expanded-policy.json > Examples/Governance/Policies/expanded.cedar

check-rust:
    mkdir -p .lake/build
    cargo tree --locked --manifest-path rust/Cargo.toml --no-default-features -e normal -p cedar-poo-bridge > .lake/build/bridge-default-tree.txt
    ! grep -q 'cedar-policy' .lake/build/bridge-default-tree.txt
    cargo fmt --manifest-path rust/Cargo.toml --check
    cargo clippy --locked --manifest-path rust/Cargo.toml --all-targets --no-default-features -- -D warnings
    cargo tree --locked --manifest-path rust/Cargo.toml --no-default-features --features google-sdp -e normal -p cedar-poo-bridge > .lake/build/bridge-google-sdp-tree.txt
    ! grep -q 'cedar-policy' .lake/build/bridge-google-sdp-tree.txt
    cargo clippy --locked --manifest-path rust/Cargo.toml --all-targets --features google-sdp -- -D warnings
    cargo clippy --locked --manifest-path rust/Cargo.toml --all-targets --features cedar-runtime -- -D warnings
    cargo clippy --locked --manifest-path rust/Cargo.toml --all-targets --features google-sdp-host -- -D warnings
    cargo test --locked --manifest-path rust/Cargo.toml --no-default-features
    cargo test --locked --manifest-path rust/Cargo.toml --features google-sdp
    cargo test --locked --manifest-path rust/Cargo.toml --features cedar-runtime
    cargo test --locked --manifest-path rust/Cargo.toml --features google-sdp-host

check-cedar-language: check-rust check-cedar-artifacts

check-cedar-artifacts: prepare-all-manifests
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-template-source < .lake/build/template-source-bundle.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-template-source < .lake/build/mixed-template-source-bundle.json
    jq -S .source .lake/build/template-source-bundle.json > .lake/build/template-source.sorted.json
    cmp .lake/build/template-source.sorted.json Examples/Governance/TemplateSources/posture.json
    jq -S .source .lake/build/mixed-template-source-bundle.json > .lake/build/mixed-template-source.sorted.json
    cmp .lake/build/mixed-template-source.sorted.json Examples/Governance/TemplateSources/posture-mixed.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Governance/Policies < .lake/build/ticket-sharing-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Governance/AttestedPolicies < .lake/build/attested-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Health/Policies < .lake/build/clinical-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Health/WearablePolicies < .lake/build/wearable-triage-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Language/Policies < .lake/build/scope-pattern-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Governance/NetworkPolicies < .lake/build/network-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Governance/CountryPolicies < .lake/build/country-approval-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/Procurement/Policies < .lake/build/purchase-approval-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/Procurement/DelegatedPolicies < .lake/build/delegated-approval-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml < .lake/build/delegated-matrix-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/Payment/PaymentPolicies < .lake/build/payment-release-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/Agent/Delegation/AgentPolicies < .lake/build/agent-delegation-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/Agent/Chain/AgentChainPolicies < .lake/build/agent-chain-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/Agent/Payment/AgentPaymentPolicies < .lake/build/agent-payment-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/Agent/DataFlow/AgentDataFlowPolicies < .lake/build/agent-data-flow-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/Agent/Session/SessionPolicies < .lake/build/bounded-session-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/Agent/Fanout/FanoutPolicies < .lake/build/shared-budget-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/Vehicle/Uptane/SupplierTransitionPolicies < .lake/build/supplier-transition-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/Vehicle/VLA/CommandPolicies < .lake/build/vla-command-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/Vehicle/Mission/MissionPolicies < .lake/build/mission-successor-manifest.json
    jq -S . .lake/build/payment-published.json > .lake/build/payment-published.sorted.json
    jq -S '[.cases[] | select(.revision == "integrated") | .policies][0]' .lake/build/payment-release-manifest.json > .lake/build/payment-receipt.sorted.json
    cmp .lake/build/payment-published.sorted.json .lake/build/payment-receipt.sorted.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- render < .lake/build/payment-published.json > .lake/build/payment-published.cedar
    cmp .lake/build/payment-published.cedar Examples/Enterprise/Payment/PaymentPolicies/integrated.cedar
    jq -S . .lake/build/delegated-published.json > .lake/build/delegated-published.sorted.json
    jq -S ".cases[0].policies" .lake/build/delegated-approval-manifest.json > .lake/build/delegated-receipt.sorted.json
    cmp .lake/build/delegated-published.sorted.json .lake/build/delegated-receipt.sorted.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- render < .lake/build/delegated-published.json > .lake/build/delegated-published.cedar
    cmp .lake/build/delegated-published.cedar Examples/Enterprise/Procurement/DelegatedPolicies/delegated.cedar
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Language/ExtensionPolicies < .lake/build/extension-coverage-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Scenarios/TenantDevicePolicies < .lake/build/tenant-device-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- render < .lake/build/expanded-policy.json > .lake/build/expanded.cedar
    cmp .lake/build/expanded.cedar Examples/Governance/Policies/expanded.cedar

check-policy-reuse: build
    mkdir -p .lake/build/lib/lean/Examples/Governance
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Governance/AttestedDataAccess.olean Examples/Governance/AttestedDataAccess.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Benchmarks/PolicyReuse.lean

bench-policy-reuse: check-policy-reuse
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Benchmarks/PolicyReuse.lean

bench-rust-export: prepare-cedar-manifest prepare-mission-successor-manifest
    cargo build --release --locked --features cedar-runtime --manifest-path rust/Cargo.toml --example export_latency
    rust/target/release/examples/export_latency .lake/build/expanded-policy.json
    jq -c '[.cases[] | select(.revision == "integrated") | .policies][0]' .lake/build/mission-successor-manifest.json > .lake/build/mission-integrated-policy.json
    rust/target/release/examples/export_latency .lake/build/mission-integrated-policy.json
    rust/target/release/examples/export_latency .lake/build/expanded-policy.json 32 500
    rust/target/release/examples/export_latency .lake/build/expanded-policy.json 128 200
    rust/target/release/examples/export_latency --manifest .lake/build/mission-successor-manifest.json 100

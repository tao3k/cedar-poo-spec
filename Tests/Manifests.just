[parallel]
check-examples: example::core::evaluation example::core::composition example::core::authorization example::cloud::pipeline-google-threat example::cloud::pipeline-google-deployment example::cloud::data-protection-google-sdp example::scenarios::tenant-device example::health::clinical-break-glass example::health::wearable-triage example::health::prior-authorization-lean example::health::prior-authorization-internal-channels-lean example::governance::attested-data example::governance::trusted-network example::governance::country-approval example::governance::ticket-sharing example::language::scope-and-enum example::language::extension-coverage example::enterprise::agent::delegation example::enterprise::agent::chain example::enterprise::agent::payment example::enterprise::agent::data-flow example::enterprise::agent::session example::enterprise::agent::fanout example::enterprise::agent::cross-agent-egress-lean example::enterprise::agent::department-synthesis-lean example::enterprise::payment::release example::enterprise::procurement::purchase-approval example::enterprise::procurement::delegated-approval example::enterprise::vehicle::supplier-transition example::enterprise::vehicle::vla-command example::enterprise::vehicle::mission-successor example::enterprise::vehicle::mission-replay example::enterprise::vehicle::mission-maintenance example::enterprise::vehicle::tara

prepare-cedar-manifest: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-cedar-manifest

prepare-source-case-manifests: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-source-case-manifests

prepare-wearable-triage-manifest: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-wearable-triage-manifest

prepare-language-manifest: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-language-manifest

prepare-network-manifest: prepare-source-case-manifests
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-network-manifest

prepare-country-manifest: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-country-manifest

prepare-purchase-manifest: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-purchase-manifest

prepare-delegated-manifest: prepare-purchase-manifest
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-delegated-manifest

prepare-delegated-matrix: prepare-delegated-manifest
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-delegated-matrix

prepare-payment-manifest: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-payment-manifest

prepare-agent-manifest: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-agent-manifest

prepare-agent-chain-manifest: prepare-agent-manifest
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-agent-chain-manifest

prepare-agent-payment-manifest: prepare-agent-manifest
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-agent-payment-manifest

prepare-agent-data-flow-manifest: prepare-agent-manifest
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-agent-data-flow-manifest

prepare-bounded-session-manifest: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-bounded-session-manifest

prepare-shared-budget-manifest: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-shared-budget-manifest

prepare-supplier-transition-manifest: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-supplier-transition-manifest

prepare-vla-command-manifest: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-vla-command-manifest

prepare-mission-successor-manifest: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-mission-successor-manifest

check-mission-comparison: prepare-mission-successor-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/Vehicle/Mission/MaintenanceComparison.lean > .lake/build/mission-maintenance-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-direct Examples/Enterprise/Vehicle/Mission/DirectPolicies < .lake/build/mission-successor-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-direct Examples/Enterprise/Vehicle/Mission/DirectChangePolicies < .lake/build/mission-maintenance-manifest.json

prepare-extension-manifest: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-extension-manifest

prepare-tenant-device-manifest: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-tenant-device-manifest

prepare-all-manifests: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-all-manifests

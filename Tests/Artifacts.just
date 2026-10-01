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

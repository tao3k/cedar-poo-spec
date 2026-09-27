set shell := ["sh", "-eu", "-c"]
export CARGO_TARGET_DIR := "rust/target"

default:
    @just --list

update:
    lake update

sync: update
    just check

build:
    lake build CedarPooSpec

build-examples: build
    lake build Examples

check-docs:
    emacs --batch -Q --eval '(progn (require (quote org-element)) (dolist (file (append (list "README.org") (directory-files-recursively "docs" "\\.org$") (directory-files-recursively "Examples" "\\.org$"))) (with-temp-buffer (insert-file-contents file) (org-mode) (org-element-parse-buffer))) (princ "ORG-OK"))'

check: build-examples check-docs
    just check-policy-reuse
    just check-cedar-language
    just check-mission-comparison

[parallel]
check-examples: check-evaluation check-composition check-authorization check-scenarios check-health check-wearable-triage check-governance check-ticket-sharing check-language check-payment-release check-agent-delegation check-agent-chain check-agent-payment check-agent-data-flow check-agent-session check-agent-fanout check-supplier-transition check-vla-command check-mission-successor check-mission-replay check-mission-maintenance check-reuse-scale

check-evaluation:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Evaluation.lean

check-composition:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Composition.lean

check-authorization:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/AuthorizationSoundness.lean

check-scenarios:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Scenarios/TenantDevicePolicyEvolution.lean

check-health:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Health/ClinicalBreakGlass.lean

check-wearable-triage:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Health/WearableTriage.lean

check-governance:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Governance/AttestedDataAccess.lean

check-trusted-network:
    mkdir -p .lake/build/lib/lean/Examples/Governance
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Governance/AttestedDataAccess.olean Examples/Governance/AttestedDataAccess.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Governance/TrustedNetworkDataAccess.lean

check-country-approval:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Governance/CountryApproval.lean

check-purchase-approval:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/Procurement/PurchaseApproval.lean

check-delegated-approval:
    mkdir -p .lake/build/lib/lean/Examples/Enterprise/Procurement
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Enterprise/Procurement/PurchaseApproval.olean Examples/Enterprise/Procurement/PurchaseApproval.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/Procurement/DelegatedApproval.lean

check-payment-release:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/Payment/PaymentRelease.lean

check-agent-delegation:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/Agent/Delegation/AgentDelegation.lean

check-agent-chain:
    mkdir -p .lake/build/lib/lean/Examples/Enterprise/Agent/Delegation
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Enterprise/Agent/Delegation/AgentDelegation.olean Examples/Enterprise/Agent/Delegation/AgentDelegation.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/Agent/Chain/AgentChain.lean

check-agent-payment:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/Agent/Payment/AgentPayment.lean

check-agent-data-flow:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/Agent/DataFlow/AgentDataFlow.lean

check-agent-session:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/Agent/Session/BoundedSession.lean

check-agent-fanout:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/Agent/Fanout/SharedBudget.lean

check-supplier-transition:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/Vehicle/Uptane/SupplierTransition.lean

check-vla-command:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/Vehicle/VLA/CommandBoundary.lean

check-mission-successor:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/Vehicle/Mission/SuccessorBoundary.lean

check-mission-replay:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/Vehicle/Mission/TrajectoryReplay.lean

check-mission-maintenance:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/Vehicle/Mission/MaintenanceComparison.lean

check-extension-coverage:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Language/ExtensionCoverage.lean

check-ticket-sharing:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Governance/TicketSharing.lean

check-language:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Language/ScopeAndPattern.lean

prepare-cedar-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean ticket-sharing > .lake/build/ticket-sharing-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Governance/ExpandedPolicy.lean > .lake/build/expanded-policy.json

prepare-source-case-manifests: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean clinical > .lake/build/clinical-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean attested > .lake/build/attested-manifest.json

prepare-wearable-triage-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean wearable-triage > .lake/build/wearable-triage-manifest.json

prepare-language-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean scope-pattern > .lake/build/scope-pattern-manifest.json

prepare-network-manifest: prepare-source-case-manifests
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean network > .lake/build/network-manifest.json

prepare-country-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean country-approval > .lake/build/country-approval-manifest.json

prepare-purchase-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean purchase-approval > .lake/build/purchase-approval-manifest.json

prepare-delegated-manifest: prepare-purchase-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean delegated-approval > .lake/build/delegated-approval-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/Procurement/PublishedPolicy.lean > .lake/build/delegated-published.json

prepare-delegated-matrix: prepare-delegated-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean delegated-matrix > .lake/build/delegated-matrix-manifest.json

prepare-payment-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean payment-release > .lake/build/payment-release-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/Payment/PublishedPayment.lean > .lake/build/payment-published.json

prepare-agent-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean agent-delegation > .lake/build/agent-delegation-manifest.json

prepare-agent-chain-manifest: prepare-agent-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean agent-chain > .lake/build/agent-chain-manifest.json

prepare-agent-payment-manifest: prepare-agent-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean agent-payment > .lake/build/agent-payment-manifest.json

prepare-agent-data-flow-manifest: prepare-agent-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean agent-data-flow > .lake/build/agent-data-flow-manifest.json

prepare-bounded-session-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean bounded-session > .lake/build/bounded-session-manifest.json

prepare-shared-budget-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean shared-budget > .lake/build/shared-budget-manifest.json

prepare-supplier-transition-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean supplier-transition > .lake/build/supplier-transition-manifest.json

prepare-vla-command-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean vla-command > .lake/build/vla-command-manifest.json

prepare-mission-successor-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean mission-successor > .lake/build/mission-successor-manifest.json

check-mission-comparison: prepare-mission-successor-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/Vehicle/Mission/MaintenanceComparison.lean > .lake/build/mission-maintenance-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-direct Examples/Enterprise/Vehicle/Mission/DirectPolicies < .lake/build/mission-successor-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-direct Examples/Enterprise/Vehicle/Mission/DirectChangePolicies < .lake/build/mission-maintenance-manifest.json

prepare-extension-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean extension-coverage > .lake/build/extension-coverage-manifest.json

prepare-tenant-device-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean tenant-device > .lake/build/tenant-device-manifest.json

prepare-all-manifests: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean all
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Governance/ExpandedPolicy.lean > .lake/build/expanded-policy.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/Procurement/PublishedPolicy.lean > .lake/build/delegated-published.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/Payment/PublishedPayment.lean > .lake/build/payment-published.json

export-cedar-language: prepare-all-manifests
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

check-cedar-language: prepare-all-manifests
    cargo tree --locked --manifest-path rust/Cargo.toml --no-default-features -e normal -p cedar-poo-bridge > .lake/build/bridge-default-tree.txt
    ! rg -q 'cedar-policy' .lake/build/bridge-default-tree.txt
    cargo fmt --manifest-path rust/Cargo.toml --check
    cargo clippy --locked --manifest-path rust/Cargo.toml --all-targets --no-default-features -- -D warnings
    cargo clippy --locked --manifest-path rust/Cargo.toml --all-targets --features cedar-runtime -- -D warnings
    cargo test --locked --manifest-path rust/Cargo.toml --no-default-features
    cargo test --locked --manifest-path rust/Cargo.toml --features cedar-runtime
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

check-reuse-scale:
    timeout --signal=TERM --kill-after=3s 30s lake env lean -M 2048 -T 10000000 Examples/ReuseScale.lean

check-policy-reuse: build
    mkdir -p .lake/build/lib/lean/Examples/Governance
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Governance/AttestedDataAccess.olean Examples/Governance/AttestedDataAccess.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Benchmarks/PolicyReuse.lean

bench-policy-reuse: check-policy-reuse
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Benchmarks/PolicyReuse.lean

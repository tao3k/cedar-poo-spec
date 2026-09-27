set shell := ["sh", "-eu", "-c"]
export CARGO_TARGET_DIR := "rust/target"

default:
    @just --list

update:
    lake update

build:
    lake build CedarPooSpec

build-examples: build
    lake build Examples

check-docs:
    emacs --batch -Q --eval '(progn (require (quote org-element)) (dolist (file (append (list "README.org") (directory-files-recursively "docs" "\\.org$") (directory-files-recursively "Examples" "\\.org$"))) (with-temp-buffer (insert-file-contents file) (org-mode) (org-element-parse-buffer))) (princ "ORG-OK"))'

check: build-examples check-docs
    just check-policy-reuse
    just check-cedar-language

[parallel]
check-examples: check-evaluation check-composition check-authorization check-scenarios check-health check-governance check-ticket-sharing check-language check-payment-release check-agent-delegation check-agent-chain check-agent-payment check-agent-data-flow check-reuse-scale

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

check-governance:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Governance/AttestedDataAccess.lean

check-trusted-network:
    mkdir -p .lake/build/lib/lean/Examples/Governance
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Governance/AttestedDataAccess.olean Examples/Governance/AttestedDataAccess.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Governance/TrustedNetworkDataAccess.lean

check-country-approval:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Governance/CountryApproval.lean

check-purchase-approval:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/PurchaseApproval.lean

check-delegated-approval:
    mkdir -p .lake/build/lib/lean/Examples/Enterprise
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Enterprise/PurchaseApproval.olean Examples/Enterprise/PurchaseApproval.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/DelegatedApproval.lean

check-payment-release:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/PaymentRelease.lean

check-agent-delegation:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/AgentDelegation.lean

check-agent-chain:
    mkdir -p .lake/build/lib/lean/Examples/Enterprise
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Enterprise/AgentDelegation.olean Examples/Enterprise/AgentDelegation.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/AgentChain.lean

check-agent-payment:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/AgentPayment.lean

check-agent-data-flow:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/AgentDataFlow.lean

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
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/PublishedPolicy.lean > .lake/build/delegated-published.json

prepare-delegated-matrix: prepare-delegated-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean delegated-matrix > .lake/build/delegated-matrix-manifest.json

prepare-payment-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean payment-release > .lake/build/payment-release-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/PublishedPayment.lean > .lake/build/payment-published.json

prepare-agent-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean agent-delegation > .lake/build/agent-delegation-manifest.json

prepare-agent-chain-manifest: prepare-agent-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean agent-chain > .lake/build/agent-chain-manifest.json

prepare-agent-payment-manifest: prepare-agent-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean agent-payment > .lake/build/agent-payment-manifest.json

prepare-agent-data-flow-manifest: prepare-agent-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean agent-data-flow > .lake/build/agent-data-flow-manifest.json

prepare-extension-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean extension-coverage > .lake/build/extension-coverage-manifest.json

prepare-all-manifests: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean all
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Governance/ExpandedPolicy.lean > .lake/build/expanded-policy.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/PublishedPolicy.lean > .lake/build/delegated-published.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/PublishedPayment.lean > .lake/build/payment-published.json

export-cedar-language: prepare-all-manifests
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Governance/Policies < .lake/build/ticket-sharing-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Governance/AttestedPolicies < .lake/build/attested-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Health/Policies < .lake/build/clinical-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Language/Policies < .lake/build/scope-pattern-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Governance/NetworkPolicies < .lake/build/network-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Governance/CountryPolicies < .lake/build/country-approval-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/Policies < .lake/build/purchase-approval-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/DelegatedPolicies < .lake/build/delegated-approval-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/PaymentPolicies < .lake/build/payment-release-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/AgentPolicies < .lake/build/agent-delegation-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/AgentChainPolicies < .lake/build/agent-chain-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/AgentPaymentPolicies < .lake/build/agent-payment-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/AgentDataFlowPolicies < .lake/build/agent-data-flow-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Language/ExtensionPolicies < .lake/build/extension-coverage-manifest.json
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
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Language/Policies < .lake/build/scope-pattern-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Governance/NetworkPolicies < .lake/build/network-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Governance/CountryPolicies < .lake/build/country-approval-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/Policies < .lake/build/purchase-approval-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/DelegatedPolicies < .lake/build/delegated-approval-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml < .lake/build/delegated-matrix-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/PaymentPolicies < .lake/build/payment-release-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/AgentPolicies < .lake/build/agent-delegation-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/AgentChainPolicies < .lake/build/agent-chain-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/AgentPaymentPolicies < .lake/build/agent-payment-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/AgentDataFlowPolicies < .lake/build/agent-data-flow-manifest.json
    jq -S . .lake/build/payment-published.json > .lake/build/payment-published.sorted.json
    jq -S '[.cases[] | select(.revision == "integrated") | .policies][0]' .lake/build/payment-release-manifest.json > .lake/build/payment-receipt.sorted.json
    cmp .lake/build/payment-published.sorted.json .lake/build/payment-receipt.sorted.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- render < .lake/build/payment-published.json > .lake/build/payment-published.cedar
    cmp .lake/build/payment-published.cedar Examples/Enterprise/PaymentPolicies/integrated.cedar
    jq -S . .lake/build/delegated-published.json > .lake/build/delegated-published.sorted.json
    jq -S ".cases[0].policies" .lake/build/delegated-approval-manifest.json > .lake/build/delegated-receipt.sorted.json
    cmp .lake/build/delegated-published.sorted.json .lake/build/delegated-receipt.sorted.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- render < .lake/build/delegated-published.json > .lake/build/delegated-published.cedar
    cmp .lake/build/delegated-published.cedar Examples/Enterprise/DelegatedPolicies/delegated.cedar
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Language/ExtensionPolicies < .lake/build/extension-coverage-manifest.json
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

set shell := ["sh", "-eu", "-c"]
export CARGO_TARGET_DIR := "rust/target"

default:
    @just --list

update:
    lake update

build:
    lake build CedarPooSpec

check-docs:
    emacs --batch -Q --eval '(progn (require (quote org-element)) (dolist (file (append (list "README.org") (directory-files-recursively "docs" "\\.org$") (directory-files-recursively "Examples" "\\.org$"))) (with-temp-buffer (insert-file-contents file) (org-mode) (org-element-parse-buffer))) (princ "ORG-OK"))'

check: build check-docs
    just --jobs 2 check-examples
    just check-policy-reuse
    just check-cedar-language

[parallel]
check-examples: check-evaluation check-composition check-authorization check-scenarios check-health check-governance check-ticket-sharing check-language check-payment-release check-agent-delegation check-agent-payment check-reuse-scale

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

check-agent-payment:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/AgentPayment.lean

check-extension-coverage:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Language/ExtensionCoverage.lean

check-ticket-sharing:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Governance/TicketSharing.lean

check-language:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Language/ScopeAndPattern.lean

prepare-cedar-manifest: build
    mkdir -p .lake/build/lib/lean/Examples/Governance
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Governance/TicketSharing.olean Examples/Governance/TicketSharing.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Governance/TicketSharingExport.lean > .lake/build/ticket-sharing-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Governance/ExpandedPolicy.lean > .lake/build/expanded-policy.json

prepare-source-case-manifests: build
    mkdir -p .lake/build/lib/lean/Examples/Health .lake/build/lib/lean/Examples/Governance
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Health/ClinicalBreakGlass.olean Examples/Health/ClinicalBreakGlass.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Governance/AttestedDataAccess.olean Examples/Governance/AttestedDataAccess.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Health/ClinicalBreakGlassExport.lean > .lake/build/clinical-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Governance/AttestedDataAccessExport.lean > .lake/build/attested-manifest.json

prepare-language-manifest: build
    mkdir -p .lake/build/lib/lean/Examples/Language
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Language/ScopeAndPattern.olean Examples/Language/ScopeAndPattern.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Language/ScopeAndPatternExport.lean > .lake/build/scope-pattern-manifest.json

prepare-network-manifest: prepare-source-case-manifests
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Governance/TrustedNetworkDataAccess.olean Examples/Governance/TrustedNetworkDataAccess.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Governance/TrustedNetworkDataAccessExport.lean > .lake/build/network-manifest.json

prepare-country-manifest: build
    mkdir -p .lake/build/lib/lean/Examples/Governance
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Governance/CountryApproval.olean Examples/Governance/CountryApproval.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Governance/CountryApprovalExport.lean > .lake/build/country-approval-manifest.json

prepare-purchase-manifest: build
    mkdir -p .lake/build/lib/lean/Examples/Enterprise
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Enterprise/PurchaseApproval.olean Examples/Enterprise/PurchaseApproval.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/PurchaseApprovalExport.lean > .lake/build/purchase-approval-manifest.json

prepare-delegated-manifest: prepare-purchase-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Enterprise/DelegatedApproval.olean Examples/Enterprise/DelegatedApproval.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/DelegatedApprovalExport.lean > .lake/build/delegated-approval-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/PublishedPolicy.lean > .lake/build/delegated-published.json

prepare-delegated-matrix: prepare-delegated-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/DelegatedApprovalMatrixExport.lean > .lake/build/delegated-matrix-manifest.json

prepare-payment-manifest: build
    mkdir -p .lake/build/lib/lean/Examples/Enterprise
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Enterprise/PaymentRelease.olean Examples/Enterprise/PaymentRelease.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/PaymentReleaseExport.lean > .lake/build/payment-release-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/PublishedPayment.lean > .lake/build/payment-published.json

prepare-agent-manifest: build
    mkdir -p .lake/build/lib/lean/Examples/Enterprise
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Enterprise/AgentDelegation.olean Examples/Enterprise/AgentDelegation.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/AgentDelegationExport.lean > .lake/build/agent-delegation-manifest.json

prepare-agent-payment-manifest: prepare-agent-manifest
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Enterprise/AgentPayment.olean Examples/Enterprise/AgentPayment.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/AgentPaymentExport.lean > .lake/build/agent-payment-manifest.json

prepare-extension-manifest: build
    mkdir -p .lake/build/lib/lean/Examples/Language
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Language/ExtensionCoverage.olean Examples/Language/ExtensionCoverage.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Language/ExtensionCoverageExport.lean > .lake/build/extension-coverage-manifest.json

export-cedar-language: prepare-cedar-manifest prepare-source-case-manifests prepare-language-manifest prepare-network-manifest prepare-country-manifest prepare-purchase-manifest prepare-delegated-manifest prepare-payment-manifest prepare-agent-payment-manifest prepare-extension-manifest
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
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/AgentPaymentPolicies < .lake/build/agent-payment-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Language/ExtensionPolicies < .lake/build/extension-coverage-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- render < .lake/build/expanded-policy.json > Examples/Governance/Policies/expanded.cedar

check-cedar-language: prepare-cedar-manifest prepare-source-case-manifests prepare-language-manifest prepare-network-manifest prepare-country-manifest prepare-purchase-manifest prepare-delegated-matrix prepare-payment-manifest prepare-agent-payment-manifest prepare-extension-manifest
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
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/AgentPaymentPolicies < .lake/build/agent-payment-manifest.json
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

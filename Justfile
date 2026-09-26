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
check-examples: check-evaluation check-composition check-authorization check-scenarios check-health check-governance check-ticket-sharing check-reuse-scale

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

check-ticket-sharing:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Governance/TicketSharing.lean

prepare-cedar-manifest: build
    mkdir -p .lake/build/lib/lean/Examples/Governance
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Governance/TicketSharing.olean Examples/Governance/TicketSharing.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Governance/TicketSharingExport.lean > .lake/build/ticket-sharing-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Governance/ExpandedPolicy.lean > .lake/build/expanded-policy.json

export-cedar-language: prepare-cedar-manifest
    cargo run --locked --quiet --manifest-path rust/Cargo.toml -- emit Examples/Governance/Policies < .lake/build/ticket-sharing-manifest.json
    cargo run --locked --quiet --manifest-path rust/Cargo.toml -- render < .lake/build/expanded-policy.json > Examples/Governance/Policies/expanded.cedar

check-cedar-language: prepare-cedar-manifest
    cargo fmt --manifest-path rust/Cargo.toml --check
    cargo clippy --locked --manifest-path rust/Cargo.toml --all-targets -- -D warnings
    cargo test --locked --manifest-path rust/Cargo.toml
    cargo run --locked --quiet --manifest-path rust/Cargo.toml -- check-artifacts Examples/Governance/Policies < .lake/build/ticket-sharing-manifest.json
    cargo run --locked --quiet --manifest-path rust/Cargo.toml -- render < .lake/build/expanded-policy.json > .lake/build/expanded.cedar
    cmp .lake/build/expanded.cedar Examples/Governance/Policies/expanded.cedar

check-reuse-scale:
    timeout --signal=TERM --kill-after=3s 30s lake env lean -M 2048 -T 10000000 Examples/ReuseScale.lean

check-policy-reuse: build
    mkdir -p .lake/build/lib/lean/Examples/Governance
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Governance/AttestedDataAccess.olean Examples/Governance/AttestedDataAccess.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Benchmarks/PolicyReuse.lean

bench-policy-reuse: check-policy-reuse
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Benchmarks/PolicyReuse.lean

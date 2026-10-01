# Generate Lean inputs, replay Cedar decisions, then run Tests/Conformance.
check-conformance: check-replay-receipts check-schema-bound-receipts check-schema-bound-scenarios check-attested-schema-evolution check-authorization-delta check-authorization-delta-operational check-authorization-delta-reasons check-authorization-delta-effective-reasons check-payment-delta check-payment-interaction check-payment-audit check-agent-trace-delta check-health-authorization-impact check-personnel-governance

check-personnel-governance:
    lake build Examples.Manifests Tests.Enterprise.Personnel.SourceCustody
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean source-custody-validated > .lake/build/source-custody-validated-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-validated-receipts < .lake/build/source-custody-validated-manifest.json > .lake/build/source-custody-validated-receipts.json
    jq -e -f Tests/Conformance/personnel-governance-receipts.jq .lake/build/source-custody-validated-receipts.json > /dev/null

check-tests: build-examples
    lake build Tests

check-delta: check-authorization-delta check-authorization-delta-operational check-authorization-delta-reasons check-authorization-delta-effective-reasons check-payment-delta check-payment-interaction check-agent-trace-delta check-health-authorization-impact

check-replay-receipts: prepare-agent-payment-manifest
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-receipts < .lake/build/agent-payment-manifest.json > .lake/build/agent-payment-replay-receipts.json
    jq -e --slurpfile manifest .lake/build/agent-payment-manifest.json -f Tests/Conformance/agent-payment-replay-receipts.jq .lake/build/agent-payment-replay-receipts.json > /dev/null

prepare-agent-payment-validated-manifest: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-agent-payment-validated-manifest

check-schema-bound-receipts: prepare-agent-payment-validated-manifest
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-validated-receipts < .lake/build/agent-payment-validated-manifest.json > .lake/build/agent-payment-validated-receipts.json
    jq -e --slurpfile manifest .lake/build/agent-payment-validated-manifest.json -f Tests/Conformance/agent-payment-validated-receipts.jq .lake/build/agent-payment-validated-receipts.json > /dev/null

prepare-schema-bound-scenarios: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-schema-bound-scenarios

check-schema-bound-scenarios: prepare-schema-bound-scenarios
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test schema-bound

prepare-attested-schema-evolution: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test prepare prepare-attested-schema-evolution

check-attested-schema-evolution: prepare-attested-schema-evolution
    jq -e -f Tests/Conformance/attested-schema-evolution.jq .lake/build/attested-schema-evolution.json > /dev/null
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-schema-only-revision < .lake/build/attested-schema-evolution.json > .lake/build/attested-schema-evolution-receipt.json
    jq -e -f Tests/Conformance/attested-schema-evolution-receipt.jq .lake/build/attested-schema-evolution-receipt.json > /dev/null

check-authorization-delta: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Governance/AuthorizationDelta.lean > .lake/build/authorization-delta.json
    jq -e -f Tests/Conformance/authorization-delta.jq .lake/build/authorization-delta.json > /dev/null
    jq '.posture_manifest' .lake/build/authorization-delta.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml
    jq '.manifest' .lake/build/authorization-delta.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml

check-authorization-delta-operational:
    lake build CedarPooSpec.AuthorizationDeltaOperationalExactProof Tests.Governance.AuthorizationDeltaOperational Tests.Governance.AuthorizationDeltaFormula
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Tests/Governance/AuthorizationDeltaOperational.lean > .lake/build/authorization-delta-operational.json
    jq -e -f Tests/Conformance/authorization-delta-operational.jq .lake/build/authorization-delta-operational.json > /dev/null
    jq '.manifest' .lake/build/authorization-delta-operational.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml

# Research artifact only: emits the exact query and cvc5's CPC output.
# The fixture's UNSAT theorem is separate and uses native computation certificates.
probe-authorization-delta-proof:
    lake build CedarPooSpec.AuthorizationDeltaOperationalExactProof Examples.Governance.TicketSharing
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Tests/Governance/AuthorizationDeltaProofProbe.lean > .lake/build/authorization-delta-exact.smt2
    timeout --signal=TERM --kill-after=3s 120s "$CVC5" --lang=smt --produce-proofs --proof-check=lazy --dump-proofs --proof-format-mode=cpc .lake/build/authorization-delta-exact.smt2 > .lake/build/authorization-delta-exact.cpc
    rg -q '^\(check-sat\)$' .lake/build/authorization-delta-exact.smt2
    test "$(head -n 1 .lake/build/authorization-delta-exact.cpc)" = unsat
    rg -q '^\(step ' .lake/build/authorization-delta-exact.cpc

# Optional pinned research check: Ethos validates a renamed reference query.
# The constructor-name translation is still outside the Lean proof boundary.
probe-authorization-delta-proof-ethos: probe-authorization-delta-proof
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test check-cpc --input .lake/build/authorization-delta-exact.smt2 --output-dir .lake/build --cvc5 "$CVC5" --ethos "$ETHOS" --signature-root "$CPC_SIGNATURE_ROOT"

check-authorization-delta-reasons:
    lake build Tests.Governance.AuthorizationDeltaReasons
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Tests/Governance/AuthorizationDeltaReasons.lean > .lake/build/authorization-delta-reasons.json
    jq -e -f Tests/Conformance/authorization-delta-reasons.jq .lake/build/authorization-delta-reasons.json > /dev/null
    jq '.manifest' .lake/build/authorization-delta-reasons.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml

check-authorization-delta-effective-reasons:
    lake build CedarPooSpec.AuthorizationDeltaEffectiveReasonsProof Tests.Governance.AuthorizationDeltaEffectiveReasons
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Tests/Governance/AuthorizationDeltaEffectiveReasons.lean > .lake/build/authorization-delta-effective-reasons.json
    jq -e -f Tests/Conformance/authorization-delta-effective-reasons.jq .lake/build/authorization-delta-effective-reasons.json > /dev/null
    jq '.manifest' .lake/build/authorization-delta-effective-reasons.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml

check-payment-interaction:
    lake build Examples.Enterprise.Agent.Payment.JointRelease
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/Agent/Payment/JointRelease.lean > .lake/build/payment-joint-release.json
    jq -e -f Tests/Conformance/payment-joint-release.jq .lake/build/payment-joint-release.json > /dev/null
    jq '.manifest' .lake/build/payment-joint-release.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml

# Public payment operation, selectable audit stages, and concrete Cedar adapter.
check-payment-audit:
    lake build CedarPooSpec.Vertical.FinancialServices.PaymentLifecycle Tests.Enterprise.Agent.Payment.PaymentAudit

check-agent-trace-delta:
    lake build Examples.Enterprise.Agent.Session.HostSafety
    just example enterprise agent session-trace-delta

check-health-authorization-impact:
    lake build Examples.Health.Pseudonymization.AuthorizationImpact
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Health/Pseudonymization/AuthorizationImpact.lean > .lake/build/health-authorization-impact.json
    jq -e -f Tests/Conformance/health-authorization-impact.jq .lake/build/health-authorization-impact.json > /dev/null
    jq '.suspended_manifest' .lake/build/health-authorization-impact.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml
    jq '.restored_manifest' .lake/build/health-authorization-impact.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml
    jq '.approval_manifest' .lake/build/health-authorization-impact.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml
    jq '{cases: [.lineage_changes[].manifest.cases[]]}' .lake/build/health-authorization-impact.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml

check-authorization-delta-proof:
    lake build CedarPooSpec.AuthorizationDeltaProof CedarPooSpec.AuthorizationDeltaBooleanCore Tests.Governance.AuthorizationDeltaFormula Tests.Governance.AuthorizationDeltaDirect Tests.Governance.AuthorizationDeltaAxiomAudit

check-payment-delta: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/Agent/Payment/AuthorizationDelta.lean > .lake/build/payment-delta.json
    jq -e -f Tests/Conformance/payment-delta.jq .lake/build/payment-delta.json > /dev/null
    jq '.manifest' .lake/build/payment-delta.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml

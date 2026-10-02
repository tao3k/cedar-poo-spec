# Generate Lean inputs, replay Cedar decisions, then run Tests/Conformance.
check-conformance: check-replay-receipts check-schema-bound-receipts check-schema-bound-scenarios check-attested-schema-evolution check-authorization-delta check-authorization-delta-operational check-authorization-delta-reasons check-authorization-delta-effective-reasons check-payment-delta check-payment-interaction check-payment-audit check-agent-trace-delta check-health-authorization-impact check-personnel-governance check-agent-commerce-admission

check-agent-commerce-admission: check-agent-commerce-projection
    cargo test --locked --manifest-path rust/Cargo.toml --no-default-features --features agent-commerce-admission --test agent_commerce_admission_consumer

check-agent-commerce-projection:
    mkdir -p .lake/build
    lake build Tests.Enterprise.Agent.Payment.AgentCommerceProjection
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test check agent-commerce-projection

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
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test check authorization-delta

check-authorization-delta-operational:
    lake build CedarPooSpec.AuthorizationDeltaOperationalExactProof Tests.Governance.AuthorizationDeltaOperational Tests.Governance.AuthorizationDeltaFormula
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test check authorization-delta-operational

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
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test check authorization-delta-reasons

check-authorization-delta-effective-reasons:
    lake build CedarPooSpec.AuthorizationDeltaEffectiveReasonsProof Tests.Governance.AuthorizationDeltaEffectiveReasons
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test check authorization-delta-effective-reasons

check-payment-interaction:
    lake build Examples.Enterprise.Agent.Payment.JointRelease
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test check payment-interaction

# Public payment operation, selectable audit stages, and concrete Cedar adapter.
check-payment-audit:
    lake build CedarPooSpec.Vertical.FinancialServices.PaymentLedger Tests.Enterprise.Agent.Payment.PaymentAudit

# Agent identity, delegated purchase scope, exact merchant offer, and cumulative budget.
check-agent-commerce:
    lake build CedarPooSpec.Vertical.FinancialServices.AgentCommercePayment Tests.Enterprise.Agent.Payment.AgentCommerce

check-agent-trace-delta:
    lake build Examples.Enterprise.Agent.Session.HostSafety
    just example enterprise agent session-trace-delta

check-health-authorization-impact:
    lake build Productions.Health.Pseudonymization.AuthorizationImpact
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test check health-authorization-impact

check-authorization-delta-proof:
    lake build CedarPooSpec.AuthorizationDeltaProof CedarPooSpec.AuthorizationDeltaBooleanCore Tests.Governance.AuthorizationDeltaFormula Tests.Governance.AuthorizationDeltaDirect Tests.Governance.AuthorizationDeltaAxiomAudit

check-payment-delta: build-examples
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test check payment-delta

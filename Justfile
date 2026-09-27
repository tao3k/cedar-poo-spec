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
    emacs --batch -Q --eval '(progn (require (quote org-element)) (dolist (file (append (list "README.org") (directory-files-recursively "docs" "\\.org$") (directory-files-recursively "Examples" "\\.org$") (directory-files-recursively "Tests" "\\.org$") (directory-files-recursively "Benchmarks" "\\.org$"))) (with-temp-buffer (insert-file-contents file) (org-mode) (org-element-parse-buffer))) (princ "ORG-OK"))'

check: check-tests check-docs
    just check-policy-reuse
    just check-cedar-language
    just check-mission-comparison
    just check-replay-receipts
    just check-exchange-signing-validated
    just check-schema-bound-receipts
    just check-schema-bound-scenarios
    just check-lakehouse-gateway
    just check-multi-account-banking
    just check-attested-schema-evolution
    just check-authorization-delta
    just check-authorization-delta-proof
    just check-payment-delta

check-lean: check-tests check-authorization-delta-proof check-policy-reuse

check-tests: build-examples
    lake build Tests

check-delta: check-authorization-delta check-payment-delta

check-replay-receipts: prepare-agent-payment-manifest
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-receipts < .lake/build/agent-payment-manifest.json > .lake/build/agent-payment-replay-receipts.json
    jq -e --slurpfile manifest .lake/build/agent-payment-manifest.json 'length == ($manifest[0].cases | length) and all(.[]; .format_version == 1 and .cedar_policy_version == "4.12.0" and .cedar_language_version == "4.5.0" and (.policies_sha256 | test("^[0-9a-f]{64}$")) and (.entities_sha256 | test("^[0-9a-f]{64}$")) and (.request_sha256 | test("^[0-9a-f]{64}$")) and .error_free_allow == (.decision == "allow" and (.error_policy_ids | length) == 0))' .lake/build/agent-payment-replay-receipts.json > /dev/null

prepare-agent-payment-validated-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean agent-payment-validated > .lake/build/agent-payment-validated-manifest.json

check-schema-bound-receipts: prepare-agent-payment-validated-manifest
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-validated-receipts < .lake/build/agent-payment-validated-manifest.json > .lake/build/agent-payment-validated-receipts.json
    jq -e --slurpfile manifest .lake/build/agent-payment-validated-manifest.json 'length == ($manifest[0].cases | length) and length == 32 and all(.[]; (.schema_sha256 | test("^[0-9a-f]{64}$")) and .replay.error_policy_ids == [] and .replay.error_free_allow == (.replay.decision == "allow"))' .lake/build/agent-payment-validated-receipts.json > /dev/null

prepare-schema-bound-scenarios: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean scope-pattern-validated > .lake/build/scope-pattern-validated-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean namespaced-enum-validated > .lake/build/namespaced-enum-validated-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean agent-data-flow-validated > .lake/build/agent-data-flow-validated-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean network-validated > .lake/build/network-validated-manifest.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean country-approval-validated > .lake/build/country-approval-validated-manifest.json

check-schema-bound-scenarios: prepare-schema-bound-scenarios
    jq -e '.schema[""].entityTypes.Document.shape.attributes.meta == {"type":"Record","attributes":{"tag":{"type":"String"}}} and (.cases | length) == 5' .lake/build/scope-pattern-validated-manifest.json > /dev/null
    jq -e '.schema.Data.entityTypes.Classification.enum == ["public","restricted"] and .schema.Data.entityTypes.Document.shape.attributes.classification == {"type":"Entity","name":"Data::Classification"} and .schema.Org.actions.read.appliesTo.principalTypes == ["Org::User"] and .schema.Org.actions.read.appliesTo.resourceTypes == ["Data::Document"] and (.cases | length) == 4' .lake/build/namespaced-enum-validated-manifest.json > /dev/null
    jq -e '.schema[""].actions["publish-document"].appliesTo.context.attributes.source == {"type":"Entity","name":"Document"} and .schema[""].actions["publish-document"].appliesTo.context.attributes.reviewer == {"type":"Entity","name":"User"} and (.cases | length) == 34' .lake/build/agent-data-flow-validated-manifest.json > /dev/null
    jq -e '.schema[""].actions.query.appliesTo.context.attributes.sourceIp == {"type":"Extension","name":"ipaddr"} and (.cases | length) == 9' .lake/build/network-validated-manifest.json > /dev/null
    jq -e '.schema[""].entityTypes.User.tags == {"type":"String"} and .schema[""].entityTypes.Timesheet.tags == {"type":"String"} and .schema[""].actions.approve.memberOf == [{"type":"Action","id":"ApproverActions"}] and (.cases | length) == 13' .lake/build/country-approval-validated-manifest.json > /dev/null
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-validated-receipts < .lake/build/agent-data-flow-validated-manifest.json > .lake/build/agent-data-flow-validated-receipts.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-validated-receipts < .lake/build/network-validated-manifest.json > .lake/build/network-validated-receipts.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-validated-receipts < .lake/build/country-approval-validated-manifest.json > .lake/build/country-approval-validated-receipts.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-validated-receipts < .lake/build/scope-pattern-validated-manifest.json > .lake/build/scope-pattern-validated-receipts.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-validated-receipts < .lake/build/namespaced-enum-validated-manifest.json > .lake/build/namespaced-enum-validated-receipts.json
    jq -e 'length == 5 and all(.[]; (.schema_sha256 | test("^[0-9a-f]{64}$")) and .replay.error_policy_ids == [])' .lake/build/scope-pattern-validated-receipts.json > /dev/null
    jq -e 'length == 4 and all(.[]; (.schema_sha256 | test("^[0-9a-f]{64}$")) and .replay.error_policy_ids == [])' .lake/build/namespaced-enum-validated-receipts.json > /dev/null
    jq -e 'length == 34 and all(.[]; (.schema_sha256 | test("^[0-9a-f]{64}$")) and .replay.error_policy_ids == [])' .lake/build/agent-data-flow-validated-receipts.json > /dev/null
    jq -e '[.[] | select(.replay.case_name | startswith("dispatch-"))] | (map(.replay.case_name) | sort) == ["dispatch-allow-publishdispatched", "dispatch-allow-publishgoverned", "dispatch-deny-publishdispatched", "dispatch-deny-publishgoverned"] and (map(.replay.decision) | unique) == ["allow", "deny"] and (group_by(.replay.request_sha256) | length == 2 and all(.[]; length == 2 and (map(.replay.policies_sha256) | unique | length) == 1 and (map(.replay.decision) | unique | length) == 1))' .lake/build/agent-data-flow-validated-receipts.json > /dev/null
    jq -e 'length == 9 and all(.[]; (.schema_sha256 | test("^[0-9a-f]{64}$")) and .replay.error_policy_ids == [])' .lake/build/network-validated-receipts.json > /dev/null
    jq -e 'length == 13 and all(.[]; (.schema_sha256 | test("^[0-9a-f]{64}$")) and .replay.error_policy_ids == [])' .lake/build/country-approval-validated-receipts.json > /dev/null

check-lakehouse-gateway: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean lakehouse-gateway-validated > .lake/build/lakehouse-gateway-validated-manifest.json
    jq -e '.schema.AgentCore.entityTypes.OAuthUser.tags == {"type":"String"} and .schema.AgentCore.actions["lakehouse-mcp-target___query_claims"].appliesTo.context.attributes.input.attributes.geography == {"required":false,"type":"String"} and (.cases | length) == 16' .lake/build/lakehouse-gateway-validated-manifest.json > /dev/null
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-validated-receipts < .lake/build/lakehouse-gateway-validated-manifest.json > .lake/build/lakehouse-gateway-validated-receipts.json
    jq -e 'length == 16 and all(.[]; .replay.error_policy_ids == [] and (.schema_sha256 | test("^[0-9a-f]{64}$"))) and ([.[] | {key:.replay.case_name,value:.replay.decision}] | from_entries) == {"policyholder-us-query":"allow","hardened-policyholder-us-query":"allow","policyholder-eu-query":"deny","hardened-policyholder-eu-query":"deny","policyholder-eu-summary":"deny","hardened-policyholder-eu-summary":"deny","adjuster-us-summary":"allow","hardened-adjuster-us-summary":"allow","adjuster-eu-details":"deny","hardened-adjuster-eu-details":"deny","restricted-tool":"deny","hardened-restricted-tool":"deny","sourcecombined-missing-geography":"allow","failclosed-missing-geography":"deny","sourcecombined-unknown-geography":"allow","failclosed-unknown-geography":"deny"}' .lake/build/lakehouse-gateway-validated-receipts.json > /dev/null
    jq '.cases[0].policies' .lake/build/lakehouse-gateway-validated-manifest.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- render > .lake/build/lakehouse-source-combined.cedar
    cmp .lake/build/lakehouse-source-combined.cedar Examples/Enterprise/Agent/LakehouseGateway/Policies/source-combined.cedar
    jq '.cases[1].policies' .lake/build/lakehouse-gateway-validated-manifest.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- render > .lake/build/lakehouse-fail-closed.cedar
    cmp .lake/build/lakehouse-fail-closed.cedar Examples/Enterprise/Agent/LakehouseGateway/Policies/fail-closed.cedar

check-multi-account-banking: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean multi-account-banking-validated > .lake/build/multi-account-banking-validated-manifest.json
    jq -e '.schema.AgentCore.entityTypes.OAuthUser != null and (.schema.AgentCore.actions | length) == 18 and (.cases | length) == 36' .lake/build/multi-account-banking-validated-manifest.json > /dev/null
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-validated-receipts < .lake/build/multi-account-banking-validated-manifest.json > .lake/build/multi-account-banking-validated-receipts.json
    jq -e 'length == 36 and all(.[]; .replay.error_policy_ids == [] and (.schema_sha256 | test("^[0-9a-f]{64}$")) and (.replay.case_name | test("^(source|owners)-")) and .replay.decision == (if (.replay.case_name | endswith("delete-customer")) then "deny" else "allow" end)) and ((group_by(.replay.case_name | sub("^(source|owners)-"; ""))) | length == 18 and all(.[]; length == 2 and (map(.replay.case_name | split("-")[0]) | sort) == ["owners", "source"]))' .lake/build/multi-account-banking-validated-receipts.json > /dev/null
    jq '.cases[0].policies' .lake/build/multi-account-banking-validated-manifest.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- render > .lake/build/multi-account-banking-source.cedar
    cmp .lake/build/multi-account-banking-source.cedar Examples/Enterprise/Agent/MultiAccountBanking/Policies/source-broad.cedar
    jq '.cases[1].policies' .lake/build/multi-account-banking-validated-manifest.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- render > .lake/build/multi-account-banking-owners.cedar
    cmp .lake/build/multi-account-banking-owners.cedar Examples/Enterprise/Agent/MultiAccountBanking/Policies/owner-composed.cedar

prepare-attested-schema-evolution: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean attested-schema-evolution > .lake/build/attested-schema-evolution.json

check-attested-schema-evolution: prepare-attested-schema-evolution
    jq -e '(.before.schema[""].entityTypes.Dataset.shape.attributes | has("classification") | not) and .after.schema[""].entityTypes.Dataset.shape.attributes.classification == {"type":"String","required":false}' .lake/build/attested-schema-evolution.json > /dev/null
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-schema-only-revision < .lake/build/attested-schema-evolution.json > .lake/build/attested-schema-evolution-receipt.json
    jq -e '(.before_schema_sha256 | test("^[0-9a-f]{64}$")) and (.after_schema_sha256 | test("^[0-9a-f]{64}$")) and .before_schema_sha256 != .after_schema_sha256 and (.replay | length) == 6 and all(.replay[]; .error_policy_ids == [])' .lake/build/attested-schema-evolution-receipt.json > /dev/null

check-authorization-delta: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Governance/AuthorizationDelta.lean > .lake/build/authorization-delta.json
    jq -e '.posture.status == "no-expansion-in-schema" and .posture.environments_checked == 1 and .new_grant.status == "expanded" and .new_grant.environments_checked == 1 and (.new_grant.counterexamples | length) > 0' .lake/build/authorization-delta.json > /dev/null
    jq '.manifest' .lake/build/authorization-delta.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml

check-authorization-delta-proof:
    lake build CedarPooSpec.AuthorizationDeltaProof

check-payment-delta: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Enterprise/Agent/Payment/AuthorizationDelta.lean > .lake/build/payment-delta.json
    jq -e '.freeze.status == "no-expansion-in-schema" and .freeze.environments_checked == 4 and .restore.status == "expanded" and .restore.environments_checked == 4 and (.restore.counterexamples | length) > 0' .lake/build/payment-delta.json > /dev/null
    jq '.manifest' .lake/build/payment-delta.json | cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml

[parallel]
check-examples: check-evaluation check-composition check-authorization check-scenarios check-health check-wearable-triage check-governance check-ticket-sharing check-language check-payment-release check-agent-delegation check-agent-chain check-agent-payment check-agent-data-flow check-agent-session check-agent-fanout check-exchange-signing check-supplier-transition check-vla-command check-mission-successor check-mission-replay check-mission-maintenance check-vehicle-tara

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

check-exchange-signing:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/Exchange/Signing/SigningBoundary.lean

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

check-vehicle-tara:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/Vehicle/TARA/TaraProjection.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Enterprise/Vehicle/TARA/TaraHandoff.lean

check-extension-coverage:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Language/ExtensionCoverage.lean

check-ticket-sharing:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Governance/TicketSharing.lean

check-language:
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Language/ScopeAndPattern.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Language/NamespacedEnum.lean

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

prepare-exchange-signing-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean exchange-signing > .lake/build/exchange-signing-manifest.json

check-exchange-signing-replay: prepare-exchange-signing-manifest
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml < .lake/build/exchange-signing-manifest.json

prepare-exchange-signing-validated-manifest: build-examples
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Manifests.lean exchange-signing-validated > .lake/build/exchange-signing-validated-manifest.json

check-exchange-signing-validated: prepare-exchange-signing-validated-manifest
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- replay-validated-receipts < .lake/build/exchange-signing-validated-manifest.json > .lake/build/exchange-signing-validated-receipts.json
    jq -e 'length == 16 and all(.[]; .replay.error_policy_ids == [] and .replay.error_free_allow == (.replay.decision == "allow"))' .lake/build/exchange-signing-validated-receipts.json > /dev/null

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
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Governance/TemplateSourceExport.lean > .lake/build/template-source-bundle.json
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Governance/TemplateSourceExport.lean mixed > .lake/build/mixed-template-source-bundle.json

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
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/Exchange/Signing/SigningPolicies < .lake/build/exchange-signing-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/Vehicle/Uptane/SupplierTransitionPolicies < .lake/build/supplier-transition-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/Vehicle/VLA/CommandPolicies < .lake/build/vla-command-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Enterprise/Vehicle/Mission/MissionPolicies < .lake/build/mission-successor-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Language/ExtensionPolicies < .lake/build/extension-coverage-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- emit Examples/Scenarios/TenantDevicePolicies < .lake/build/tenant-device-manifest.json
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- render < .lake/build/expanded-policy.json > Examples/Governance/Policies/expanded.cedar

check-rust:
    mkdir -p .lake/build
    cargo tree --locked --manifest-path rust/Cargo.toml --no-default-features -e normal -p cedar-poo-bridge > .lake/build/bridge-default-tree.txt
    ! rg -q 'cedar-policy' .lake/build/bridge-default-tree.txt
    cargo fmt --manifest-path rust/Cargo.toml --check
    cargo clippy --locked --manifest-path rust/Cargo.toml --all-targets --no-default-features -- -D warnings
    cargo clippy --locked --manifest-path rust/Cargo.toml --all-targets --features cedar-runtime -- -D warnings
    cargo test --locked --manifest-path rust/Cargo.toml --no-default-features
    cargo test --locked --manifest-path rust/Cargo.toml --features cedar-runtime

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
    cargo run --locked --quiet --features cedar-runtime --manifest-path rust/Cargo.toml -- check-artifacts Examples/Enterprise/Exchange/Signing/SigningPolicies < .lake/build/exchange-signing-manifest.json
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

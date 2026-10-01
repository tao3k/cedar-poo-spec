set shell := ["sh", "-eu", "-c"]
export CARGO_TARGET_DIR := "rust/target"

# Example recipes follow the source publisher or project area.
mod example 'Examples/Justfile'
import 'Tests/Conformance.just'
import 'Tests/Manifests.just'
import 'Tests/Artifacts.just'
import 'Benchmarks/Justfile'

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

check: check-tests
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

# Lean feedback without running every Cedar/Rust scenario.
check-quick:
    lake build CedarPooSpec Tests

check-lean: check-tests check-authorization-delta-proof check-policy-reuse

# Python workspace

`python/` is a uv workspace with two installable packages:

- `cedar-poo-bridge` wraps the current Rust bridge CLI as a byte-preserving process client. It accepts a repository path and permits a different executable in tests or future integrations. A native Python bridge can add an implementation behind this boundary without changing conformance recipe names.
- `cedar-poo-testing` owns conformance plans, artifact generation and checks, schema-bound receipt checks, the pinned AP2 wire/constraint corpus checks, and the optional pinned CPC research check. Its `cedar-poo-test` CLI is called by imported Justfiles; the Justfiles remain the stable public task interface.
- Named `cedar-poo-test check <recipe>` plans run Lean conformance fixtures, jq assertions, and Cedar Rust consumers behind the corresponding `just check-*` entrypoints.

From the repository root:

```sh
uv run --project python --package cedar-poo-testing --locked cedar-poo-test --help
uv run --project python --package cedar-poo-testing --locked python -m unittest discover -s python/tests
just check-schema-bound-scenarios
```

The CLI expects the repository root as its working directory unless `--repository` is supplied. `prepare` plans run Lean exports under the existing timeout and resource limits. `emit-artifacts` and `check-artifacts` share one manifest-to-directory plan. `schema-bound` checks the exported manifests with jq, replays them through the Rust CLI, and checks the resulting receipts. `check-cpc` remains a research probe for a renamed reference query; it does not establish the Lean UNSAT premise.

## Pinned AP2 checks

The testing package owns `ap2_wire` and `ap2_constraints`. Both use the CLI's
`--repository` path for frozen fixtures. Frozen byte checks need the normal
installation; actual SDK replay selects the `ap2-sdk` extra. Core and transitive
SDK dependencies are pinned in the shared `python/uv.lock`.

```sh
uv run --project python --package cedar-poo-testing --locked cedar-poo-test ap2-wire --check-frozen
uv run --project python --package cedar-poo-testing --extra ap2-sdk --locked cedar-poo-test ap2-wire --sdk-root /absolute/path/to/pinned/AP2
uv run --project python --package cedar-poo-testing --extra ap2-sdk --locked cedar-poo-test ap2-constraints --sdk-root /absolute/path/to/pinned/AP2
```

The corresponding public Justfile tasks are
`check-agentic-ai-commerce-wire-corpus`, `check-agentic-ai-commerce-wire-sdk`
and `check-agentic-ai-commerce-constraint-sdk`. SDK source and fixture digest
checks are unchanged. Frozen byte integrity, SDK observations and independent
Rust verifier results remain separate evidence.

export-cedar-language: prepare-all-manifests
    mkdir -p Examples/Governance/TemplateSources
    jq -S .source .lake/build/template-source-bundle.json > Examples/Governance/TemplateSources/posture.json
    jq -S .source .lake/build/mixed-template-source-bundle.json > Examples/Governance/TemplateSources/posture-mixed.json
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test emit-artifacts
    cargo run --locked --quiet -p cedar-poo-bridge --manifest-path rust/Cargo.toml -- render < .lake/build/expanded-policy.json > Examples/Governance/Policies/expanded.cedar

check-rust:
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test check-rust

check-cedar-language: check-rust check-cedar-artifacts

check-cedar-artifacts: prepare-all-manifests
    cargo run --locked --quiet -p cedar-poo-bridge --manifest-path rust/Cargo.toml -- check-template-source < .lake/build/template-source-bundle.json
    cargo run --locked --quiet -p cedar-poo-bridge --manifest-path rust/Cargo.toml -- check-template-source < .lake/build/mixed-template-source-bundle.json
    jq -S .source .lake/build/template-source-bundle.json > .lake/build/template-source.sorted.json
    cmp .lake/build/template-source.sorted.json Examples/Governance/TemplateSources/posture.json
    jq -S .source .lake/build/mixed-template-source-bundle.json > .lake/build/mixed-template-source.sorted.json
    cmp .lake/build/mixed-template-source.sorted.json Examples/Governance/TemplateSources/posture-mixed.json
    uv run --project python --package cedar-poo-testing --locked cedar-poo-test check-artifacts
    cargo run --locked --quiet -p cedar-poo-bridge --manifest-path rust/Cargo.toml < .lake/build/delegated-matrix-manifest.json
    jq -S . .lake/build/payment-published.json > .lake/build/payment-published.sorted.json
    jq -S '[.cases[] | select(.revision == "integrated") | .policies][0]' .lake/build/payment-release-manifest.json > .lake/build/payment-receipt.sorted.json
    cmp .lake/build/payment-published.sorted.json .lake/build/payment-receipt.sorted.json
    cargo run --locked --quiet -p cedar-poo-bridge --manifest-path rust/Cargo.toml -- render < .lake/build/payment-published.json > .lake/build/payment-published.cedar
    cmp .lake/build/payment-published.cedar Examples/Enterprise/Payment/PaymentPolicies/integrated.cedar
    jq -S . .lake/build/delegated-published.json > .lake/build/delegated-published.sorted.json
    jq -S ".cases[0].policies" .lake/build/delegated-approval-manifest.json > .lake/build/delegated-receipt.sorted.json
    cmp .lake/build/delegated-published.sorted.json .lake/build/delegated-receipt.sorted.json
    cargo run --locked --quiet -p cedar-poo-bridge --manifest-path rust/Cargo.toml -- render < .lake/build/delegated-published.json > .lake/build/delegated-published.cedar
    cmp .lake/build/delegated-published.cedar Examples/Enterprise/Procurement/DelegatedPolicies/delegated.cedar
    cargo run --locked --quiet -p cedar-poo-bridge --manifest-path rust/Cargo.toml -- render < .lake/build/expanded-policy.json > .lake/build/expanded.cedar
    cmp .lake/build/expanded.cedar Examples/Governance/Policies/expanded.cedar

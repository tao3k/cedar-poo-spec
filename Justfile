set shell := ["sh", "-eu", "-c"]

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

check-reuse-scale:
    timeout --signal=TERM --kill-after=3s 30s lake env lean -M 2048 -T 10000000 Examples/ReuseScale.lean

check-policy-reuse: build
    mkdir -p .lake/build/lib/lean/Examples/Governance
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 -o .lake/build/lib/lean/Examples/Governance/AttestedDataAccess.olean Examples/Governance/AttestedDataAccess.lean
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 Examples/Benchmarks/PolicyReuse.lean

bench-policy-reuse: check-policy-reuse
    timeout --signal=TERM --kill-after=3s 120s lake env lean -M 2048 -T 10000000 --run Examples/Benchmarks/PolicyReuse.lean

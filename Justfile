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
    lake env lean Examples/Evaluation.lean
    lake env lean Examples/Composition.lean
    lake env lean Examples/AuthorizationSoundness.lean
    lake env lean Examples/Scenarios/TenantDevicePolicyEvolution.lean
    timeout --signal=TERM --kill-after=3s 30s lake env lean -M 2048 -T 10000000 Examples/ReuseScale.lean

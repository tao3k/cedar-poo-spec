set shell := ["sh", "-eu", "-c"]

default:
    @just --list

update:
    lake update

build:
    lake build CedarPooSpec

check-docs:
    emacs --batch -Q --eval '(progn (require (quote org-element)) (with-temp-buffer (insert-file-contents "README.org") (org-mode) (org-element-parse-buffer)) (princ "ORG-OK"))'

check: build check-docs
    lake env lean Examples/Evaluation.lean
    lake env lean Examples/Composition.lean

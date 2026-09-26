set shell := ["sh", "-eu", "-c"]

default:
    @just --list

update:
    lake update

build:
    lake build CedarPooSpec

check: build
    lake env lean Examples/Evaluation.lean

"""Entry point for Cedar POO conformance preparation and checks."""

import argparse
from pathlib import Path

from . import artifacts, checks, cpc, manifests, scenarios, rust_checks, ap2_wire, ap2_constraints


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path.cwd())
    commands = parser.add_subparsers(dest="command", required=True)
    prepare = commands.add_parser("prepare", help="run a named Lean manifest export")
    prepare.add_argument("recipe", choices=sorted(manifests.PREPARE))
    commands.add_parser("schema-bound", help="check and replay schema-bound scenarios")
    check = commands.add_parser("check", help="run a named conformance check")
    check.add_argument("recipe", choices=sorted(checks.NAMES))
    commands.add_parser("emit-artifacts", help="generate Cedar artifacts from manifests")
    commands.add_parser("check-artifacts", help="check Cedar artifacts against manifests")
    commands.add_parser("check-rust", help="check Rust feature boundaries and consumers")
    commands.add_parser("check-cpc", help="check the pinned Ethos research proof")
    wire = commands.add_parser("ap2-wire", help="check frozen AP2 bytes or replay the pinned SDK wire corpus")
    wire.add_argument("--sdk-root", type=Path)
    wire.add_argument("--check-frozen", action="store_true")
    wire.add_argument("--generate", action="store_true")
    constraints = commands.add_parser("ap2-constraints", help="replay pinned SDK constraint domain observations")
    constraints.add_argument("--sdk-root", type=Path, required=True)
    constraints.add_argument("--generate", action="store_true")
    args, remaining = parser.parse_known_args()
    if args.command != "check-cpc" and remaining:
        parser.error(f"unrecognized arguments: {' '.join(remaining)}")
    if args.command == "prepare":
        manifests.prepare(args.recipe, args.repository)
    elif args.command == "schema-bound":
        scenarios.check_schema_bound(args.repository)
    elif args.command == "check":
        checks.run(args.recipe, args.repository)
    elif args.command == "ap2-wire":
        ap2_wire.run(args.repository, sdk_root=args.sdk_root,
                     check_frozen=args.check_frozen, generate_corpus=args.generate)
    elif args.command == "ap2-constraints":
        ap2_constraints.run(args.repository, sdk_root=args.sdk_root,
                            generate_corpus=args.generate)
    elif args.command == "check-rust":
        rust_checks.run(args.repository)
    elif args.command in {"emit-artifacts", "check-artifacts"}:
        artifacts.run(args.repository, "emit" if args.command == "emit-artifacts" else "check-artifacts")
    else:
        cpc.check(remaining)

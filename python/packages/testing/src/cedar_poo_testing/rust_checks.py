"""Workspace dependency boundaries, isolated profile builds and consumer gates."""

import json
from pathlib import Path
import subprocess


COMMERCE = (None, "projection", "admission", "budget-commit", "credential", "consumption")


def run(repository: Path) -> None:
    repository = repository.resolve()
    base = ["--locked", "--manifest-path", "Cargo.toml"]

    def cargo(command: str, *args: str) -> None:
        print(f"workspace gate: cargo {command} {' '.join(args)}", flush=True)
        subprocess.run(["cargo", command, *base, *args], cwd=repository, check=True)

    metadata = json.loads(subprocess.check_output(
        ["cargo", "metadata", *base, "--no-deps", "--format-version", "1"],
        cwd=repository, text=True,
    ))
    members = [p for p in metadata["packages"] if p["id"] in metadata["workspace_members"]]
    for package in members:
        if package["name"] != "cedar-poo-bridge" and not package["name"].endswith("-case"):
            if any(d["name"].endswith("-case") or d["name"] == "cedar-poo-bridge"
                   for d in package["dependencies"]):
                raise ValueError(f"library {package['name']} imports an application Case")

    build = repository / ".lake/build"
    build.mkdir(parents=True, exist_ok=True)
    # Inspect one package at a time: a workspace all-features build unifies dependencies
    # and cannot demonstrate isolation of a production consumer's selected profile.
    profiles = [(p, None) for p in ("cedar-poo-core", "cedar-poo-agentic",
                                  "cedar-poo-pseudonymization")]
    profiles += [("cedar-poo-pseudonymization", "google-sdp")]
    profiles += [("cedar-poo-commerce", f) for f in COMMERCE]
    profiles += [("cedar-poo-commerce-case", f) for f in COMMERCE]
    profiles += [("cedar-poo-pseudonymization-case", "google-contract")]
    for package, feature in profiles:
        args = ["-p", package, "--no-default-features"]
        if feature:
            args += ["--features", feature]
        print(f"dependency boundary: {package}/{feature or 'default'}", flush=True)
        tree = subprocess.check_output(
            ["cargo", "tree", *base, *args, "-e", "normal"], cwd=repository, text=True,
        )
        (build / f"{package}-{feature or 'default'}-tree.txt").write_text(tree)
        if "cedar-policy" in tree:
            raise ValueError(f"{package}/{feature} unexpectedly depends on Cedar runtime")
        if ("p256 v" in tree) != (package in ("cedar-poo-commerce", "cedar-poo-commerce-case")):
            raise ValueError(f"{package}/{feature} has an unexpected P-256 dependency")
        expects_mrr = package in ("cedar-poo-commerce", "cedar-poo-commerce-case") and feature in (
            "budget-commit", "credential", "consumption",
        )
        if ("mrr-data-content v" in tree) != expects_mrr:
            raise ValueError(f"{package}/{feature} has an unexpected MRR dependency")
        cargo("clippy", *args, "--all-targets", "--", "-D", "warnings")

    subprocess.run(["cargo", "fmt", "--all", "--check"], cwd=repository, check=True)
    cargo("clippy", "--workspace", "--all-targets", "--all-features", "--", "-D", "warnings")
    cargo("test", "--workspace", "--all-features", "--exclude", "cedar-poo-commerce-case")
    cargo("test", "-p", "cedar-poo-commerce-case", "--no-default-features")
    # Fixture-dependent consumers execute in cedar-conformance after Lean exports.
    cargo("test", "-p", "cedar-poo-commerce-case", "--features", "admission",
          "--test", "agentic_ai_commerce_admission_consumer")
    for feature in ("local", "google-contract", "google-admission"):
        cargo("clippy", "-p", "cedar-poo-pseudonymization-case", "--no-default-features",
              "--features", feature, "--all-targets", "--", "-D", "warnings")
    # Also compile every package's defaults independently, preventing rich workspace
    # feature unification from hiding an omitted dependency or cfg declaration.
    for package in sorted(p["name"] for p in members):
        cargo("check", "-p", package, "--all-targets", "--no-default-features")

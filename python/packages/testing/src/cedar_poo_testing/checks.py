"""Lean fixture and Rust consumer checks behind stable Just recipe names."""

import hashlib

import json
import os
from pathlib import Path
import subprocess


BUILD = Path(".lake/build")
RUST = [
    "cargo", "run", "--locked", "--quiet", "-p", "cedar-poo-bridge",
    "--manifest-path", "Cargo.toml",
]
LEAN = [
    "timeout", "--signal=TERM", "--kill-after=3s", "120s",
    "lake", "env", "lean", "-M", "2048", "-T", "10000000", "--run",
]

# Source, output stem, jq assertion, and manifest fields replayed by Cedar.
CHECKS = {
    "agentic-ai-commerce-presentation": (
        "Tests/AgenticAI/Commerce/Presentation.lean",
        "agentic-ai-commerce-presentation", None, (),
    ),
    "agentic-ai-commerce-acceptance": (
        "Tests/AgenticAI/Commerce/Acceptance.lean",
        "agentic-ai-commerce-acceptance", None, (),
    ),
    "authorization-delta": (
        "Productions/Governance/AuthorizationDelta.lean", "authorization-delta",
        "authorization-delta", ("posture_manifest", "manifest"),
    ),
    "authorization-delta-operational": (
        "Tests/Governance/AuthorizationDeltaOperational.lean", "authorization-delta-operational",
        "authorization-delta-operational", ("manifest",),
    ),
    "authorization-delta-reasons": (
        "Tests/Governance/AuthorizationDeltaReasons.lean", "authorization-delta-reasons",
        "authorization-delta-reasons", ("manifest",),
    ),
    "authorization-delta-effective-reasons": (
        "Tests/Governance/AuthorizationDeltaEffectiveReasons.lean",
        "authorization-delta-effective-reasons", "authorization-delta-effective-reasons",
        ("manifest",),
    ),
    "payment-interaction": (
        "Examples/Enterprise/Agent/Payment/JointRelease.lean", "payment-joint-release",
        "payment-joint-release", ("manifest",),
    ),
    "payment-delta": (
        "Productions/Enterprise/Agent/Payment/AuthorizationDelta.lean", "payment-delta",
        "payment-delta", ("manifest",),
    ),
    "health-authorization-impact": (
        "Productions/Health/Pseudonymization/AuthorizationImpact.lean",
        "health-authorization-impact", "health-authorization-impact",
        ("suspended_manifest", "restored_manifest", "approval_manifest", "lineage_changes"),
    ),
    "agentic-ai-commerce-projection": (
        "Tests/AgenticAI/Commerce/Projection.lean",
        "agentic-ai-commerce-projection", None, (),
    ),
}


NAMES = {*CHECKS, "agentic-ai-commerce-admission"}

def _run(
    command: list[str], repository: Path, *,
    input_bytes: bytes | None = None, env: dict[str, str] | None = None,
) -> None:
    subprocess.run(command, cwd=repository, input=input_bytes, env=env, check=True)


def _projection(data: object) -> None:
    if not isinstance(data, dict):
        raise ValueError("agentic AI commerce projection must be an object")
    mandate, offer, lineage = data.get("mandate"), data.get("offer"), data.get("lineage")
    if not (
        isinstance(mandate, dict) and isinstance(offer, dict) and isinstance(lineage, list)
        and len(lineage) == 2 and lineage[0] == mandate
        and all(isinstance(item, dict) and "verified" not in item for item in (mandate, offer, *lineage))
    ):
        raise ValueError("agentic AI commerce projection has invalid lineage or includes derived verification")


def run(name: str, repository: Path) -> None:
    repository = repository.resolve()
    if name == "agentic-ai-commerce-admission":
        fixture = repository / BUILD / "agentic-ai-commerce-projection.json"
        if not fixture.is_file():
            run("agentic-ai-commerce-projection", repository)
        env = {**os.environ, "LEAN_PROJECTION_FIXTURE": str(fixture)}
        for feature, consumer in (
            ("admission", "agentic_ai_commerce_admission_consumer"),
        ):
            _run(["cargo", "test", "--locked", "--manifest-path", "Cargo.toml",
                  "-p", "cedar-poo-commerce-case", "--no-default-features", "--features", feature, "--test", consumer],
                 repository, env=env)
        return
    source, stem, assertion, fields = CHECKS[name]
    output = repository / BUILD / f"{stem}.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as stream:
        subprocess.run([*LEAN, source], cwd=repository, stdout=stream, check=True)
    if assertion:
        subprocess.run(
            ["jq", "-e", "-f", f"Tests/Conformance/{assertion}.jq", str(output)],
            cwd=repository, stdout=subprocess.DEVNULL, check=True,
        )
    data = json.loads(output.read_text())
    if name in ("agentic-ai-commerce-acceptance", "agentic-ai-commerce-presentation"):
        kind = "presentation" if name.endswith("presentation") else "acceptance"
        if data != json.loads((repository / f"Tests/Conformance/commerce-{kind}-v1.json").read_text()):
            raise ValueError("acceptance fixture differs from actual Lean export")
        if kind == "presentation":
            upstream = repository / "Tests/Conformance/ap2-upstream"
            pin = json.loads((upstream / "source.json").read_text())
            if data["ap2Revision"] != pin["revision"]:
                raise ValueError("presentation fixture and upstream source pins differ")
            for path, digest in pin["files"].items():
                if hashlib.sha256((upstream / path).read_bytes()).hexdigest() != digest:
                    raise ValueError(f"pinned AP2 source digest differs: {path}")
        _run(["cargo", "test", "--locked", "-p", "cedar-poo-commerce-case",
              "--no-default-features", "--features", "ap2-receipt" if kind == "presentation" else "acceptance", "--test",
              f"agentic_ai_commerce_{kind}_consumer"], repository)
        return
    if name == "agentic-ai-commerce-projection":
        _projection(data)
        if data != json.loads((repository / "Tests/Conformance/commerce-projection-v1.json").read_text()):
            raise ValueError("commerce conformance fixture differs from actual Lean export")
        env = {**os.environ, "LEAN_PROJECTION_FIXTURE": str(output)}
        _run(
            ["cargo", "test", "--locked", "--manifest-path", "Cargo.toml",
             "-p", "cedar-poo-commerce-case", "--no-default-features", "--features", "projection",
             "--test", "agentic_ai_commerce_projection_consumer"],
            repository, env=env,
        )
        return
    for field in fields:
        if field == "lineage_changes":
            value = {"cases": [case for change in data[field] for case in change["manifest"]["cases"]]}
        else:
            value = data[field]
        _run(RUST, repository, input_bytes=json.dumps(value).encode())

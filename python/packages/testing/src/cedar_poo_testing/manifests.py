"""Named Lean exports used by the conformance recipes."""

from pathlib import Path
import subprocess


BUILD = Path(".lake/build")
MANIFEST = Path("Productions/Manifests.lean")


def manifest(selector: str, filename: str | None = None) -> tuple[Path, str, Path]:
    return MANIFEST, selector, BUILD / (filename or f"{selector}-manifest.json")


def source(path: str, filename: str, selector: str = "") -> tuple[Path, str, Path]:
    return Path(path), selector, BUILD / filename


PREPARE: dict[str, list[tuple[Path, str, Path | None]]] = {
    "prepare-agent-payment-validated-manifest": [manifest("agent-payment-validated")],
    "prepare-schema-bound-scenarios": [
        manifest("scope-pattern-validated"),
        manifest("namespaced-enum-validated"),
        manifest("agent-data-flow-validated"),
        manifest("network-validated"),
        manifest("country-approval-validated"),
    ],
    "prepare-attested-schema-evolution": [
        manifest("attested-schema-evolution", "attested-schema-evolution.json")
    ],
    "prepare-cedar-manifest": [
        manifest("ticket-sharing"),
        source("Productions/Governance/ExpandedPolicy.lean", "expanded-policy.json"),
    ],
    "prepare-source-case-manifests": [manifest("clinical"), manifest("attested")],
    "prepare-wearable-triage-manifest": [manifest("wearable-triage")],
    "prepare-language-manifest": [manifest("scope-pattern")],
    "prepare-network-manifest": [manifest("network")],
    "prepare-country-manifest": [manifest("country-approval")],
    "prepare-purchase-manifest": [manifest("purchase-approval")],
    "prepare-delegated-manifest": [
        manifest("delegated-approval"),
        source("Productions/Enterprise/Procurement/PublishedPolicy.lean", "delegated-published.json"),
    ],
    "prepare-delegated-matrix": [manifest("delegated-matrix")],
    "prepare-payment-manifest": [
        manifest("payment-release"),
        source("Productions/Enterprise/Payment/PublishedPayment.lean", "payment-published.json"),
    ],
    "prepare-agent-manifest": [manifest("agent-delegation")],
    "prepare-agent-chain-manifest": [manifest("agent-chain")],
    "prepare-agent-payment-manifest": [manifest("agent-payment")],
    "prepare-agent-data-flow-manifest": [manifest("agent-data-flow")],
    "prepare-bounded-session-manifest": [manifest("bounded-session")],
    "prepare-shared-budget-manifest": [manifest("shared-budget")],
    "prepare-supplier-transition-manifest": [manifest("supplier-transition")],
    "prepare-vla-command-manifest": [manifest("vla-command")],
    "prepare-mission-successor-manifest": [manifest("mission-successor")],
    "prepare-extension-manifest": [manifest("extension-coverage")],
    "prepare-tenant-device-manifest": [manifest("tenant-device")],
    "prepare-all-manifests": [
        (MANIFEST, "all", None),
        source("Productions/Governance/ExpandedPolicy.lean", "expanded-policy.json"),
        source("Productions/Enterprise/Procurement/PublishedPolicy.lean", "delegated-published.json"),
        source("Productions/Enterprise/Payment/PublishedPayment.lean", "payment-published.json"),
        source("Productions/Governance/TemplateSourceExport.lean", "template-source-bundle.json"),
        source("Productions/Governance/TemplateSourceExport.lean", "mixed-template-source-bundle.json", "mixed"),
    ],
}


def prepare(name: str, repository: Path) -> None:
    repository = repository.resolve()
    for path, selector, output in PREPARE[name]:
        command = [
            "timeout", "--signal=TERM", "--kill-after=3s", "120s",
            "lake", "env", "lean", "-M", "2048", "-T", "10000000",
            "--run", str(path),
        ]
        if selector:
            command.append(selector)
        if output is None:
            subprocess.run(command, cwd=repository, check=True)
        else:
            target = repository / output
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open("wb") as stream:
                subprocess.run(command, cwd=repository, stdout=stream, check=True)
            print(f"prepared {output}")

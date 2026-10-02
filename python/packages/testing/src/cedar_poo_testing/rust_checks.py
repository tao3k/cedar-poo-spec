"""Rust feature dependency boundaries, lint gates, and independent consumers."""

from pathlib import Path
import subprocess


COMMERCE = (
    "agentic-ai-commerce-signatures", "agentic-ai-commerce-projection",
    "agentic-ai-commerce-admission", "agentic-ai-commerce-budget-commit",
    "agentic-ai-commerce-credential",
)


def run(repository: Path) -> None:
    repository = repository.resolve()
    base = ["--locked", "--manifest-path", "rust/Cargo.toml"]

    def cargo(command: str, *args: str) -> None:
        subprocess.run(["cargo", command, *base, *args], cwd=repository, check=True)

    build = repository / ".lake/build"
    build.mkdir(parents=True, exist_ok=True)
    for feature in (None, "google-sdp", *COMMERCE):
        args = ["--no-default-features"]
        if feature:
            args += ["--features", feature]
        tree = subprocess.check_output(
            ["cargo", "tree", *base, *args, "-e", "normal", "-p", "cedar-poo-bridge"],
            cwd=repository, text=True,
        )
        (build / f"bridge-{feature or 'default'}-tree.txt").write_text(tree)
        if "cedar-policy" in tree:
            raise ValueError(f"{feature or 'default'} unexpectedly depends on Cedar runtime")
        if ("p256" in tree) != (feature in COMMERCE):
            raise ValueError(f"{feature or 'default'} has an unexpected P-256 dependency")
    subprocess.run(["cargo", "fmt", "--manifest-path", "rust/Cargo.toml", "--check"],
                   cwd=repository, check=True)
    cargo("clippy", "--all-targets", "--no-default-features", "--", "-D", "warnings")
    for feature in ("google-sdp", *COMMERCE, "cedar-runtime", "google-sdp-host"):
        cargo("clippy", "--all-targets", "--features", feature, "--", "-D", "warnings")
    cargo("test", "--no-default-features")
    for feature in ("google-sdp", "agentic-ai-commerce-signatures", "cedar-runtime", "google-sdp-host"):
        cargo("test", "--features", feature)
    cargo("test", "--no-default-features", "--features", "agentic-ai-commerce-admission",
          "--test", "agentic_ai_commerce_admission_consumer")

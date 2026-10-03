"""Check the pinned ticket-sharing CPC experiment against an Ethos reference.

This checks the renamed SMT query. It does not prove that renaming the original
Cedar query preserves its semantics or discharge the Lean UNSAT premise.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


EXPECTED_SOURCE_SHA256 = "93ee56de8354e4b38044b225290b4a58f4b476fc6377dfbbc4c41e96ff627de5"
CONSTRUCTORS = {"E0": 3, "E1": 3, "R2": 1, "R3": 1}


def run(command: list[str], *, timeout: int = 120) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, capture_output=True, timeout=timeout, check=False)


def require_success(result: subprocess.CompletedProcess[str], stage: str) -> None:
    if result.returncode != 0:
        raise RuntimeError(
            f"{stage} failed ({result.returncode}): "
            f"stdout={result.stdout[:500]!r} stderr={result.stderr[:500]!r}"
        )


def check(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--cvc5", required=True)
    parser.add_argument("--ethos", required=True)
    parser.add_argument("--signature-root", type=Path, required=True)
    args = parser.parse_args(argv)

    cvc5_version = run([args.cvc5, "--version"])
    require_success(cvc5_version, "cvc5 version check")
    if not cvc5_version.stdout.startswith("cvc5 1.3.4\n"):
        raise RuntimeError(f"expected cvc5 1.3.4: {cvc5_version.stdout[:100]!r}")
    ethos_version = run([args.ethos, "--show-config"])
    require_success(ethos_version, "Ethos version check")
    if not ethos_version.stdout.startswith("This is ethos version 0.2.4.\n"):
        raise RuntimeError(f"expected Ethos 0.2.4: {ethos_version.stdout[:100]!r}")

    source = args.input.read_bytes()
    digest = hashlib.sha256(source).hexdigest()
    if digest != EXPECTED_SOURCE_SHA256:
        raise RuntimeError(f"unexpected Cedar query SHA-256: {digest}")
    text = source.decode("utf-8")
    if not text.startswith("(reset)\n"):
        raise RuntimeError("expected one initial solver reset")
    text = text.removeprefix("(reset)\n")
    for name, count in CONSTRUCTORS.items():
        text, actual = re.subn(r"\(" + name + r"(?=\s)", "(mk" + name, text)
        if actual != count:
            raise RuntimeError(f"expected {count} constructor uses of {name}, found {actual}")

    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    reference = output / "authorization-delta-ethos.smt2"
    reference.write_text(text)
    cvc5 = run([
        args.cvc5, "--lang=smt", "--produce-proofs", "--proof-check=lazy",
        "--dump-proofs", "--proof-format-mode=cpc", str(reference),
    ])
    require_success(cvc5, "cvc5")
    if not cvc5.stdout.startswith("unsat\n"):
        raise RuntimeError(f"cvc5 did not report UNSAT: {cvc5.stdout[:200]!r}")

    proof = output / "authorization-delta-ethos.cpc"
    proof.write_text(cvc5.stdout)
    lines = cvc5.stdout.splitlines()
    starts = [i for i, line in enumerate(lines) if line.startswith("(define @t1 ")]
    if len(starts) != 1 or starts[0] < 3 or lines[:2] != ["unsat", "("] or lines[-1] != ")":
        raise RuntimeError("unexpected CPC declaration/definition prefix")
    if "(assume @p1 true)" not in lines or "(assume @p2 t30)" not in lines:
        raise RuntimeError("unexpected CPC assumptions")

    signature = args.signature_root.resolve()
    includes = [signature / "Cpc.eo", signature / "expert/CpcExpert.eo"]
    for path in includes:
        if not path.is_file():
            raise RuntimeError(f"missing cvc5 1.3.4 signature: {path}")

    def proof_with_reference(path: Path) -> Path:
        target = output / ("authorization-delta-ethos-checked.cpc" if path == reference
                           else "authorization-delta-ethos-negative.cpc")
        prefix = [f"(include {json.dumps(str(part))})" for part in includes]
        prefix.append(f"(reference {json.dumps(str(path))})")
        target.write_text("\n".join(prefix + lines[starts[0]:-1]) + "\n")
        return target

    options = [args.ethos, "--reference-define-fun", "--require-proof-of-false"]
    checked = run(options + [str(proof_with_reference(reference))])
    require_success(checked, "Ethos reference check")
    if checked.stdout.strip() != "correct":
        raise RuntimeError(f"Ethos did not certify the renamed reference: {checked.stdout!r}")

    if text.count("(assert t30)\n") != 1:
        raise RuntimeError("expected exactly one final query assertion")
    negative = output / "authorization-delta-ethos-negative.smt2"
    negative.write_text(text.replace("(assert t30)\n", "(assert false)\n"))
    rejected = run(options + [str(proof_with_reference(negative))])
    if rejected.returncode == 0 or "was not part of the referenced assertions" not in rejected.stderr:
        raise RuntimeError("Ethos did not reject the changed reference assertion")

    print(f"ETHOS-OK renamed query; original SHA-256 {digest}; changed assertion rejected")

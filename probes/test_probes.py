"""One parametrized test per probe under probes/cases/."""

from __future__ import annotations

import subprocess
from pathlib import Path

from conftest import COMPILER, Case


def test_probe(case: Case, tmp_path: Path) -> None:
    binary = tmp_path / case.name
    compile_proc = subprocess.run(
        [COMPILER, "--compile", f"--output={binary}", str(case.source)],
        capture_output=True,
    )
    assert compile_proc.returncode == 0, (
        f"compile failed: stdout={compile_proc.stdout!r} "
        f"stderr={compile_proc.stderr!r}"
    )

    run_proc = subprocess.run(
        [str(binary), *case.args],
        capture_output=True,
    )

    assert run_proc.stdout == case.expected_out, (
        f"stdout mismatch: got {run_proc.stdout!r} "
        f"expected {case.expected_out!r}"
    )
    assert run_proc.stderr == case.expected_err, (
        f"stderr mismatch: got {run_proc.stderr!r} "
        f"expected {case.expected_err!r}"
    )
    assert run_proc.returncode == case.expected_exit, (
        f"exit mismatch: got {run_proc.returncode} "
        f"expected {case.expected_exit}"
    )

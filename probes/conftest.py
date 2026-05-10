"""Probe harness for cursed-compiler native-compile behavior.

Each subdirectory of probes/cases/ is one probe. The harness compiles
source.💀 with `cursed-compiler --compile`, runs the produced binary,
and asserts stdout, stderr, and exit code against the expected.* files.
"""

from __future__ import annotations

import os
import shlex
from dataclasses import dataclass
from pathlib import Path

import pytest

CASES_DIR = Path(__file__).parent / "cases"
COMPILER = os.environ.get("CURSED_COMPILER", "cursed-compiler")


@dataclass
class Case:
    name: str
    source: Path
    args: list[str]
    expected_out: bytes
    expected_err: bytes
    expected_exit: int


def _read_args(path: Path) -> list[str]:
    if not path.exists():
        return []
    text = path.read_text().strip()
    return shlex.split(text) if text else []


def _read_bytes(path: Path) -> bytes:
    return path.read_bytes() if path.exists() else b""


def _read_exit(path: Path) -> int:
    return int(path.read_text().strip()) if path.exists() else 0


def discover_cases() -> list[Case]:
    cases: list[Case] = []
    if not CASES_DIR.is_dir():
        return cases
    for case_dir in sorted(p for p in CASES_DIR.iterdir() if p.is_dir()):
        source_candidates = list(case_dir.glob("source.*"))
        if not source_candidates:
            continue
        cases.append(
            Case(
                name=case_dir.name,
                source=source_candidates[0],
                args=_read_args(case_dir / "args"),
                expected_out=_read_bytes(case_dir / "expected.out"),
                expected_err=_read_bytes(case_dir / "expected.err"),
                expected_exit=_read_exit(case_dir / "expected.exit"),
            )
        )
    return cases


def pytest_generate_tests(metafunc: pytest.Metafunc) -> None:
    if "case" in metafunc.fixturenames:
        cases = discover_cases()
        metafunc.parametrize("case", cases, ids=[c.name for c in cases])

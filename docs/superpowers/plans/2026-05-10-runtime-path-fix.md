# Runtime Path Compile Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the active native compiler's `/home/ghuntley` runtime path dependency and make clang/link failures produce a nonzero `cursed-compiler --compile` exit.

**Architecture:** Keep the fix inside the active LLVM pipeline wired by `build.zig`. Add focused probe tests that exercise source-checkout compilation from the repo root and failure propagation when the runtime path is unavailable from the current working directory.

**Tech Stack:** Zig compiler code in `src-zig/llvm_ir_pipeline_complete.zig`; pytest probe tests under `probes/`; downstream brat verification script.

---

## File Structure

- Modify `src-zig/llvm_ir_pipeline_complete.zig`
  - Replace the hardcoded `/home/ghuntley/cursed/src-zig/cursed_runtime.c` with `src-zig/cursed_runtime.c`.
  - Add explicit compile errors for clang execution failure and clang nonzero exit.
  - Return those errors from `compileToNativeBinary`.
- Create `probes/test_runtime_path.py`
  - Tests the active compiler command behavior around runtime path selection and clang failure propagation.
- No changes to old LLVM implementations, interpreter fake paths, cross-compilation search paths, or public CLI parsing.

---

### Task 1: Add Failing Runtime Path Probes

**Files:**
- Create: `probes/test_runtime_path.py`

- [ ] **Step 1: Create probe test file**

Add this exact file:

```python
"""Runtime path behavior for cursed-compiler --compile."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

from conftest import COMPILER


REPO_ROOT = Path(__file__).resolve().parents[1]


def write_source(path: Path) -> None:
    path.write_text(
        'vibe main\n'
        'yeet "vibez"\n'
        '\n'
        'slay main_character() {\n'
        '    vibez.spill("path-check")\n'
        '}\n',
        encoding="utf-8",
    )


def compiler_argv() -> list[str]:
    compiler = Path(COMPILER)
    if compiler.is_absolute() or os.sep in COMPILER:
        return [COMPILER]
    return [str(REPO_ROOT / "zig-out" / "bin" / COMPILER)]


def test_compile_uses_repo_relative_runtime_path(tmp_path: Path) -> None:
    source = tmp_path / "path-check.💀"
    binary = tmp_path / "path-check"
    write_source(source)

    proc = subprocess.run(
        [
            *compiler_argv(),
            "--compile",
            f"--output={binary}",
            str(source),
        ],
        cwd=REPO_ROOT,
        capture_output=True,
    )

    assert proc.returncode == 0, (
        f"compile failed: stdout={proc.stdout!r} stderr={proc.stderr!r}"
    )
    assert binary.exists(), "compile reported success but did not create binary"
    assert b"src-zig/cursed_runtime.c" in proc.stderr
    assert b"/home/ghuntley" not in proc.stderr


def test_missing_runtime_path_returns_nonzero(tmp_path: Path) -> None:
    source = tmp_path / "path-check.💀"
    binary = tmp_path / "path-check"
    write_source(source)

    proc = subprocess.run(
        [
            *compiler_argv(),
            "--compile",
            f"--output={binary}",
            str(source),
        ],
        cwd=tmp_path,
        capture_output=True,
    )

    assert proc.returncode != 0, (
        "compile should fail when src-zig/cursed_runtime.c is not reachable "
        f"from cwd; stdout={proc.stdout!r} stderr={proc.stderr!r}"
    )
    assert not binary.exists()
    assert b"src-zig/cursed_runtime.c" in proc.stderr
```

- [ ] **Step 2: Build current compiler**

Run:

```bash
zig build
```

Expected: command exits 0.

- [ ] **Step 3: Run new probes and confirm they fail for the right reasons**

Run:

```bash
CURSED_COMPILER=cursed-compiler pytest probes/test_runtime_path.py -q
```

Expected before the implementation:

- `test_compile_uses_repo_relative_runtime_path` fails because compile does not create the binary and stderr mentions `/home/ghuntley/cursed/src-zig/cursed_runtime.c`.
- `test_missing_runtime_path_returns_nonzero` fails because `cursed-compiler --compile` returns 0 even after clang fails.

- [ ] **Step 4: Commit failing probes**

Run:

```bash
git add probes/test_runtime_path.py
git commit -m "test: capture runtime path compile failure" \
  -m "Adds probes for the active native compile path: source-checkout runtime linking must not use /home/ghuntley, and clang failure must propagate as a nonzero compiler exit." \
  -m "Co-authored-by: Codex <codex@openai.com>"
```

Expected: commit-msg hook passes.

---

### Task 2: Fix Runtime Path and Failure Propagation

**Files:**
- Modify: `src-zig/llvm_ir_pipeline_complete.zig`

- [ ] **Step 1: Add compile errors for clang failures**

Update the `CompileError` set near the top of `src-zig/llvm_ir_pipeline_complete.zig` from:

```zig
const CompileError = error{ 
    OutOfMemory, 
    InvalidExpression,
    UnsupportedFeature,
    VariableNotFound,
    FunctionNotFound,
};
```

to:

```zig
const CompileError = error{
    OutOfMemory,
    InvalidExpression,
    UnsupportedFeature,
    VariableNotFound,
    FunctionNotFound,
    ClangUnavailable,
    ClangFailed,
};
```

- [ ] **Step 2: Replace hardcoded runtime path and return errors**

In `compileToNativeBinary`, replace the runtime-path and clang-result block with:

```zig
        // Step 3: Automatically invoke clang to compile to native binary.
        // The active source-checkout workflow runs from the repository root.
        const runtime_path = "src-zig/cursed_runtime.c";

        const compile_cmd = try std.fmt.allocPrint(self.allocator,
            "clang -O2 -o {s} {s} {s}", .{ exe_name, ir_file, runtime_path });
        defer self.allocator.free(compile_cmd);

        print("🔧 Compiling to native binary: {s}\n", .{compile_cmd});

        // Execute clang compilation
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "clang", "-O2", "-o", exe_name, ir_file, runtime_path },
            .cwd = null,
        }) catch |err| {
            print("❌ Failed to run clang: {any}\n", .{err});
            print("💡 Make sure clang is installed and accessible\n", .{});
            return CompileError.ClangUnavailable;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited == 0) {
            print("🎉 Successfully compiled CURSED program to native binary: {s}\n", .{exe_name});
            print("💡 Run with: ./{s}\n", .{exe_name});

            // Don't cleanup IR file for debugging
            // std.fs.cwd().deleteFile(ir_file) catch {};
        } else {
            print("❌ Compilation failed with exit code: {}\n", .{result.term.Exited});
            if (result.stderr.len > 0) {
                print("Error output: {s}\n", .{result.stderr});
            }
            print("💡 LLVM IR saved for debugging: {s}\n", .{ir_file});
            return CompileError.ClangFailed;
        }
```

- [ ] **Step 3: Rebuild compiler**

Run:

```bash
zig build
```

Expected: command exits 0.

- [ ] **Step 4: Run focused probes**

Run:

```bash
CURSED_COMPILER=cursed-compiler pytest probes/test_runtime_path.py -q
```

Expected: `2 passed`.

- [ ] **Step 5: Manually verify bytes and exit for minimal compile**

Run:

```bash
cat >/tmp/runtime-path-check.💀 <<'EOF'
vibe main
yeet "vibez"

slay main_character() {
    vibez.spill("path-check")
}
EOF

./zig-out/bin/cursed-compiler --compile --output=/tmp/runtime-path-check /tmp/runtime-path-check.💀 >/tmp/runtime-path-check.compile.out 2>/tmp/runtime-path-check.compile.err
compile_status=$?
/tmp/runtime-path-check >/tmp/runtime-path-check.run.out 2>/tmp/runtime-path-check.run.err
run_status=$?
printf 'compile_status=%s\n' "$compile_status"
printf 'run_status=%s\n' "$run_status"
printf 'stdout_hex='
xxd -p /tmp/runtime-path-check.run.out | tr -d '\n'
printf '\n'
printf 'stderr_hex='
xxd -p /tmp/runtime-path-check.run.err | tr -d '\n'
printf '\n'
rg -n '/home/ghuntley|src-zig/cursed_runtime.c' /tmp/runtime-path-check.compile.err
```

Expected:

```text
compile_status=0
run_status=0
stdout_hex=706174682d636865636b0a
stderr_hex=
```

The final `rg` output contains `src-zig/cursed_runtime.c` and does not contain `/home/ghuntley`.

- [ ] **Step 6: Commit implementation**

Run:

```bash
git add src-zig/llvm_ir_pipeline_complete.zig
git commit -m "fix: use source-checkout runtime path for native compile" \
  -m "Replaces the maintainer-specific /home/ghuntley runtime path with the repo-relative runtime source used by the documented source-checkout workflow. Propagates clang execution and link failures so --compile exits nonzero when no binary is produced." \
  -m "Co-authored-by: Codex <codex@openai.com>"
```

Expected: commit-msg hook passes.

---

### Task 3: Full Verification and Downstream Check

**Files:**
- No code changes expected.

- [ ] **Step 1: Run all probes**

Run:

```bash
CURSED_COMPILER=cursed-compiler pytest probes/ -q
```

Expected: all probes pass.

- [ ] **Step 2: Run `make probes`**

Run:

```bash
make probes
```

Expected: all probes pass. If this fails because `cursed-compiler` is not on `PATH`, rerun:

```bash
PATH="$PWD/zig-out/bin:$PATH" make probes
```

Expected: all probes pass.

- [ ] **Step 3: Run brat downstream verifier**

Run:

```bash
bash ~/brat/experiments/verify_cursed_gaps.sh >/tmp/verify-cursed-gaps-runtime-path.out 2>&1
status=$?
printf 'verify_status=%s\n' "$status"
sed -n '1,220p' /tmp/verify-cursed-gaps-runtime-path.out
```

Expected:

- Script completes with the same substantive gap picture as before.
- Native compile probes no longer depend on `/home/ghuntley`.
- Any command-status change from clang failure propagation is reviewed before finalizing.

- [ ] **Step 4: Check for remaining active hardcoded runtime path**

Run:

```bash
rg -n '/home/ghuntley/cursed/src-zig/cursed_runtime.c|runtime_path = "/home/ghuntley' build.zig src-zig/cursed_compiler_main.zig src-zig/llvm_ir_pipeline_complete.zig
```

Expected: no matches.

- [ ] **Step 5: Confirm git state and recent commits**

Run:

```bash
git status --short
git log --oneline -4
```

Expected:

- `git status --short` is empty.
- Recent commits include the failing probe commit and implementation commit.

---

## Self-Review Checklist

- Spec coverage:
  - Runtime path no longer hardcodes `/home/ghuntley`: Task 2.
  - Clang execution failure and nonzero exit propagate: Task 2.
  - Minimal source-checkout behavior verified from repo root: Tasks 1-3.
  - No public `--runtime-path` or env var added: Task 2 scope.
- Red-flag scan: no incomplete-step markers are present.
- Type consistency:
  - `CompileError.ClangUnavailable` and `CompileError.ClangFailed` are added before use.
  - Probe tests call the active built compiler through `zig-out/bin`.

# Runtime Path Compile Fix Design

## Problem

`cursed-compiler --compile` currently links generated LLVM IR by
passing clang a hardcoded runtime source path:

```text
/home/ghuntley/cursed/src-zig/cursed_runtime.c
```

That path is in the active compiler route wired by `build.zig`:
`src-zig/cursed_compiler_main.zig` imports
`src-zig/llvm_ir_pipeline_complete.zig`, and
`compileToNativeBinary` passes the hardcoded path to clang.

On a machine without that home-directory workaround, native compile
prints a clang error and produces no binary. The compiler still exits
successfully because `compileToNativeBinary` reports clang failure but
does not return an error.

## Goal

Make the active native compile path work from a normal source checkout
without any `/home/ghuntley` symlink or user-specific path, and make
clang/link failure visible through the compiler process exit status.

## Options Considered

### Option A: Minimal source-checkout fix

Use `src-zig/cursed_runtime.c` relative to the current working
directory and return an error when clang fails.

Tradeoffs:

- Smallest upstream patch.
- Matches the documented development flow: run `zig build`, then run
  `./zig-out/bin/cursed-compiler --compile ...` from the repository
  root.
- Does not solve installed binary layouts or invocations from arbitrary
  directories.

### Option B: Runtime discovery

Search for `src-zig/cursed_runtime.c` from likely locations such as the
current working directory, the compiler executable path, and parent
directories.

Tradeoffs:

- Works for more source-tree invocation patterns.
- Avoids adding public CLI surface.
- Adds path-resolution code and edge cases around symlinks, `PATH`
  lookup, and copied binaries.

### Option C: Explicit runtime path

Add a user-facing override such as `--runtime-path=<path>` or
`CURSED_RUNTIME_PATH`, with a default lookup for source checkouts.

Tradeoffs:

- Most flexible for CI, downstream projects, and installed layouts.
- Creates a public interface upstream may not want to support yet.
- Requires more CLI parsing, docs, and tests than this bug needs.

## Decision

Choose Option A for the first upstream contribution.

The bug is already actionable without designing installed-runtime
layout. A minimal patch keeps review focused on removing a
maintainer-specific path and fixing the false-success exit status. If
upstream wants broader invocation support, Options B or C can be a
follow-up discussion.

## Scope

Change only the active build path:

- `src-zig/llvm_ir_pipeline_complete.zig`

Expected behavior:

- `compileToNativeBinary` passes clang `src-zig/cursed_runtime.c`
  instead of `/home/ghuntley/cursed/src-zig/cursed_runtime.c`.
- If clang cannot be executed, return an error.
- If clang exits nonzero, print the existing diagnostic context and
  return an error so `cursed-compiler --compile` exits nonzero.

Out of scope:

- `--runtime-path` or environment-variable overrides.
- Installed runtime packaging.
- Changes to old or parallel LLVM implementations not wired by
  `build.zig`.
- Cleanup of unrelated hardcoded sample paths in interpreter, testing,
  cross-compilation, or platform-probe code.

## Verification

Use a minimal CURSED source file in `/tmp`:

```cursed
vibe main
yeet "vibez"

slay main_character() {
    vibez.spill("path-check")
}
```

Checks:

- With `/home/ghuntley` absent, from the repository root:
  `./zig-out/bin/cursed-compiler --compile --output=/tmp/path-check /tmp/path-check.💀`
  exits 0 and creates `/tmp/path-check`.
- Running `/tmp/path-check` emits the expected bytes for the current
  `vibez.spill` behavior.
- If `src-zig/cursed_runtime.c` is unavailable, compile exits nonzero
  instead of reporting success.
- `make probes` passes.
- `bash ~/brat/experiments/verify_cursed_gaps.sh` runs so downstream
  behavior changes are visible. Command-status differences caused by
  clang failure propagation should be reviewed explicitly.

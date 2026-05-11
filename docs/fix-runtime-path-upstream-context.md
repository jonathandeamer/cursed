# fix-runtime-path-upstream — review & PR context

Branch: `jonathandeamer/cursed:fix-runtime-path-upstream`
Target: `ghuntley/cursed:zig` (the upstream's `zig` branch, **not** our fork's `main`)
State vs target: 5 ahead, 0 behind — ready to PR as-is, no rebase needed.

## What the branch does

Two real fixes in `src-zig/llvm_ir_pipeline_complete.zig`, each paired with a shell regression test, plus a path-hygiene guard.

### Fix 1 — runtime path resolution (`eba3cf3`)

Replaces a hardcoded maintainer-specific path:

```zig
// before
const runtime_path = "/home/ghuntley/cursed/src-zig/cursed_runtime.c";

// after
const runtime_path = try self.resolveRuntimePath();
defer self.allocator.free(runtime_path);
// ...
fn resolveRuntimePath(self: *Self) ![]u8 {
    const exe_dir = try std.fs.selfExeDirPathAlloc(self.allocator);
    defer self.allocator.free(exe_dir);
    return try std.fs.path.resolve(self.allocator, &[_][]const u8{
        exe_dir, "..", "..", "src-zig", "cursed_runtime.c",
    });
}
```

Uses `selfExeDirPathAlloc` + `..` × 2 to hop `zig-out/bin/cursed-compiler` → repo root → `src-zig/cursed_runtime.c`. Independent of cwd and of whose machine built it.

**Caveat — still source-checkout-only.** See "Release-binary gap" below.

### Fix 2 — clang failure propagation (`66aebba`)

Adds two error variants and returns them instead of falling through:

```zig
const CompileError = error{
    // ...existing...
    ClangUnavailable,   // clang couldn't launch
    ClangFailed,        // clang ran and returned nonzero
};
```

Previously, `--compile` printed an error then `return;`d normally, so the CLI exited 0 with no binary produced. Now the caller sees a real error.

### Tests (new `scripts/`, wired via Makefile targets)

- `check-native-runtime-path.sh` — `cd`s into a tmpdir, runs `--compile` from there, asserts the output binary exists and runs, greps stderr to prove `/home/ghuntley` is absent and `src-zig/cursed_runtime.c` is present.
- `check-native-clang-failure.sh` — puts a fake `clang` (`exit 42`) on `PATH`, asserts `--compile` exits nonzero and produces no binary.
- `check-no-personal-paths.sh` — greps `build.zig`, `src-zig/cursed_compiler_main.zig`, `src-zig/llvm_ir_pipeline_complete.zig` for `/home/…` or `/Users/…`. Narrow file list is deliberate — the scripts themselves intentionally contain `/home/ghuntley` strings for regression assertions.

Makefile additions: `path-hygiene`, `native-runtime-path`, `native-clang-failure` targets.

## Review nits worth polishing before opening the PR

1. **`check-native-runtime-path.sh` stderr-grep assumption.** Requires the runtime path to appear in stderr diagnostics. If `--compile` runs cleanly with no output, the assertion may fail spuriously. Confirm the compiler prints the resolved runtime path on success; if it only prints on failure, this assertion is load-bearing on noise.
2. **Relative `./zig-out/bin/cursed-compiler`** in `check-native-clang-failure.sh` — the other script uses `"$(dirname "$0")/.."` to find the repo root. Align for consistency so `make native-clang-failure` works regardless of cwd.

## Release-binary gap (important context for the PR)

Upstream `ghuntley/cursed` ships standalone binaries at tag `v0.0.1`: `cursed-compiler-{linux-x64,macos-arm64,macos-x64,windows-x64.exe}`. Users download just the compiler — no `src-zig/`, no checkout.

For a release-binary user:
- `exe_dir` = `/usr/local/bin` (or wherever they put it)
- Resolved runtime = `/usr/src-zig/cursed_runtime.c` → doesn't exist
- clang fails → thanks to Fix 2, `--compile` now correctly reports `ClangFailed` instead of silently succeeding

So this branch *exposes* the gap rather than hiding it. The gap pre-exists — `v0.0.1`'s `--compile` was already broken for everyone downloading the binary (hardcoded `/home/ghuntley/...`). Our fix doesn't create the problem, just doesn't fully solve it. Our fix only affects future releases built from `zig` after merge — the tagged `v0.0.1` artifacts are frozen and untouched.

### Options considered

1. **Ship option 1 alone (what's on the branch).** Strict improvement; source-checkout builds work for everyone, release-binary users stay broken (same as today).
2. **Add `CURSED_RUNTIME` env-var override.** ~5 lines — check env first, fall back to exe-relative lookup. Unblocks release-binary users without committing to a full install layout.
3. **Embed the runtime in the compiler binary.** The "real" fix — `@embedFile` the C source and write it to a temp path at compile time, or statically link a prebuilt runtime object. Bigger change, out of scope for this branch.

### Decision: ship option 1 only

Reasoning:
- Option 1 is a single coherent idea ("stop hardcoding the runtime path"). A boring, easy-to-approve first PR from an unknown contributor.
- Option 2 introduces a user-facing API (`CURSED_RUNTIME`) — naming, precedence, docs — that the maintainer may prefer to decide themselves. Design choices are where first PRs get stuck.
- The release-binary gap is a pre-existing problem, not one we create. Our PR doesn't regress the release case and doesn't introduce a new release blocker that wasn't already there. Whatever work is needed before the next release ships a working `--compile` (env-var, embedded runtime, or documenting the limitation) was already needed before our PR too.

### What to put in the PR description

- Problem: hardcoded `/home/ghuntley/...` runtime path; silent success when clang fails.
- Fixes: exe-relative runtime lookup; error propagation on clang failure.
- Tests: three new shell checks wired via Makefile.
- **Heads-up section**: flag that `--compile` from release binaries was already broken by the hardcoded path and is still broken after this PR (now with a clean error instead of wrong silent success). Offer two follow-ups — env-var override or embedded runtime — and *ask* the maintainer's preference rather than presenting a decision.

## Links

- Branch: https://github.com/jonathandeamer/cursed/tree/fix-runtime-path-upstream
- Upstream target: https://github.com/ghuntley/cursed/tree/zig
- Upstream release: https://github.com/ghuntley/cursed/releases/tag/v0.0.1

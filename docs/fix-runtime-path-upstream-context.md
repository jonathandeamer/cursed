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
- Tests: two new shell checks wired via Makefile (see "Are all three test scripts necessary?" below for why we're dropping the third).
- **Heads-up section**: flag that `--compile` from release binaries was already broken by the hardcoded path and is still broken after this PR (now with a clean error instead of wrong silent success). Offer two follow-ups — env-var override or embedded runtime — and *ask* the maintainer's preference rather than presenting a decision.

## Should the two fixes be one PR or split?

Considered splitting Fix 1 (runtime path) and Fix 2 (clang failure propagation) into two PRs. Decision: **keep them as one PR.**

**Why not split:**
- Fix 2 earns its keep *because of* Fix 1. Before Fix 1, `--compile` was broken for everyone-not-ghuntley, so silent-success-on-clang-failure was just one symptom among many. After Fix 1, `--compile` actually runs clang for real users, which is exactly when you want clang failures to propagate. They tell a coherent story together: "make `--compile` actually work, and fail loudly when it can't."
- The test for Fix 2 (`check-native-clang-failure.sh`) only works because Fix 1 makes the compiler resolvable in the first place. Splitting means either ordering the PRs (Fix 1 first, then Fix 2) or writing temporary test scaffold that gets thrown away.
- Total diff is small: one Zig file (+24/-6), three shell scripts, a Makefile hunk. Well under the threshold where "too big" becomes a concern.
- Two PRs doubles the review surface — two notifications, two passes, two merges — for a change that a maintainer can review in one sitting.

**What would tip toward splitting:**
- Signal that the maintainer prefers single-purpose PRs as a house style. No such signal on `ghuntley/cursed`.
- Fix 2's error-variant naming (`ClangUnavailable` vs `ClangFailed`) turning into a bikeshed that blocks Fix 1. Low-risk; if it happens, splitting mid-review is trivial.

Default to one PR. If the maintainer asks to split, do it then.

## Are all three test scripts necessary?

Checked the upstream README and `test_suite/` for test-style conventions. Findings:

- README contribution guideline is one line: *"Add tests for new features."* No format prescribed.
- No CONTRIBUTING.md, no AGENTS.md, no CI config enforcing a style.
- `test_suite/` is a dumping ground — dozens of `.log`/`.txt` output captures checked in next to `.💀` source programs and `.ll` LLVM IR files. No shell-script regression checks exist today. Our tests are actually more rigorous than what's there.

Given the loose convention, the question becomes: do our three scripts each justify their presence?

| Script | Tests what? | Keep? |
|---|---|---|
| `check-native-runtime-path.sh` | Fix 1: runtime found when cwd ≠ repo root, no `/home/ghuntley` in diagnostics | **Yes** — directly exercises the bug |
| `check-native-clang-failure.sh` | Fix 2: `--compile` exits nonzero when clang fails | **Yes** — without it, Fix 2 is a trust-me change |
| `check-no-personal-paths.sh` | Future regressions: greps active compiler files for `/home/…` and `/Users/…` | **Drop** — see below |

**Why drop `check-no-personal-paths.sh`:**
- It doesn't test *this* fix. It's a style/hygiene lint preventing a class of future regression.
- The other two scripts prove the fixes; this one introduces a *new project policy* (no personal paths in three specific files). Policy decisions are the maintainer's call, not an unknown contributor's.
- Removing it drops one commit (`eb4b3aa`), one script (17 lines), and one Makefile target (`path-hygiene`). Tightens the commit shape to four commits of pure fix-and-test work.
- If the maintainer likes the idea, offer it in the PR description as a follow-up: *"Happy to add a lint that rejects `/home/...` and `/Users/...` in `build.zig` and the two compiler entry points if you'd like — didn't want to presume."*

### Recommended branch adjustment before opening PR

Drop commit `eb4b3aa` ("test: reject personal home paths in active compiler code"). This removes:
- `scripts/check-no-personal-paths.sh`
- the `path-hygiene` target and its `.PHONY` entry in `Makefile`

Leaves the branch at 4 commits:
1. `4613577` test: capture cwd-independent runtime path
2. `eba3cf3` fix: resolve native runtime path from compiler
3. `e23b457` test: capture native clang failure exit
4. `66aebba` fix: propagate native compile clang failures

## Repo-activity reality check (revises earlier assumptions)

Surveyed the upstream before finalizing. Several signals change the framing:

**The repo is effectively abandoned for PR review.**
- Last commit on `zig`: **2025-09-09** (8+ months ago). Maintainer shipped `v0.0.1`, wrote the README, stopped.
- **5 open PRs, 0 merged.** Oldest from 2025-08-29. Even `t3dotgg`'s PR #7 (emoji identifier support, 16 comments) has sat since 2025-09-24 with no maintainer action. `Badbird5907`'s 10-line Windows ARM64 CI PR has sat 8 months with zero comments.
- Maintainer's total comment engagement: two short replies in 2025-09 across all issues/PRs.
- 633 stars, 38 forks, 12 open issues. No CI besides a release workflow. This is a meme/stunt project that went viral, not an actively maintained one.

**What this changes about the PR strategy:**

1. **Getting merged is unlikely in a useful timeframe.** The PR will almost certainly sit in the queue indefinitely. Don't optimize for "merge this week" — optimize for *"this is a clean, useful artifact on the public record."* Future maintainers or forkers should be able to read it and understand the whole picture without a review conversation.

2. **Flipping the option-1-vs-1+2 decision — now recommend 1+2.** The earlier reasoning against option 2 (env-var override) was "design choices are where first PRs get stuck with reviewers." With no active reviewer, there's no one to get stuck with. Meanwhile:
   - The env-var actually unblocks release-binary users (the population that matters for a public artifact).
   - It's ~5 lines, backward-compatible, no new dependencies.
   - It makes the PR strictly more useful as a standalone artifact.
   - Leaving it out just to be "minimal for a reviewer" when there's no reviewer is optimizing for nothing.

   Recommendation: **add `CURSED_RUNTIME` env-var check in `resolveRuntimePath` — env wins if set, otherwise the exe-relative lookup.** Document the name in the PR description.

3. **Write the PR description as freestanding documentation, not a reviewer-facing ask.**
   - State what was done and why. No "let me know which you prefer" phrasing.
   - Don't ask the maintainer to pick between follow-ups — pick a reasonable default (env-var) and ship it.
   - Mention the embedded-runtime approach as a possible future direction, but don't frame it as a question requiring an answer.

4. **Don't invite peanut-gallery engagement.** PR #7's comment thread is a cautionary tale — drive-by "lgtm works on my machine" comments and self-critical AI-agent remarks. Our PR should not encourage this:
   - Keep the description factual and narrow in scope.
   - Don't lean on AI co-authorship signals in the PR description (the commits already have `Co-authored-by: Codex <codex@openai.com>` — sufficient).
   - Don't phrase things as open questions that invite random votes.

5. **Tone — keep the serious register.** Upstream commits mix serious conventional-commits style with emoji-heavy "🔧 MAJOR FIX: Thing Working!" style. Our commits (`fix: propagate native compile clang failures`) are firmly in the serious register. That signals we're fixing actual bugs, not joining the meme. Don't change it.

6. **Expectations.** Treat this PR as probably-won't-merge. The value is: (a) the branch exists as a clean artifact; (b) it's a good portfolio item; (c) if the maintainer ever returns or someone forks the project, the fix is picked up, already reviewed against the code and documented.

7. **One CI concern to note (minor).** Our new test scripts are POSIX shell with `set -eu` — fine on Linux/macOS, broken on Windows. The upstream's only CI workflow is `release.yml`, not a test matrix, so this won't fail CI today. But if the maintainer ever adds a Windows test job, these scripts won't run there. Worth mentioning in the PR description as a known limitation (or guard the Makefile targets with an OS check).

### Revised recommendation summary

- **Ship fixes 1 + 2 + env-var override.** Add `CURSED_RUNTIME` env check ahead of the exe-relative lookup in `resolveRuntimePath`.
- **Still drop `check-no-personal-paths.sh`** (the policy reasoning from the previous section stands).
- **Final branch shape: 4 commits + 1 new commit for the env-var** → 5 commits, three Zig changes, two shell tests, one Makefile hunk.
- **Write the PR description to stand alone.** Factual, narrow, no asks.

## Links

- Branch: https://github.com/jonathandeamer/cursed/tree/fix-runtime-path-upstream
- Upstream target: https://github.com/ghuntley/cursed/tree/zig
- Upstream release: https://github.com/ghuntley/cursed/releases/tag/v0.0.1

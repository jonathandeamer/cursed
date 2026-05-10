# CLAUDE.md

This file provides guidance to Claude Code and Codex when working in
this repository. `AGENTS.md` is a symlink to this file so both agents
read the same instructions.

## What This Is

CURSED is Geoffrey Huntley's language implemented primarily through the
Zig compiler path in this checkout. The active build target in
`build.zig` installs `zig-out/bin/cursed-compiler` from
`src-zig/cursed_compiler_main.zig`.

This repo contains many specs, examples, generated docs, old result
logs, and parallel implementation experiments. Treat them as context,
not proof that a feature works.

## Verify What Works

- Do not infer implementation status from `README.md`, `specs/`,
  `docs_generated/`, loose `.💀` examples, old `.ll` files, or
  `final_*` / `latest_*` result logs.
- Verify behavior in the current checkout with a minimal program and a
  fresh command run.
- For compiler/runtime work, source reads are not enough. Check the
  full path: parse/codegen output, emitted IR when relevant, clang/link
  behavior, process stdout/stderr bytes, and exit code.
- When testing stdout/stderr/exit semantics, capture bytes explicitly
  with redirection and tools such as `xxd -p`.

`~/brat` currently contains the best downstream audit of the native
compile surface:

- `/home/ec2-user/brat/docs/cursed-subset.md`
- `/home/ec2-user/brat/docs/cursed-gaps.md`
- `/home/ec2-user/brat/experiments/verify_cursed_gaps.sh`

Read those before changing brat-driven compiler/runtime behavior, then
confirm again against this repo.

## Build And Test

Prefer the active Zig compiler path:

```bash
zig build
./zig-out/bin/cursed-compiler example.💀
./zig-out/bin/cursed-compiler --compile --output=/tmp/example example.💀
./zig-out/bin/cursed-compiler --emit-ir --output=/tmp/example.ll example.💀
```

`make build` wraps `zig build`. `make test` currently runs the Zig build
test target, but that may mostly prove the Zig build graph rather than
the behavior of a CURSED language feature. For behavior changes, add or
run focused compile/run probes.

When a change touches semantics, test the relevant execution mode:

- default/interpreter mode, if the bug is in that path;
- native compile mode via `--compile`, then run the produced binary;
- emitted IR via `--emit-ir`, when code generation is the suspected
  failure.

## Working Style

- Use red-green development for fixes: create or identify a minimal
  failing `.💀` reproducer, confirm it fails for the right reason, then
  implement the fix.
- Keep changes primitive-sized: one compiler/runtime behavior per branch
  or PR when possible.
- Identify the active implementation path before editing. `src-zig/`
  contains many `advanced_*`, `*_fixed`, `*_complete`, and
  `llvm_ir_pipeline_*` files that may not be wired into `build.zig`.
- Avoid broad rewrites across parallel old implementations unless the
  task explicitly requires it.
- Use `/tmp` for exploratory probes. Do not add root-level debug files
  or generated result logs unless they are intentional test fixtures.
- Avoid touching `zig-out/`, `build/`, `output/`, `docs_generated/`,
  old result logs, and broad generated reports unless the task is
  specifically about those artifacts.
- The native compile path currently links `src-zig/cursed_runtime.c`;
  verify before changing other runtime-looking files.

## Fork And Contribution Hygiene

This checkout is configured for personal-fork contributions:

- `origin` is `https://github.com/jonathandeamer/cursed`
- `upstream` is `https://github.com/ghuntley/cursed`
- pushing to `upstream` is disabled in this checkout

Treat this as an unauthorised personal fork. Do not imply maintainer
status, do not push directly to upstream, and do not rewrite upstream
history.

Before starting upstreamable work:

```bash
git fetch upstream
git switch zig
git merge --ff-only upstream/zig
git push origin zig
git switch -c <topic-branch>
```

Keep `zig` as the fork's working baseline branch. Create upstreamable
feature or fix work on topic branches from `zig`, and avoid committing
feature work directly to `zig`.

Fork-only workflow notes may live on `zig`, but remember that topic
branches created from `zig` inherit those commits. Before opening an
upstream PR, confirm the branch contains only the intended upstreamable
changes, or branch from `upstream/zig` and cherry-pick the feature
commits.

Prefer topic branches named for the primitive or bug, for example
`fix-compile-ready`, `runtime-stderr-write`, `compiler-argv-access`, or
`stdlib-dropz-read-file`. Do not force-push `zig`. Force-push a personal
topic branch only when no one else is using it.

Use conventional commits, as requested by the README. Useful scopes:

```text
fix(compiler): ...
fix(runtime): ...
test(compiler): ...
docs(specs): ...
```

Prefer commits split by intent: failing test/probe, implementation, docs
update. Tiny changes can combine test and fix, but avoid mixing unrelated
primitives.

For issues and PRs, include issue-shaped evidence: minimal `.💀`
reproducer, exact command, expected output, actual output, platform, and
why the behavior matters. It is fine to mention brat as downstream
motivation, but the CURSED fix should be general rather than brat-only.

## Git Hooks

This repo tracks hooks in `.githooks/`. Enable them in each local clone:

```bash
git config core.hooksPath .githooks
```

The hooks are intentionally light:

- `commit-msg` runs `cz check --commit-msg-file "$1"` to enforce
  conventional commit messages.
- `post-commit` makes a best-effort backup push, but only when the
  branch tracks `origin/*`. Set `CURSED_NO_AUTO_PUSH=1` to disable it.
- `pre-push` refuses pushes to `upstream` and non-fast-forward pushes to
  `zig`.

Do not bypass hooks unless the user explicitly asks or the hook is
broken and you have explained the failure.

## Cross-Repo Learnings

Work in this repo can update brat's CURSED-facing docs. If direct work
in `~/cursed` changes the relationship between brat and CURSED, update
the relevant files in `/home/ec2-user/brat` in the same session:

- `UPSTREAM.md` — CURSED issues, PRs, links, status, and which brat gap
  they address.
- `docs/cursed-subset.md` — verified current behavior of
  `cursed-compiler --compile`.
- `docs/cursed-gaps.md` — brat blockers, failure modes, blocked cases,
  and upstream framing.
- `README.md` — public-facing project status or reviewer entry points.
- `docs/learnings.md` — durable surprises only, using the tag guidance
  in that file.

If direct work in `~/cursed` reveals a CURSED limitation,
compiler/runtime surprise, tooling gap, upstream issue, PR, or other
durable lesson, update:

`/home/ec2-user/brat/docs/learnings.md`

Use the guidance in that file, tag direct CURSED work with
`#cursed-dev`, read `/home/ec2-user/tropes/tropes.md` before drafting,
and commit the brat-doc update in the `~/brat` repo separately from any
CURSED commit.

## Agent Attribution

Both Claude and Codex may work in this repo. When an agent creates or
amends a commit, include that agent's trailer so later readers can tell
who did the work:

```text
Co-authored-by: Claude <noreply@anthropic.com>
Co-authored-by: Codex <codex@openai.com>
```

Do not add agent attribution to commits the agent did not create or
amend.

## Machine-Level Changes

Avoid machine-level workarounds for repo bugs. In particular, do not
create broad home-directory symlinks such as `/home/ghuntley` to satisfy
hardcoded paths. Fix path handling in code/build configuration, or use
the narrowest possible local workaround and document it.

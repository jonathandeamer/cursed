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

Before editing implementation files, verify the path is wired in
`build.zig`; native compile currently links `src-zig/cursed_runtime.c`.

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

## Build, Test, And Fix

Prefer the active Zig compiler path:

```bash
zig build
./zig-out/bin/cursed-compiler example.💀
./zig-out/bin/cursed-compiler --compile --output=/tmp/example example.💀
./zig-out/bin/cursed-compiler --emit-ir --output=/tmp/example.ll example.💀
```

`make build` wraps `zig build`. `make test` currently runs the Zig build
test target, but that may mostly prove the Zig build graph rather than
the behavior of a CURSED language feature.

For compiler/runtime behavior work, use the paired `cursed-tdd` skill.
If skills are unavailable, use this fallback:

1. Reproduce the behavior with the smallest `.💀` program in `/tmp`.
2. Test the relevant execution mode: interpreter, native `--compile`,
   or `--emit-ir` when codegen is suspected. Capture stdout bytes,
   stderr, and exit code; source reads alone are not enough.
3. Add or update a case under `probes/cases/`, then run `make probes`
   (`pytest probes/`). See `probes/README.md`.
4. Run `bash ~/brat/experiments/verify_cursed_gaps.sh`; if a gap moved,
   follow `## Cross-Repo Doc Sync`.

## Working Style

- Keep changes primitive-sized: one compiler/runtime behavior per branch
  or PR when possible.
- Use `/tmp` for exploratory probes. Do not add root-level debug files
  or generated result logs unless they are intentional test fixtures.
- Avoid broad rewrites across parallel old implementations and generated
  artifacts unless the task explicitly requires it.

## Spec Locations

`specs/` holds upstream CURSED language specifications - do not put
session work there. Session brainstorms and implementation plans go
under `docs/superpowers/specs/` and `docs/superpowers/plans/` with
date-prefixed filenames (`YYYY-MM-DD-<topic>.md`).

## Fork And Contribution Hygiene

This checkout is configured for personal-fork contributions:

- `origin` is `https://github.com/jonathandeamer/cursed`
- `upstream` is `https://github.com/ghuntley/cursed`
- pushing to `upstream` is disabled in this checkout

Treat this as an unauthorised personal fork. Do not imply maintainer
status, do not push directly to upstream, and do not rewrite upstream
history.

Before starting upstreamable work, run:

    scripts/upstream-sync.sh <topic-branch>

It handles the fetch, fast-forward from `upstream/zig`, `origin/main`
push, dirty-tree refusal, and topic branch switch.

Keep `main` as the fork's working baseline. Do upstreamable work on topic
branches from `main`; do not commit feature work directly to `main`, and
do not force-push `main`. Force-push a personal topic branch only when no
one else is using it.

Use conventional commits, as requested by the README. Useful scopes:

```text
fix(compiler): ...
fix(runtime): ...
test(compiler): ...
docs(specs): ...
```

Prefer commits split by intent: failing test/probe, implementation, docs
update. Tiny changes can combine test and fix.

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
- `post-commit` is intentionally a no-op; push cursed branches
  explicitly.
- `pre-push` refuses pushes to `upstream` and non-fast-forward pushes to
  `zig`. It also runs `~/brat/experiments/verify_cursed_gaps.sh`
  non-blockingly when the brat checkout is reachable; set
  `CURSED_SKIP_DOWNSTREAM_CHECK=1` to skip that check.

Do not bypass hooks unless the user explicitly asks or the hook is
broken and you have explained the failure.

## Cross-Repo Doc Sync

Use the paired `cross-repo-sync` skill when a change here closes or
surfaces a CURSED gap. If skills are unavailable, walk these brat
tracking files and decide whether each needs an update:

- `~/brat/UPSTREAM.md` - issue/PR row updates or new rows
- `~/brat/docs/cursed-subset.md` - verified current behavior
- `~/brat/docs/cursed-gaps.md` - failure modes; mark closed gaps
- `~/brat/docs/learnings.md` - durable surprises only. Re-read the
  doc's own "When to update" section. Load `~/tropes/tropes.md`
  before drafting; avoid "this changes everything" grandiosity, magic
  adverbs, and `delve`/`tapestry`/`landscape`/`serves as`.

Commit any brat doc update separately in `~/brat`, and reference the
cursed commit SHA in the brat commit body.

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

Keep project skills paired across agents: `cursed-tdd` and
`cross-repo-sync` should match under `~/.claude/skills/` and
`~/.codex/skills/`; after editing one copy, update the other and verify
with `diff -u`.

Claude-only slash commands, permission allowlists, and `SessionStart`
hooks do not have direct Codex equivalents here. Codex uses
`~/.codex/config.toml`, project trust entries, runtime sandbox
approvals, and its own `~/.codex/skills/` support. When a Claude-only
tool drove a non-trivial decision, name it in the commit body so Codex
review can replay the reasoning.

## Machine-Level Changes

Avoid machine-level workarounds for repo bugs. In particular, do not
create broad home-directory symlinks such as `/home/ghuntley` to satisfy
hardcoded paths. Fix path handling in code/build configuration, or use
the narrowest possible local workaround and document it.

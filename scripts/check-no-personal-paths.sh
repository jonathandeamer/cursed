#!/bin/sh
set -eu

paths='build.zig src-zig/cursed_compiler_main.zig src-zig/llvm_ir_pipeline_complete.zig'
pattern='/home/[A-Za-z0-9._-]+|/Users/[A-Za-z0-9._-]+'

if command -v rg >/dev/null 2>&1; then
    matches="$(rg -n "$pattern" $paths || true)"
else
    matches="$(grep -En "$pattern" $paths || true)"
fi

if [ -n "$matches" ]; then
    printf '%s\n' "$matches" >&2
    printf '%s\n' 'personal home-directory path found in active compiler/build code' >&2
    exit 1
fi

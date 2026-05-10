# Probes

Compile-and-run tests for cursed-compiler native-compile behavior.

## Layout

Each subdirectory of `cases/` is one probe:

- `source.💀` - input program
- `args` - shell-quoted args for the produced binary (optional)
- `expected.out` - exact stdout bytes (optional, default empty)
- `expected.err` - exact stderr bytes (optional, default empty)
- `expected.exit` - exit code (optional, default 0)

## Running

    pytest probes/        # all cases
    pytest probes/ -k <name>  # single case
    make probes           # same as `pytest probes/`

## Adding a case

Add a directory under `cases/` with the files above. The harness picks
it up automatically - no test code changes needed. Probes document
*current* runtime behavior. If a probe fails because the runtime now
emits different bytes, decide whether the change was intentional and
update the expected files OR fix the runtime.

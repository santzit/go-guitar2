## tests/README.md — how to run the GoGuitar2 test suite

# GoGuitar2 — Godot Test Suite

Tests live in `tests/` and use Godot's `SceneTree`-based headless runner.

## Quick start

```bash
# From the project root:
GODOT="./Godot_v4.4.1-stable_linux.x86_64"

$GODOT --headless --path . --script tests/test_gdextension.gd
echo "Exit code: $?"
```

Exit code `0` = all tests passed.  Exit code `1` = one or more failures.

## Test files

| File | What it tests |
|---|---|
| `tests/test_gdextension.gd` | GDExtension class registration, PSARC parsing, note field validation, AudioEngine WEM decode |

## DLC files

Place `.psarc` files in the `DLC/` folder next to the project for the
PSARC-dependent tests to run.  Tests gracefully skip when no DLC is present.

## Running without DLC

The class-registration tests and AudioEngine smoke tests run without any
`.psarc` file.  PSARC-specific tests are automatically skipped when DLC is
absent.

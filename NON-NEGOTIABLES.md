# Non-Negotiables

These rules are mandatory for `win-zig-bindgen`.

## Acceptance

- Do not declare the repo green unless `zig build gate` passes.
- If the change touches `emit.zig`, `resolver.zig`, `main.zig`, `build.zig`, `tests/generation_parity.zig`, or `scripts/winui3-*`, also run `pwsh -File ..\win-zig-core\scripts\winui3-verify-all.ps1`.

## Parallel Work

- One file, one writer.
- Shared driver files (`main.zig`, `build.zig`, `README.md`) must have a single owner during a task.
- If two agents need to modify the same file, split by worktree or serialize the edits.

## Test Integrity

- No heuristic text scanning to fake dependency closure.
- No compare-layer hacks without explicit documentation.
- Do not convert a real implementation gap into a passing test by weakening assertions.

## Hygiene

- Do not leave stale script references in docs or gates.
- Do not push partial validation changes without updating the acceptance path they describe.
- GitHub issue and PR operations must target forks, not upstream repos.

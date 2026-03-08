# AGENTS.md

## Project Scope

`win-zig-bindgen` is the WinMD -> Zig generator layer. It owns metadata-driven resolution, code emission, parity tests, and WinUI3 delegate IID support scripts.

Read [NON-NEGOTIABLES.md](C:\Users\yuuji\win-zig-bindgen\NON-NEGOTIABLES.md) first. Those rules override convenience.

## Primary Commands

- Build/test gate: `zig build gate`
- Metadata parity only: `zig build test-md-parity`
- Generation parity only: `zig build test-gen-parity`
- Cross-repo acceptance: `pwsh -File ..\win-zig-core\scripts\winui3-verify-all.ps1`

## Workstreams

| Area | Owner | Typical Files |
|------|-------|---------------|
| Metadata parser | one agent | `coded_index.zig`, `metadata.zig`, `pe.zig`, `streams.zig`, `tables.zig` |
| Resolver/emitter | one agent | `resolver.zig`, `emit.zig` |
| Harness/scripts | one agent | `tests/`, `scripts/`, `docs/` |
| Driver/integration | human or single driver agent | `main.zig`, `build.zig`, `README.md` |

### Ownership Rules

- Do not let multiple agents edit the same file.
- If a change crosses workstreams, the driver owns the merge.
- Treat `main.zig` and `build.zig` as single-owner files for a task.

## Operating Rules

1. Fix compiler failures before semantic failures.
2. Use metadata/resolver semantics for dependency closure. Do not add text-scanning heuristics to make parity pass.
3. If you add normalization in the parity harness, document it as compatibility logic, not as generator completeness.
4. Do not claim completion from local green tests if downstream WinUI3 acceptance is still red.

## Acceptance Policy

- Local completion for generator-only work: `zig build gate`
- Completion for changes that can affect WinUI3 consumers:
  1. `zig build gate`
  2. `pwsh -File ..\win-zig-core\scripts\winui3-verify-all.ps1`

## GitHub Policy

- Create issues/PRs on fork repos only.
- Do not open upstream issues or PRs from this workspace workflow unless explicitly told to.

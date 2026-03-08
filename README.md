# win-zig-bindgen

`win-zig-bindgen` is the WinMD -> Zig code generator (extracted from `ghostty-win/tools/winmd2zig`).

## Current Scope

- WinMD parsing and resolution
- GUID/IID generation
- Delegate IID emit helpers
- Shadow parity assets (`shadow/windows-rs`, mirrored from `microsoft/windows-rs`)
- Metadata source selection:
  - Prefer sibling repo `../win-zig-metadata/lib.zig`
  - Fallback to local `metadata_local.zig`

## Entry Point

- `main.zig`
- `build.zig`

## Included validation scripts

- `scripts/winui3-sync-delegate-iids.ps1`
- `scripts/winui3-delegate-iid-check.ps1`
- `scripts/check-rust-case-map.ps1` (validates `docs/rust-parity-case-map.json`)

Notes:
- `winui3-sync-delegate-iids.ps1` supports `-RepoRoot`, `-ToolDir`, and `-ComPath` to avoid machine-specific absolute paths.
- Defaults prefer sibling `../ghostty-win` when available.

## Single Quality Gate

Run this from `win-zig-bindgen`:

1. `zig build gate`

`gate` includes:
- unit tests
- generated output compile audit
- metadata sync check
- delegate IID/vector checks
- Rust parity case-map validation
- script guard tests

Optional cross-repo checks (outside this repo's gate):
1. `ghostty-win`: `pwsh -File .\scripts\winui3-contract-check.ps1 -Build`
2. `win-zig-core`: `pwsh -File .\scripts\winui3-verify-all.ps1`

If all three repos are siblings, run once from `win-zig-core`:

```powershell
pwsh -File ..\win-zig-core\scripts\winui3-verify-all.ps1
```

For changes under `emit.zig`, `resolver.zig`, `main.zig`, `build.zig`, `tests/generation_parity.zig`, or `scripts/winui3-*`, treat `winui3-verify-all.ps1` as the downstream acceptance gate.

## Third-party provenance

This repo includes a mirrored `windows-rs` shadow corpus used for parity tests.

- upstream: `microsoft/windows-rs`
- copied/derived assets live under `shadow/windows-rs`
- license notices: `THIRD_PARTY_NOTICES.md`
- vendored upstream licenses:
  - `third_party/windows-rs/LICENSE-MIT`
  - `third_party/windows-rs/LICENSE-APACHE-2.0`

## Build Options

- `-Dwin_zig_metadata_path=<path-to-lib.zig>`
  - Explicit metadata module path (highest priority)
  - If omitted: tries sibling `../win-zig-metadata/lib.zig`
  - Final fallback: local `metadata_local.zig`

## Migration note

Source snapshot copied from `ghostty-win` commit `fe9218c`.

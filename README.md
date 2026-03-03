# win-zig-bindgen

`win-zig-bindgen` is the WinMD -> Zig code generator (extracted from `ghostty-win/tools/winmd2zig`).

## Current Scope

- WinMD parsing and resolution
- GUID/IID generation
- Delegate IID emit helpers
- Shadow parity assets (`shadow/windows-rs`)
- Metadata source selection:
  - Prefer sibling repo `../win-zig-metadata/lib.zig`
  - Fallback to local `metadata_local.zig`

## Entry Point

- `main.zig`
- `build.zig`

## Included validation scripts

- `scripts/winui3-sync-delegate-iids.ps1`
- `scripts/winui3-delegate-iid-check.ps1`

Notes:
- `winui3-sync-delegate-iids.ps1` supports `-RepoRoot`, `-ToolDir`, and `-ComPath` to avoid machine-specific absolute paths.
- Defaults prefer sibling `../ghostty-win` when available.

## Recommended Run Order

1. `win-zig-metadata`: `zig build test`
2. `win-zig-bindgen`: `zig build test`
3. `win-zig-bindgen`: `pwsh -File .\scripts\winui3-sync-delegate-iids.ps1 -Check`
4. `ghostty-win`: `pwsh -File .\scripts\winui3-delegate-iid-check.ps1`
5. `ghostty-win`: `pwsh -File .\scripts\winui3-inspect-event-params.ps1`
6. `win-zig-core`: `pwsh -File .\scripts\winui3-contract-run.ps1 -SkipReference -SkipExtractIids`

If all three repos are siblings, run once from `win-zig-core`:

```powershell
pwsh -File ..\win-zig-core\scripts\winui3-verify-all.ps1
```

## Build Options

- `-Dwin_zig_metadata_path=<path-to-lib.zig>`
  - Explicit metadata module path (highest priority)
  - If omitted: tries sibling `../win-zig-metadata/lib.zig`
  - Final fallback: local `metadata_local.zig`

## Migration note

Source snapshot copied from `ghostty-win` commit `fe9218c`.

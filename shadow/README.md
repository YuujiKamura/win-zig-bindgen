# windows-rs Shadow Corpus

`tools/winmd2zig/shadow/windows-rs` is a mirrored corpus from `windows-rs`:

- `bindgen-cases.json`: extracted from `crates/tools/bindgen/src/main.rs`
- `bindgen-golden/*.rs`: copied from `crates/tests/libs/bindgen/src`

Sync commands:

```powershell
zig build winmd2zig-shadow-sync
zig build winmd2zig-shadow-check
```

Direct script:

```powershell
pwsh -File scripts/sync-windowsrs-shadow.ps1
pwsh -File scripts/sync-windowsrs-shadow.ps1 -Check
```

# windows-rs Shadow Corpus

`shadow/windows-rs` is a mirrored corpus from `microsoft/windows-rs`.

Upstream:
- repo: https://github.com/microsoft/windows-rs
- current local reference snapshot used during parity work:
  - `f46dfcfa9ec59d96c14c3accbffcdb837d036798`

Included materials:

- `bindgen-cases.json`: extracted from `crates/tools/bindgen/src/main.rs`
- `bindgen-golden/*.rs`: copied from `crates/tests/libs/bindgen/src`

License:
- upstream is dual licensed under MIT or Apache-2.0
- local copies:
  - `../third_party/windows-rs/LICENSE-MIT`
  - `../third_party/windows-rs/LICENSE-APACHE-2.0`
- repo-level notice:
  - `../THIRD_PARTY_NOTICES.md`

Notes:
- this mirrored corpus is used for parity testing and regression detection
- it is not an endorsement by Microsoft or the `windows-rs` maintainers
- when refreshing this mirror, update the exact upstream commit recorded here

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

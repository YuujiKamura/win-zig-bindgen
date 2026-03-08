## Third-Party Notices

### microsoft/windows-rs

This repository includes a mirrored reference corpus from `microsoft/windows-rs`
for parity testing and regression detection.

Upstream repository:
- https://github.com/microsoft/windows-rs

Upstream license:
- dual licensed under MIT or Apache-2.0, at your option
- vendored copies are included here:
  - `third_party/windows-rs/LICENSE-MIT`
  - `third_party/windows-rs/LICENSE-APACHE-2.0`

Copied or derived materials currently tracked in this repository:
- `shadow/windows-rs/bindgen-cases.json`
  - derived from `windows-rs/crates/tools/bindgen/src/main.rs`
- `shadow/windows-rs/bindgen-golden/*.rs`
  - copied from `windows-rs/crates/tests/libs/bindgen/src`

Purpose of inclusion:
- parity testing against the Rust reference implementation
- regression detection for generated Zig bindings

Project boundary:
- `win-zig-bindgen` is an independent Zig implementation
- the shadow corpus is used as a reference/test artifact
- `ghostty-win/src/apprt/winui3/com_native.zig` is not treated as upstream truth

Provenance note:
- current parity work in this workspace uses a local `windows-rs` reference
  snapshot at commit `f46dfcfa9ec59d96c14c3accbffcdb837d036798`
- when the mirrored shadow corpus is refreshed, record the exact upstream commit
  used for that refresh in `shadow/README.md`

No affiliation:
- this project is not affiliated with or endorsed by Microsoft or the
  `windows-rs` maintainers

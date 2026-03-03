# Rust Parity Test Plan

Goal: converge toward parity with the upstream Rust reference corpus under `shadow/windows-rs`.

Current reference size (snapshot):
- `bindgen-cases.json`: 107 cases
- `bindgen-golden/*.rs`: 108 files

## Phase 1: Nucleus (done in this step)

Increase pure unit tests around core primitives used by many categories:
- coded index decoding
- heap/stream decoding
- GUID/signature generation and parsing

This catches high-impact regressions that would affect many Rust corpus categories (`interface`, `fn`, `reference`, `struct`, `enum`, `delegate`).

## Phase 2: Category parity harness

Add representative parity checks by category, starting with top volume categories:
1. `interface`
2. `fn`
3. `reference`
4. `struct`
5. `enum`
6. `delegate`

For each category, maintain:
- selected reference case IDs from `bindgen-cases.json`
- expected structural invariants in Zig output (ABI shape, signatures, GUID constants, symbol names)

## Phase 3: Full-count target (107)

Expand selected cases until the maintained parity set count reaches Rust case count.

Tracking rule:
- keep a single mapping file of `rust_case -> zig_parity_test`
- CI should fail if mapped case count decreases

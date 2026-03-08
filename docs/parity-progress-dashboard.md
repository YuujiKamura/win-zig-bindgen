# Parity Progress Dashboard (#12)

Updated: 2026-03-08

## Scope

This dashboard tracks measurable progress for:
- Parent roadmap: #12
- Objective: Rust `windows-rs` output parity for Zig generation

## Child Issues

- #15 AST-normalized structural comparator
- #17 Exact function signature parity
- #14 Enum/Struct/Interface shape comparator
- #16 Progress dashboard and % tracking

## Gate Model (Percent Tracking)

Progress % is computed by completed gates / total gates.

- Gate G1: 107-case manifest execution in `test-gen-parity` (strict)  
  Status: done
- Gate G2: Golden file resolution for all cases (`bindgen-golden/*.rs`)  
  Status: done
- Gate G3: Symbol kind-level structural checks (function/constant/type)  
  Status: done
- Gate G4: Exact function signature comparator (normalized)  
  Status: pending (#17)
- Gate G5: Enum/Struct/Interface shape comparator  
  Status: pending (#14)
- Gate G6: AST-normalized full structural diff engine  
  Status: pending (#15)

Current score: **3 / 6 = 50%**

## Current Verification Snapshot

- `zig build test-gen-parity`: pass
- `GEN_PARITY_STRICT=1 zig build test-gen-parity`: pass
- `zig build test-md-parity`: pass

## Exit Criteria (100%)

- G1..G6 all complete
- Parent #12 checklist updated to reflect completion
- CI gate uses strict parity mode without token-fallback paths

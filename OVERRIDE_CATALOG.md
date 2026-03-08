# Hardcoded Method Override Catalog — emit.zig

Generated: 2026-03-07
Source: `C:\Users\yuuji\win-zig-bindgen\emit.zig`

## Summary

There are **18 distinct override entries** (some grouped into a single `if` block) spanning lines 267-649.
They fall into 4 categories based on root cause.

## Generic Code Behavior (for reference)

- **is_getter** = `name starts with "get_" AND param_count == 1` (line 159)
- **BYREF detection**: 0x10 byte is consumed by `decodeSigType`, which returns `*inner_type` (line 841-845)
- **Getter path** (line 259-263): strips leading `*` from vtbl param to get wrapper return type, returns it via `var out: T = undefined; hrCheck(...(self, &out)); return out;`
- **Non-getter path** (line 284-290): all params become wrapper input args; no out-param detection
- **Type resolution** (line 856-883): enums -> `i32`, structs -> short name, interfaces/classes -> `?*anyopaque`

## Override Table

| # | Interface.Method | Lines | Getter? | Override vtbl signature | Override return type | Category | Root Cause |
|---|---|---|---|---|---|---|---|
| 1 | `*.CreateInstance` (param_count >= 2) | 267-283 | No | *(uses generic vtbl)* | `!struct { inner, instance }` | D | COM aggregation pattern: 2 out-params (inner + instance) need special struct return. Unique calling convention. |
| 2 | `ITabView.get_TabItems` | 294-310 | Yes | `(*anyopaque, *?*anyopaque) -> HRESULT` | `!*IVector` | A | BYREF interface pointer. Generic code returns `?*anyopaque`; override refines to `*IVector` and ensures non-null unwrap. |
| 3 | `ITabView.add_TabCloseRequested` / `add_AddTabButtonClick` / `add_SelectionChanged` | 312-332 | No | `(*anyopaque, ?*anyopaque, *EventRegistrationToken) -> HRESULT` | `!EventRegistrationToken` | B | 2 params: handler (in) + token (BYREF out). Generic non-getter treats both as inputs. Needs BYREF out-param tracking. |
| 4 | `IWindow.add_Closed` | 334-350 | No | `(*anyopaque, ?*anyopaque, *EventRegistrationToken) -> HRESULT` | `!EventRegistrationToken` | B | Same pattern as #3: handler (in) + token (BYREF out). |
| 5 | `ITabView.get_SelectedIndex` | 352-364 | Yes | `(*anyopaque, *i32) -> HRESULT` | `!i32` | A | BYREF i32. Generic code should already handle this correctly (vtbl=`*i32`, ret=`i32`). Override only ensures `= 0` init instead of `= undefined`. May be removable. |
| 6 | `ITabView.get_SelectedItem` | 366-378 | Yes | `(*anyopaque, *?*anyopaque) -> HRESULT` | `!*IInspectable` | A | BYREF interface pointer. Generic returns `?*anyopaque`; override refines to `*IInspectable` with non-null unwrap. |
| 7 | `IWindow.get_Content` / `IContentControl.get_Content` | 380-392 | Yes | `(*anyopaque, *?*anyopaque) -> HRESULT` | `!?*IInspectable` | A | BYREF interface pointer. Generic returns `?*anyopaque`; override refines to `?*IInspectable` (nullable, unlike #6). |
| 8 | `ITabViewTabCloseRequestedEventArgs.get_Tab` | 394-406 | Yes | `(*anyopaque, *?*anyopaque) -> HRESULT` | `!*IInspectable` | A | BYREF interface pointer. Same pattern as #6. |
| 9 | `*.put_Content` / `*.put_Background` / `*.put_Header` | 408-417 | No | *(vtbl not overridden)* | `!void` | D | Wrapper-only override: forces param type to `?*anyopaque`. Generic code may already produce this via the "unknown type -> ?*anyopaque" fallback, but override ensures consistent shape. |
| 10 | `*.remove_*` (param_count == 1) | 419-430 | No | `(*anyopaque, EventRegistrationToken) -> HRESULT` | `!void` | C | EventRegistrationToken is a struct/value type (i64). Generic code sees BYREF token? No -- `remove_` takes token by value. Generic code may mis-resolve the token type. Needs EventRegistrationToken type recognition. |
| 11 | `IFrameworkElement.add_Loaded` / `add_SizeChanged` | 432-448 | No | `(*anyopaque, ?*anyopaque, *EventRegistrationToken) -> HRESULT` | `!EventRegistrationToken` | B | Same pattern as #3/#4: handler (in) + token (BYREF out). |
| 12 | `IApplicationFactory.CreateInstance` | 450-453 | No | `(*anyopaque, ?*anyopaque, *?*anyopaque, *?*anyopaque) -> HRESULT` | *(wrapper not overridden, only vtbl)* | D | vtbl-only fix: 3 params (outer, inner-out, instance-out). Generic vtbl may mis-decode the param types. Works with override #1 for wrapper. |
| 13 | `IXamlMetadataProvider.GetXmlnsDefinitions` | 455-479 | No | `(*anyopaque, *u32, *?*anyopaque) -> HRESULT` | `!struct { count, definitions }` | B | 2 BYREF out-params (count + array pointer). Generic non-getter treats both as inputs. Unique multi-out pattern. |
| 14 | `IXamlMetadataProvider.GetXamlType` / `GetXamlType_2` | 481-499 | No | `(*anyopaque, ?*anyopaque, *?*anyopaque) -> HRESULT` | `!*IXamlType` | B | 2 params: type-name/GUID (in) + IXamlType (BYREF out). Generic non-getter treats both as inputs. |
| 15 | `IXamlType.ActivateInstance` | 501-517 | No* | `(*anyopaque, *?*anyopaque) -> HRESULT` | `!*IInspectable` | A | param_count=1 but name != `get_*`, so `is_getter=false`. Has single BYREF out-param. Generic non-getter treats it as input. Would need is_getter expansion or BYREF out-param tracking. |
| 16 | `ISolidColorBrush.put_Color` | 519-531 | No | `(*anyopaque, Color) -> HRESULT` | `!void` | C | Color is a struct (4 bytes: a,r,g,b). Generic code resolves to struct short name if `identifyTypeCategory` works, otherwise falls to `?*anyopaque`. Needs struct type pass-by-value support. |
| 17 | `IPanel.get_Children` | 533-549 | Yes | `(*anyopaque, *?*anyopaque) -> HRESULT` | `!*IVector` | A | BYREF interface pointer. Same pattern as #2. |
| 18 | `IGrid.get_RowDefinitions` | 551-567 | Yes | `(*anyopaque, *?*anyopaque) -> HRESULT` | `!*IVector` | A | BYREF interface pointer. Same pattern as #2. |
| 19 | `IResourceDictionary.get_MergedDictionaries` | 569-585 | Yes | `(*anyopaque, *?*anyopaque) -> HRESULT` | `!*IVector` | A | BYREF interface pointer. Same pattern as #2. |
| 20 | `IResourceDictionary.get_ThemeDictionaries` | 587-603 | Yes | `(*anyopaque, *?*anyopaque) -> HRESULT` | `!*anyopaque` | A | BYREF interface pointer. Returns raw `*anyopaque` (untyped). |
| 21 | `IGridStatics.SetRow` / `SetColumn` | 605-617 | No | `(*anyopaque, ?*anyopaque, i32) -> HRESULT` | `!void` | C | Mixed param types: interface ptr + i32 enum. Generic code may mis-resolve the i32 (enum) param type or the interface param. |
| 22 | `IRowDefinition.put_Height` | 619-631 | No | `(*anyopaque, GridLength) -> HRESULT` | `!void` | C | GridLength is a struct passed by value. Generic code needs struct pass-by-value support. |
| 23 | `IRowDefinition.get_Height` | 633-649 | Yes | `(*anyopaque, *GridLength) -> HRESULT` | `!GridLength` | C | BYREF struct (GridLength). Generic getter path would produce `*GridLength` in vtbl and `GridLength` return -- likely correct if struct is recognized. Override ensures proper zero-init. |

\* `ActivateInstance` has param_count=1 but does NOT start with `get_`, so `is_getter` is false.

## Category Summary

### Category A: BYREF getters (10 overrides)

Overrides: #2, #5, #6, #7, #8, #15, #17, #18, #19, #20

These are single-BYREF-out-param methods where the generic getter path (`is_getter=true`) would actually produce correct ABI signatures. The overrides exist primarily to:
- **Refine return types** from `?*anyopaque` to specific types (`*IVector`, `*IInspectable`, etc.)
- **Ensure non-null unwrap** (`.?` on the result pointer)
- **Zero-initialize** out vars instead of `undefined`

**BYREF fix impact**: If `decodeSigType` properly handles BYREF, the vtbl signatures would be correct without overrides. However, the **type refinement** (returning `*IVector` instead of `?*anyopaque`) would still require either overrides or a type-mapping table.

**Exception**: #15 (`ActivateInstance`) is NOT detected as a getter because its name doesn't start with `get_`. It would need `is_getter` logic expansion OR generic BYREF out-param detection.

**Exception**: #5 (`get_SelectedIndex`) may already work generically since `i32` is a builtin type.

### Category B: BYREF non-getters with out-params (5 overrides)

Overrides: #3, #4, #11, #13, #14

These have multiple parameters where the last one (or last two) are BYREF out-params. The generic non-getter path treats ALL params as inputs. Fixing these requires:
1. BYREF detection in the non-getter path
2. Recognizing the last BYREF param(s) as out-params
3. Generating `var out: T; ...; return out;` wrapper code

**Sub-patterns**:
- `add_*` event handlers (#3, #4, #11): handler-in + token-out -> returns token
- `GetXamlType` (#14): type-ref-in + IXamlType-out -> returns IXamlType
- `GetXmlnsDefinitions` (#13): count-out + array-out -> returns struct (unique)

### Category C: Struct/enum value types (5 overrides)

Overrides: #10, #16, #21, #22, #23

These involve value types (structs or enums) that need to be passed or returned by value at the ABI level, not as pointers:
- `EventRegistrationToken` (i64 alias) — #10
- `Color` (4-byte struct) — #16
- `GridLength` (struct with f64 + i32) — #22, #23
- `i32` enum params — #21

**Fix needed**: The struct/enum type resolution in `decodeSigType` (lines 856-883) already handles enums (`-> i32`) and structs (`-> short_name`). These overrides may become unnecessary if the struct definitions are emitted AND the type is recognized in vtbl param generation. Some may already work after the enum fix.

### Category D: Other special cases (3 overrides)

Overrides: #1, #9, #12

These have unique patterns that likely need to remain hardcoded:
- **#1** (`CreateInstance`): COM aggregation with 2 out-params returning a struct
- **#9** (`put_Content/Background/Header`): Wrapper param type coercion (may already work generically)
- **#12** (`IApplicationFactory.CreateInstance`): vtbl-only fix for 3-param factory pattern

## Removability Assessment After BYREF Fix

| After fix | Overrides | Count |
|---|---|---|
| Likely removable (ABI correct, type = anyopaque acceptable) | #5, #9 | 2 |
| Removable if type refinement table added | #2, #6, #7, #8, #15, #17, #18, #19, #20 | 9 |
| Removable if BYREF out-param tracking added to non-getter path | #3, #4, #11, #14 | 4 |
| Removable if struct pass-by-value fully supported | #10, #16, #21, #22, #23 | 5 |
| Likely must remain hardcoded | #1, #12, #13 | 3 |

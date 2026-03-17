# Delegate Implementation Template Generation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make win-zig-bindgen generate provider-side delegate implementations so ghostty-win's hand-written `delegate_runtime.zig` can be eliminated.

**Architecture:** Currently `emitDelegate` for WinRT delegates falls back to `emitInterface` which only emits a consumer-side vtable struct. We add a `pub fn Impl(Context, CallbackFn) type` method to each generated delegate struct that returns a provider-side box with heap allocation, ref-counting, QI, IMarshal, and callback dispatch — exactly what `delegate_runtime.zig`'s `TypedDelegate` provides today. The runtime helpers (`com_runtime.zig`, `marshaler_runtime.zig`) stay in ghostty-win; the generated code imports and uses them.

**Tech Stack:** Zig, WinMD metadata, COM/WinRT delegate ABI

---

## Background

### The Problem

ghostty-win has 185 lines of hand-written `delegate_runtime.zig` that implements `TypedDelegate(Context, CallbackFn)` — a generic COM delegate provider. This is used ~15 times in Surface.zig and caption_buttons.zig. The generator should produce this code per delegate type.

### Current vs Desired

**Current generated output** (consumer-only, from `emitInterface`):
```zig
pub const RoutedEventHandler = extern struct {
    pub const IID = GUID{ ... };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface, AddRef, Release,
        GetIids, GetRuntimeClassName, GetTrustLevel,  // IInspectable
        Invoke: *const fn(*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn invoke(...) ...
    pub fn new() !*@This() { return error.NotImplemented; }  // ← THE GAP
};
```

**Desired**: keep the above, replace `new()` with:
```zig
    pub fn Impl(comptime Context: type, comptime CallbackFn: type) type {
        return DelegateBox(Context, CallbackFn, @This());
    }
```

Where `DelegateBox` is a shared generic (emitted once per file or imported from a runtime module) that provides:
- Heap allocation with `create` / `createWithIid`
- Atomic ref-counting (AddRef/Release, destroy on zero)
- QI for IUnknown + IAgileObject + delegate IID + IMarshal
- Invoke dispatch through `callback(context, sender, args)`
- `comPtr()` for passing to COM event registration

### IID Duality

Two different GUIDs exist per delegate type:
- **Metadata IID** (`RoutedEventHandler.IID` = `0xdae23d85`): the COM interface definition GUID
- **Parameterized IID** (`IID_RoutedEventHandler` = `0xaf8dae19`): the WinRT signature hash used for QI validation

Currently these are handled separately (metadata IID on the struct, parameterized IID as a top-level constant passed via `createWithIid`). This plan preserves that pattern — `createWithIid` accepts the parameterized IID at runtime. Generating parameterized IID computation is a separate future task.

### Usage Pattern in ghostty-win (what stays the same)

```zig
// Before (hand-written):
const delegate_runtime = @import("delegate_runtime.zig");
const LoadedDelegate = delegate_runtime.TypedDelegate(Surface, *const fn (*Surface, *anyopaque, *anyopaque) void);
const d = try LoadedDelegate.createWithIid(alloc, self, &onLoaded, &com.IID_RoutedEventHandler);
_ = ui_element.AddLoaded(d.comPtr());

// After (generated):
const LoadedDelegate = com.RoutedEventHandler.Impl(Surface, *const fn (*Surface, *anyopaque, *anyopaque) void);
const d = try LoadedDelegate.createWithIid(alloc, self, &onLoaded, &com.RoutedEventHandler.IID);
_ = ui_element.AddLoaded(d.comPtr());
```

---

## Task 1: Add DelegateBox test — verify shape requirement

**Files:**
- Create: `tests/bindgen/winui/delegate_impl.zig`
- Modify: `tests/bindgen/winui.zig` (add import)

**Step 1: Write the failing test**

Add `tests/bindgen/winui/delegate_impl.zig`:
```zig
const std = @import("std");
const support = @import("test_support");
const generateWinuiOutput = support.winui.generateWinuiOutput;

test "WINUI RoutedEventHandler: has Impl function" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "RoutedEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    // The generated struct must have a `pub fn Impl` that returns a type
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn Impl(") != null);
}

test "WINUI RoutedEventHandler: Impl has create and createWithIid" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "RoutedEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn create(") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn createWithIid(") != null);
}

test "WINUI RoutedEventHandler: Impl has comPtr" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "RoutedEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn comPtr(") != null);
}

test "WINUI SizeChangedEventHandler: has Impl function" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "SizeChangedEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn Impl(") != null);
}

test "WINUI ScrollEventHandler: has Impl function" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "ScrollEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn Impl(") != null);
}

test "WINUI SelectionChangedEventHandler: has Impl function" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "SelectionChangedEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn Impl(") != null);
}

test "WINUI RoutedEventHandler: no error.NotImplemented" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "RoutedEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    // new() should no longer return error.NotImplemented
    try std.testing.expect(std.mem.indexOf(u8, generated, "error.NotImplemented") == null);
}
```

**Step 2: Add import to winui.zig**

In `tests/bindgen/winui.zig`, add:
```zig
pub const delegate_impl = @import("winui/delegate_impl.zig");
```

**Step 3: Run test to verify it fails**

Run: `zig build test 2>&1 | tail -20`
Expected: FAIL — "pub fn Impl(" not found in generated output

**Step 4: Commit**

```bash
git add tests/bindgen/winui/delegate_impl.zig tests/bindgen/winui.zig
git commit -m "test: add delegate Impl generation shape tests (#88)"
```

---

## Task 2: Emit `Impl` function in WinRT delegate structs

**Files:**
- Modify: `emit.zig` — `emitDelegate` function (line 1068-1137)

The key change: for WinRT delegates, after calling `emitInterface` (which generates the consumer struct), inject a `pub fn Impl(...)` method inside the struct.

**Step 1: Understand current flow**

`emitDelegate` at line 1075-1077:
```zig
if (is_winrt) {
    try emitInterface(allocator, writer, ctx, "", type_name);
    return;
}
```

`emitInterface` writes the full struct including closing `};`. We need to inject the `Impl` function before the struct closes.

**Approach**: Modify `emitInterface` to accept an optional delegate flag, or post-process by injecting before the final `};`. The cleanest approach is to add a parameter to `emitInterface` that triggers delegate Impl emission.

**Step 2: Add delegate Impl emission**

In `emitDelegate`, change the WinRT path to:
```zig
if (is_winrt) {
    try emitInterface(allocator, writer, ctx, "", type_name);
    // Inject Impl function after the interface struct
    try emitDelegateImpl(writer, type_name);
    return;
}
```

Add new function `emitDelegateImpl`:
```zig
fn emitDelegateImpl(writer: anytype, type_name: []const u8) !void {
    // The emitInterface already closed the struct with `};`
    // We need to reopen or inject before close.
    // Actually, we write a standalone function that references the delegate type.
    // This is emitted OUTSIDE the struct as a companion.
    try writer.print(
        \\pub fn {0s}Impl(comptime Context: type, comptime CallbackFn: type) type {{
        \\    return struct {{
        \\        const Self = @This();
        \\        const Delegate = {0s};
        \\
        \\        pub const ComHeader = extern struct {{
        \\            lpVtbl: *const Delegate.VTable,
        \\        }};
        \\
        \\        com: ComHeader,
        \\        allocator: @import("std").mem.Allocator,
        \\        ref_count: @import("std").atomic.Value(u32),
        \\        context: *Context,
        \\        callback: CallbackFn,
        \\        delegate_iid: ?*const GUID = null,
        \\
        \\        const vtable_instance = Delegate.VTable{{
        \\            .QueryInterface = &queryInterfaceFn,
        \\            .AddRef = &addRefFn,
        \\            .Release = &releaseFn,
        \\            .GetIids = null,
        \\            .GetRuntimeClassName = null,
        \\            .GetTrustLevel = null,
        \\            .Invoke = &invokeFn,
        \\        }};
        \\
        \\        pub fn create(allocator: @import("std").mem.Allocator, context: *Context, callback: CallbackFn) !*Self {{
        \\            const self = try allocator.create(Self);
        \\            self.* = .{{
        \\                .com = .{{ .lpVtbl = &vtable_instance }},
        \\                .allocator = allocator,
        \\                .ref_count = @import("std").atomic.Value(u32).init(1),
        \\                .context = context,
        \\                .callback = callback,
        \\            }};
        \\            return self;
        \\        }}
        \\
        \\        pub fn createWithIid(allocator: @import("std").mem.Allocator, context: *Context, callback: CallbackFn, iid: *const GUID) !*Self {{
        \\            const self = try allocator.create(Self);
        \\            self.* = .{{
        \\                .com = .{{ .lpVtbl = &vtable_instance }},
        \\                .allocator = allocator,
        \\                .ref_count = @import("std").atomic.Value(u32).init(1),
        \\                .context = context,
        \\                .callback = callback,
        \\                .delegate_iid = iid,
        \\            }};
        \\            return self;
        \\        }}
        \\
        \\        pub fn comPtr(self: *Self) *anyopaque {{
        \\            return @ptrCast(&self.com);
        \\        }}
        \\
        \\        pub fn release(self: *Self) void {{
        \\            _ = self.com.lpVtbl.Release(self.comPtr());
        \\        }}
        \\
        \\        fn fromComPtr(ptr: *anyopaque) *Self {{
        \\            const header: *ComHeader = @ptrCast(@alignCast(ptr));
        \\            return @fieldParentPtr("com", header);
        \\        }}
        \\
        \\        fn queryInterfaceFn(this: *anyopaque, riid: *const GUID, ppv: *?*anyopaque) callconv(.winapi) HRESULT {{
        \\            const IID_IUnknown = GUID{{ .data1 = 0x00000000, .data2 = 0x0000, .data3 = 0x0000, .data4 = .{{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 }} }};
        \\            const IID_IAgileObject = GUID{{ .data1 = 0x94ea2b94, .data2 = 0xe9cc, .data3 = 0x49e0, .data4 = .{{ 0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90 }} }};
        \\            const self = fromComPtr(this);
        \\            if (guidEql(riid, &IID_IUnknown) or guidEql(riid, &IID_IAgileObject)) {{
        \\                ppv.* = this;
        \\                _ = self.ref_count.fetchAdd(1, .monotonic);
        \\                return S_OK;
        \\            }}
        \\            if (self.delegate_iid) |iid| {{
        \\                if (guidEql(riid, iid)) {{
        \\                    ppv.* = this;
        \\                    _ = self.ref_count.fetchAdd(1, .monotonic);
        \\                    return S_OK;
        \\                }}
        \\            }}
        \\            ppv.* = null;
        \\            return E_NOINTERFACE;
        \\        }}
        \\
        \\        fn addRefFn(this: *anyopaque) callconv(.winapi) u32 {{
        \\            const self = fromComPtr(this);
        \\            return self.ref_count.fetchAdd(1, .monotonic) + 1;
        \\        }}
        \\
        \\        fn releaseFn(this: *anyopaque) callconv(.winapi) u32 {{
        \\            const self = fromComPtr(this);
        \\            const prev = self.ref_count.fetchSub(1, .monotonic);
        \\            const next = prev - 1;
        \\            if (next == 0) self.allocator.destroy(self);
        \\            return next;
        \\        }}
        \\
        \\        fn invokeFn(this: *anyopaque, sender: ?*anyopaque, args: ?*anyopaque) callconv(.winapi) HRESULT {{
        \\            const self = fromComPtr(this);
        \\            const cb_ptr_info = @typeInfo(CallbackFn).pointer;
        \\            const fn_info = @typeInfo(cb_ptr_info.child).@"fn";
        \\            const sender_t = fn_info.params[1].type.?;
        \\            const args_t = fn_info.params[2].type.?;
        \\            if (sender_t == ?*anyopaque and args_t == ?*anyopaque) {{
        \\                self.callback(self.context, sender, args);
        \\            }} else if (sender_t == ?*anyopaque and args_t == *anyopaque) {{
        \\                const a = args orelse return S_OK;
        \\                self.callback(self.context, sender, a);
        \\            }} else if (sender_t == *anyopaque and args_t == ?*anyopaque) {{
        \\                const s = sender orelse return S_OK;
        \\                self.callback(self.context, s, args);
        \\            }} else {{
        \\                const s = sender orelse return S_OK;
        \\                const a = args orelse return S_OK;
        \\                self.callback(self.context, s, a);
        \\            }}
        \\            return S_OK;
        \\        }}
        \\    }};
        \\}}
        \\
    , .{type_name});
}
```

**Note**: This emits `RoutedEventHandlerImpl(Context, CallbackFn)` as a standalone pub function alongside the `RoutedEventHandler` struct. This avoids modifying `emitInterface` internals.

**Important**: The generated code references `GUID`, `HRESULT`, `S_OK`, `E_NOINTERFACE`, `guidEql` — these must already be declared at the top of com_generated.zig (they are, as part of the standard preamble).

**Step 3: Also remove `error.NotImplemented` from `new()`**

In `emitInterface`, find where `new()` is emitted and change it to reference the Impl function, or simply remove `new()` for delegate types.

**Step 4: Run tests**

Run: `zig build test 2>&1 | tail -20`
Expected: All delegate_impl tests PASS

**Step 5: Commit**

```bash
git add emit.zig
git commit -m "feat: emit DelegateImpl provider box for WinRT delegate types (#88)"
```

---

## Task 3: Verify existing parity and coverage tests still pass

**Files:** None modified, verification only.

**Step 1: Run parity tests**

Run: `zig build test-gen-parity 2>&1; echo "EXIT: $?"`
Expected: EXIT: 0

**Step 2: Run coverage check**

Run: `pwsh -NoProfile -Command "& ./scripts/check-winui-coverage.ps1" 2>&1 | tail -10`
Expected: The 4 DEGRADED types should now show `not_impl=0`

**Step 3: Run all tests**

Run: `zig build test 2>&1; echo "EXIT: $?"`
Expected: EXIT: 0

**Step 4: Commit (if any coverage script adjustments needed)**

---

## Task 4: Regenerate com_generated.zig in ghostty-win

**Files:**
- Modify: `ghostty-win/src/apprt/winui3/com_generated.zig` (regenerated)

**Step 1: Run generator**

```bash
cd ~/win-zig-bindgen
zig build run -- --winui-roots winui_roots.json > /tmp/com_generated_new.zig
```

(Adjust command to match actual generator invocation)

**Step 2: Replace generated file**

```bash
cp /tmp/com_generated_new.zig ~/ghostty-win/src/apprt/winui3/com_generated.zig
```

**Step 3: Verify build**

```bash
cd ~/ghostty-win && bash ./build-winui3.sh 2>&1 | tail -5
```

**Step 4: Commit**

```bash
cd ~/ghostty-win
git add src/apprt/winui3/com_generated.zig
git commit -m "chore: regenerate COM bindings with delegate Impl (#88)"
```

---

## Task 5: Migrate ghostty-win from delegate_runtime.zig to generated Impl

**Files:**
- Modify: `src/apprt/winui3/Surface.zig` — replace all `delegate_runtime.TypedDelegate` with generated `FooHandlerImpl`
- Modify: `src/apprt/winui3/caption_buttons.zig` — same
- Modify: `src/apprt/winui3/event.zig` — rewrite to use generated types
- Delete: `src/apprt/winui3/delegate_runtime.zig`

**Step 1: Replace in Surface.zig**

Example transformation (repeat for each usage):
```zig
// Before:
const delegate_runtime = @import("delegate_runtime.zig");
const LoadedDelegate = delegate_runtime.TypedDelegate(Surface, *const fn (*Surface, *anyopaque, *anyopaque) void);
const d = try LoadedDelegate.createWithIid(alloc, self, &onLoaded, &com.IID_RoutedEventHandler);

// After:
const gen = @import("com_generated.zig");
const LoadedDelegate = gen.RoutedEventHandlerImpl(Surface, *const fn (*Surface, *anyopaque, *anyopaque) void);
const d = try LoadedDelegate.createWithIid(alloc, self, &onLoaded, &gen.IID_RoutedEventHandler);
```

Mapping:
- `RoutedEventHandler` → Loaded, SizeChanged events
- `PointerEventHandler` → PointerPressed/Moved/Released/WheelChanged
- `KeyEventHandler` → PreviewKeyDown
- `ScrollEventHandler` → ScrollBar events
- `SelectionChangedEventHandler` → SelectionChanged events
- `TappedEventHandler` → caption button taps

**Step 2: Update event.zig**

```zig
const gen = @import("com_generated.zig");

pub fn TypedEventHandler(comptime Context: type, comptime CallbackFn: type) type {
    // This becomes a thin alias if needed, or callers use generated Impl directly
    return gen.RoutedEventHandlerImpl(Context, CallbackFn);
}
```

Or better: eliminate event.zig entirely and use the generated Impl directly at each call site.

**Step 3: Delete delegate_runtime.zig**

**Step 4: Build and verify**

```bash
cd ~/ghostty-win && bash ./build-winui3.sh 2>&1 | tail -5
```

**Step 5: Commit**

```bash
git add -u src/apprt/winui3/
git commit -m "refactor: replace hand-written delegate_runtime with generated Impl (#88)"
```

---

## Task 6: IMarshal support (optional, can be deferred)

The current `delegate_runtime.zig` supports IMarshal via `marshaler_runtime.zig`. The generated Impl in Task 2 intentionally omits IMarshal to keep the generator self-contained. If WinRT event dispatch fails due to missing IMarshal:

**Option A**: Add IMarshal handling to the generated `queryInterfaceFn` that calls an extern helper function (defined in ghostty-win's runtime modules).

**Option B**: Keep `marshaler_runtime.zig` in ghostty-win and have the generated code conditionally import it.

This is deferred — test without IMarshal first. Most WinUI3 event callbacks work on the UI thread and don't need cross-thread marshaling.

---

## Summary

| Task | What | Where | Est. |
|------|------|-------|------|
| 1 | Add failing tests for Impl shape | win-zig-bindgen/tests/ | 5 min |
| 2 | Emit DelegateImpl in emitDelegate | win-zig-bindgen/emit.zig | 15 min |
| 3 | Verify parity/coverage | win-zig-bindgen | 5 min |
| 4 | Regenerate com_generated.zig | ghostty-win | 5 min |
| 5 | Migrate Surface.zig etc. | ghostty-win | 15 min |
| 6 | IMarshal (deferred) | both | TBD |

After Task 5, `delegate_runtime.zig` is deleted and all delegate implementations come from the generator.

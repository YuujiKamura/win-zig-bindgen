/// Quick test: generate TSF COM interfaces from Win32.winmd
const std = @import("std");
const support = @import("test_support");
const ctx = support.context;
const winmd2zig = ctx.winmd2zig;
const emit = winmd2zig.emit;

const GenCtx = ctx.GenCtx;
const cache_alloc = ctx.cache_alloc;

var cached_win32: ?GenCtx = null;

fn getWin32() !*GenCtx {
    if (cached_win32 == null) {
        const win32_winmd = winmd2zig.findWin32DefaultWinmdAlloc(cache_alloc) catch return error.SkipZigTest;
        cached_win32 = try ctx.loadGenCtx(cache_alloc, win32_winmd);
    }
    return &cached_win32.?;
}

test "generate ITfThreadMgrEx" {
    const allocator = std.testing.allocator;
    const win32 = try getWin32();
    const output = ctx.generateActualOutput(allocator, win32, win32, &.{"Windows.Win32.UI.TextServices.ITfThreadMgrEx"}) catch |err| {
        std.debug.print("Generation failed: {}\n", .{err});
        return err;
    };
    defer allocator.free(output);
    std.debug.print("\n=== ITfThreadMgrEx ===\n{s}\n", .{output});
    try std.testing.expect(output.len > 0);

    // Issue #156: ITfThreadMgrEx vtable must contain parent ITfThreadMgr methods
    // Expected: 3 IUnknown + 11 ITfThreadMgr + 2 ITfThreadMgrEx = 16 methods
    const parent_methods = [_][]const u8{
        "Activate:",
        "Deactivate:",
        "CreateDocumentMgr:",
        "EnumDocumentMgrs:",
        "GetFocus:",
        "SetFocus:",
        "AssociateFocus:",
        "IsThreadFocus:",
        "GetFunctionProvider:",
        "EnumFunctionProviders:",
        "GetGlobalCompartment:",
    };
    for (parent_methods) |method_name| {
        if (std.mem.indexOf(u8, output, method_name) == null) {
            std.debug.print("MISSING parent method in ITfThreadMgrEx vtable: {s}\n", .{method_name});
            return error.MissingParentMethod;
        }
    }
    // Own methods must also be present
    try std.testing.expect(std.mem.indexOf(u8, output, "ActivateEx:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "GetActiveFlags:") != null);
}

test "generate ITfContextOwner" {
    const allocator = std.testing.allocator;
    const win32 = try getWin32();
    const output = ctx.generateActualOutput(allocator, win32, win32, &.{"Windows.Win32.UI.TextServices.ITfContextOwner"}) catch |err| {
        std.debug.print("Generation failed: {}\n", .{err});
        return err;
    };
    defer allocator.free(output);
    std.debug.print("\n=== ITfContextOwner ===\n{s}\n", .{output});
    try std.testing.expect(output.len > 0);
}

test "generate ITfEditSession" {
    const allocator = std.testing.allocator;
    const win32 = try getWin32();
    const output = ctx.generateActualOutput(allocator, win32, win32, &.{"Windows.Win32.UI.TextServices.ITfEditSession"}) catch |err| {
        std.debug.print("Generation failed: {}\n", .{err});
        return err;
    };
    defer allocator.free(output);
    std.debug.print("\n=== ITfEditSession ===\n{s}\n", .{output});
    try std.testing.expect(output.len > 0);
}

test "generate TF_DISPLAYATTRIBUTE" {
    const allocator = std.testing.allocator;
    const win32 = try getWin32();
    const output = ctx.generateActualOutput(allocator, win32, win32, &.{"Windows.Win32.UI.TextServices.TF_DISPLAYATTRIBUTE"}) catch |err| {
        std.debug.print("Generation failed: {}\n", .{err});
        return err;
    };
    defer allocator.free(output);
    std.debug.print("\n=== TF_DISPLAYATTRIBUTE ===\n{s}\n", .{output});
    try std.testing.expect(output.len > 0);
}

test "generate all TSF interfaces" {
    const allocator = std.testing.allocator;
    const win32 = try getWin32();
    const output = ctx.generateActualOutput(allocator, win32, win32, &.{
        "Windows.Win32.UI.TextServices.ITfThreadMgrEx",
        "Windows.Win32.UI.TextServices.ITfContextOwner",
        "Windows.Win32.UI.TextServices.ITfContextOwnerCompositionSink",
        "Windows.Win32.UI.TextServices.ITfTextEditSink",
        "Windows.Win32.UI.TextServices.ITfEditSession",
        "Windows.Win32.UI.TextServices.ITfDocumentMgr",
        "Windows.Win32.UI.TextServices.ITfContext",
        "Windows.Win32.UI.TextServices.ITfRange",
        "Windows.Win32.UI.TextServices.ITfSource",
        "Windows.Win32.UI.TextServices.ITfCategoryMgr",
        "Windows.Win32.UI.TextServices.ITfDisplayAttributeMgr",
        "Windows.Win32.UI.TextServices.ITfReadOnlyProperty",
        "Windows.Win32.UI.TextServices.TF_DISPLAYATTRIBUTE",
    }) catch |err| {
        std.debug.print("Generation failed: {}\n", .{err});
        return err;
    };
    defer allocator.free(output);
    std.debug.print("\n=== ALL TSF ({} bytes) ===\n{s}\n", .{ output.len, output });
    try std.testing.expect(output.len > 0);
}

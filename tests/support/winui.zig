/// WinUI context management, companion WinMD loading, and output generation.
/// Shared by all WinUI probe tests (type_resolution, delegate, shape, etc.).
const std = @import("std");
const ctx = @import("context.zig");
const emit = ctx.emit;

const GenCtx = ctx.GenCtx;
const cache_alloc = ctx.cache_alloc;

var cached_xaml: ?GenCtx = null;
var cached_winui_outputs: ?std.StringHashMap([]const u8) = null;
var winrt_companions: ?[2]emit.CompanionMetadata = null;
var winrt_companion_count: usize = 0;

pub fn ensureXamlCtx() !*GenCtx {
    if (cached_xaml == null) {
        const xaml_winmd = ctx.winmd2zig.findXamlWinmdAlloc(cache_alloc) catch return error.SkipZigTest;
        cached_xaml = ctx.loadGenCtx(cache_alloc, xaml_winmd) catch return error.SkipZigTest;
    }
    return &cached_xaml.?;
}

pub fn generateWinuiOutput(allocator: std.mem.Allocator, filter: []const u8) ![]u8 {
    const xaml = try ensureXamlCtx();
    if (cached_winui_outputs == null) {
        cached_winui_outputs = std.StringHashMap([]const u8).init(cache_alloc);
    }
    if (cached_winui_outputs.?.get(filter)) |cached| {
        return try allocator.dupe(u8, cached);
    }
    // Load companion WinMDs for cross-WinMD resolution
    if (winrt_companions == null) {
        winrt_companions = undefined;
        winrt_companion_count = 0;
        // Windows.winmd (Windows.UI.Core, Windows.Foundation, etc.)
        if (ctx.winmd2zig.findWindowsKitUnionWinmdAlloc(cache_alloc)) |winrt_winmd| {
            if (ctx.loadGenCtx(cache_alloc, winrt_winmd)) |winrt| {
                winrt_companions.?[winrt_companion_count] = .{ .table_info = winrt.table_info, .heaps = winrt.heaps };
                winrt_companion_count += 1;
            } else |_| {}
        } else |_| {}
        // Microsoft.UI.winmd (Microsoft.UI.Input, etc.)
        if (ctx.winmd2zig.findMicrosoftUiWinmdAlloc(cache_alloc)) |ui_winmd| {
            if (ctx.loadGenCtx(cache_alloc, ui_winmd)) |ui| {
                winrt_companions.?[winrt_companion_count] = .{ .table_info = ui.table_info, .heaps = ui.heaps };
                winrt_companion_count += 1;
            } else |_| {}
        } else |_| {}
    }
    xaml.emit_ctx.companions = winrt_companions.?[0..winrt_companion_count];
    const generated = try ctx.generateActualOutput(cache_alloc, xaml, xaml, &.{filter});
    const key = try cache_alloc.dupe(u8, filter);
    errdefer cache_alloc.free(key);
    errdefer cache_alloc.free(generated);
    try cached_winui_outputs.?.put(key, generated);
    return try allocator.dupe(u8, generated);
}

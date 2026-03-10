/// WinUI context management, companion WinMD loading, and output generation.
/// Shared by all WinUI probe tests (type_resolution, delegate, shape, etc.).
const std = @import("std");
const ctx = @import("context.zig");
const emit = ctx.emit;
const ui = ctx.winmd2zig.ui;

const GenCtx = ctx.GenCtx;
const cache_alloc = ctx.cache_alloc;

var cached_xaml: ?GenCtx = null;
var cached_winui_outputs: ?std.StringHashMap([]const u8) = null;

/// Companion GenCtx instances (Windows.winmd, Microsoft.UI.winmd).
/// We keep them alive so their arenas (and thus FileEntry data) stay valid.
var companion_ctxs: [2]GenCtx = undefined;
var companion_count: usize = 0;
var companions_loaded: bool = false;

pub fn ensureXamlCtx() !*GenCtx {
    if (cached_xaml == null) {
        const xaml_winmd = ctx.winmd2zig.findXamlWinmdAlloc(cache_alloc) catch return error.SkipZigTest;
        cached_xaml = ctx.loadGenCtx(cache_alloc, xaml_winmd) catch return error.SkipZigTest;
    }
    return &cached_xaml.?;
}

fn ensureCompanions() void {
    if (companions_loaded) return;
    companions_loaded = true;
    companion_count = 0;

    // Windows.winmd (Windows.UI.Core, Windows.Foundation, etc.)
    if (ctx.winmd2zig.findWindowsKitUnionWinmdAlloc(cache_alloc)) |winrt_winmd| {
        if (ctx.loadGenCtx(cache_alloc, winrt_winmd)) |winrt| {
            companion_ctxs[companion_count] = winrt;
            companion_count += 1;
        } else |_| {}
    } else |_| {}

    // Microsoft.UI.winmd (Microsoft.UI.Input, etc.)
    if (ctx.winmd2zig.findMicrosoftUiWinmdAlloc(cache_alloc)) |ui_winmd| {
        if (ctx.loadGenCtx(cache_alloc, ui_winmd)) |loaded_ui| {
            companion_ctxs[companion_count] = loaded_ui;
            companion_count += 1;
        } else |_| {}
    } else |_| {}
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
    ensureCompanions();

    // Build extra file entries from companions
    var extra_buf: [2]ui.FileEntry = undefined;
    var extra_count: usize = 0;
    for (companion_ctxs[0..companion_count]) |*comp| {
        extra_buf[extra_count] = comp.file_entries[0];
        extra_count += 1;
    }

    const generated = try ctx.generateActualOutputWithExtras(
        cache_alloc,
        xaml,
        xaml,
        &.{filter},
        extra_buf[0..extra_count],
    );
    const key = try cache_alloc.dupe(u8, filter);
    errdefer cache_alloc.free(key);
    errdefer cache_alloc.free(generated);
    try cached_winui_outputs.?.put(key, generated);
    return try allocator.dupe(u8, generated);
}

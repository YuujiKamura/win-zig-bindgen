/// WinMD exact shape probes.
/// Compares WinMD MethodDef metadata against generated vtable for completeness.
const std = @import("std");
const support = @import("test_support");
const ctx = support.context;
const manifest_mod = support.manifest;
const winui_ctx = support.winui;
const emit = ctx.emit;

const GenCtx = ctx.GenCtx;
const cache_alloc = ctx.cache_alloc;
const containsStr = ctx.containsStr;
const freeSliceList = ctx.freeSliceList;
const trimLine = ctx.trimLine;
const braceDelta = ctx.braceDelta;

// ============================================================
// Shape types and extraction
// ============================================================

const WinmdMethodShape = struct {
    name: []const u8,
    param_count: u32,
    is_getter: bool,
    is_setter: bool,
};

const WinmdTypeShape = struct {
    name: []const u8,
    category: emit.TypeCategory,
    methods: std.ArrayList(WinmdMethodShape),

    fn deinit(self: *WinmdTypeShape, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.methods.deinit(allocator);
    }
};

fn extractWinmdShape(allocator: std.mem.Allocator, gctx: *GenCtx, type_name: []const u8) !WinmdTypeShape {
    const row = try ctx.findExactTypeRow(gctx, type_name) orelse return error.TypeNotFound;
    const category = try emit.identifyTypeCategory(gctx.emitCtx(), row);

    const td = try gctx.table_info.readTypeDef(row);
    const method_start = td.method_list;
    const td_table = gctx.table_info.getTable(.TypeDef);
    const method_end = if (row < td_table.row_count)
        (try gctx.table_info.readTypeDef(row + 1)).method_list
    else
        gctx.table_info.getTable(.MethodDef).row_count + 1;

    var methods = std.ArrayList(WinmdMethodShape).empty;
    errdefer methods.deinit(allocator);

    var mi: u32 = method_start;
    while (mi < method_end) : (mi += 1) {
        const md = try gctx.table_info.readMethodDef(mi);
        const name = try gctx.heaps.getString(md.name);

        const param_start = md.param_list;
        const param_end = if (mi < gctx.table_info.getTable(.MethodDef).row_count)
            (try gctx.table_info.readMethodDef(mi + 1)).param_list
        else
            gctx.table_info.getTable(.Param).row_count + 1;

        var param_count: u32 = 0;
        var pi: u32 = param_start;
        while (pi < param_end) : (pi += 1) {
            const p = try gctx.table_info.readParam(pi);
            if (p.sequence != 0) param_count += 1;
        }

        try methods.append(allocator, .{
            .name = name,
            .param_count = param_count,
            .is_getter = std.mem.startsWith(u8, name, "get_"),
            .is_setter = std.mem.startsWith(u8, name, "put_"),
        });
    }

    return .{
        .name = try allocator.dupe(u8, type_name),
        .category = category,
        .methods = methods,
    };
}

fn countAnyopaqueInVtable(text: []const u8, type_name: []const u8) u32 {
    var buf: [256]u8 = undefined;
    const marker = std.fmt.bufPrint(&buf, "pub const {s} = extern struct", .{type_name}) catch return 0;
    const type_start = std.mem.indexOf(u8, text, marker) orelse return 0;

    const search_text = text[type_start..];
    const vtable_start = std.mem.indexOf(u8, search_text, "pub const VTable = extern struct {") orelse return 0;

    var count: u32 = 0;
    var depth: i32 = 0;
    var started = false;
    var lines = std.mem.tokenizeScalar(u8, search_text[vtable_start..], '\n');
    while (lines.next()) |raw_line| {
        const line = trimLine(raw_line);
        if (!started) {
            if (std.mem.startsWith(u8, line, "pub const VTable = extern struct {")) {
                started = true;
                depth = braceDelta(line);
            }
            continue;
        }
        const is_base_line = std.mem.startsWith(u8, line, "QueryInterface:") or
            std.mem.startsWith(u8, line, "AddRef:") or
            std.mem.startsWith(u8, line, "Release:") or
            std.mem.indexOf(u8, line, "VtblPlaceholder") != null;
        if (!is_base_line) {
            var search: usize = 0;
            while (std.mem.indexOfPos(u8, line, search, "?*anyopaque")) |pos| {
                count += 1;
                search = pos + "?*anyopaque".len;
            }
        }
        depth += braceDelta(line);
        if (depth <= 0) break;
    }
    return count;
}

const base_methods = [_][]const u8{
    "QueryInterface",
    "AddRef",
    "Release",
    "GetIids",
    "GetRuntimeClassName",
    "GetTrustLevel",
};

fn isBaseMethod(name: []const u8) bool {
    for (&base_methods) |bm| {
        if (std.mem.eql(u8, name, bm)) return true;
    }
    return false;
}

fn expectedVtableSlotName(allocator: std.mem.Allocator, winmd_name: []const u8) ![]const u8 {
    if (std.mem.startsWith(u8, winmd_name, "get_"))
        return try allocator.dupe(u8, winmd_name[4..]);
    if (std.mem.startsWith(u8, winmd_name, "put_"))
        return try std.fmt.allocPrint(allocator, "Set{s}", .{winmd_name[4..]});
    if (std.mem.startsWith(u8, winmd_name, "add_"))
        return try allocator.dupe(u8, winmd_name[4..]);
    if (std.mem.startsWith(u8, winmd_name, "remove_"))
        return try std.fmt.allocPrint(allocator, "Remove{s}", .{winmd_name[7..]});
    return try allocator.dupe(u8, winmd_name);
}

fn expectedWrapperName(allocator: std.mem.Allocator, winmd_name: []const u8) ![]const u8 {
    if (std.mem.startsWith(u8, winmd_name, "get_"))
        return try allocator.dupe(u8, winmd_name[4..]);
    if (std.mem.startsWith(u8, winmd_name, "put_"))
        return try std.fmt.allocPrint(allocator, "Set{s}", .{winmd_name[4..]});
    if (std.mem.startsWith(u8, winmd_name, "add_"))
        return try std.fmt.allocPrint(allocator, "Add{s}", .{winmd_name[4..]});
    if (std.mem.startsWith(u8, winmd_name, "remove_"))
        return try std.fmt.allocPrint(allocator, "Remove{s}", .{winmd_name[7..]});
    var buf = try allocator.dupe(u8, winmd_name);
    if (buf.len > 0 and std.ascii.isUpper(buf[0])) {
        buf[0] = std.ascii.toLower(buf[0]);
    }
    return buf;
}

const ShapeProbeResult = struct {
    vtable_missing: std.ArrayList([]const u8),
    wrapper_missing: std.ArrayList([]const u8),
    anyopaque_count: u32,
    winmd_method_count: u32,
    vtable_slot_count: u32,

    fn deinit(self: *ShapeProbeResult, allocator: std.mem.Allocator) void {
        freeSliceList(allocator, &self.vtable_missing);
        freeSliceList(allocator, &self.wrapper_missing);
    }
};

var cached_winrt_ctx: ?GenCtx = null;

fn ensureWinrtCtx() !*GenCtx {
    if (cached_winrt_ctx == null) {
        const winrt_winmd = ctx.winmd2zig.findWindowsKitUnionWinmdAlloc(cache_alloc) catch return error.SkipZigTest;
        cached_winrt_ctx = ctx.loadGenCtx(cache_alloc, winrt_winmd) catch return error.SkipZigTest;
    }
    return &cached_winrt_ctx.?;
}

fn runExactShapeProbe(allocator: std.mem.Allocator, type_name: []const u8) !ShapeProbeResult {
    const xaml = winui_ctx.ensureXamlCtx() catch return error.SkipZigTest;

    var winmd_shape = extractWinmdShape(allocator, xaml, type_name) catch |e| blk: {
        if (e == error.TypeNotFound) {
            const winrt = ensureWinrtCtx() catch return error.SkipZigTest;
            break :blk try extractWinmdShape(allocator, winrt, type_name);
        }
        return e;
    };
    defer winmd_shape.deinit(allocator);

    const generated = winui_ctx.generateWinuiOutput(allocator, type_name) catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);

    var manifest = try manifest_mod.parseGeneratedManifest(allocator, generated);
    defer manifest.deinit();

    const anyopaque_count = countAnyopaqueInVtable(generated, type_name);
    const gen_type = manifest.findType(type_name);

    var vtable_missing = std.ArrayList([]const u8).empty;
    errdefer freeSliceList(allocator, &vtable_missing);
    var wrapper_missing = std.ArrayList([]const u8).empty;
    errdefer freeSliceList(allocator, &wrapper_missing);

    var non_base_count: u32 = 0;
    for (winmd_shape.methods.items) |method| {
        if (std.mem.eql(u8, method.name, ".ctor")) continue;
        if (isBaseMethod(method.name)) continue;
        non_base_count += 1;

        if (gen_type) |gt| {
            const slot_name = try expectedVtableSlotName(allocator, method.name);
            defer allocator.free(slot_name);
            if (!containsStr(gt.vtable_methods.items, slot_name)) {
                try vtable_missing.append(allocator, try allocator.dupe(u8, method.name));
            }

            const wrapper = try expectedWrapperName(allocator, method.name);
            defer allocator.free(wrapper);
            const get_prefixed = try std.fmt.allocPrint(allocator, "Get{s}", .{wrapper});
            defer allocator.free(get_prefixed);
            if (!containsStr(gt.methods.items, wrapper) and !containsStr(gt.methods.items, get_prefixed)) {
                try wrapper_missing.append(allocator, try allocator.dupe(u8, method.name));
            }
        } else {
            try vtable_missing.append(allocator, try allocator.dupe(u8, method.name));
        }
    }

    const vtable_slot_count = if (gen_type) |gt| @as(u32, @intCast(gt.vtable_methods.items.len)) else 0;

    return .{
        .vtable_missing = vtable_missing,
        .wrapper_missing = wrapper_missing,
        .anyopaque_count = anyopaque_count,
        .winmd_method_count = non_base_count,
        .vtable_slot_count = vtable_slot_count,
    };
}

fn assertExactShape(type_name: []const u8) !void {
    const allocator = cache_alloc;
    var result = runExactShapeProbe(allocator, type_name) catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer result.deinit(allocator);

    var fail_count: usize = 0;

    for (result.vtable_missing.items) |missing| {
        std.log.err("[SHAPE {s}] vtable slot missing: {s}", .{ type_name, missing });
        fail_count += 1;
    }

    for (result.wrapper_missing.items) |missing| {
        std.log.err("[SHAPE {s}] wrapper missing for: {s}", .{ type_name, missing });
        fail_count += 1;
    }

    if (result.anyopaque_count > 0) {
        std.log.warn("[SHAPE {s}] vtable has {d} ?*anyopaque param slots (COM ABI, not a shape error)", .{ type_name, result.anyopaque_count });
    }

    std.log.info("[SHAPE {s}] WinMD methods={d}, vtable slots={d}, anyopaque={d}, vtable_missing={d}, wrapper_missing={d}", .{
        type_name,
        result.winmd_method_count,
        result.vtable_slot_count,
        result.anyopaque_count,
        @as(u32, @intCast(result.vtable_missing.items.len)),
        @as(u32, @intCast(result.wrapper_missing.items.len)),
    });

    if (fail_count > 0) {
        return error.TestUnexpectedResult;
    }
}

// ============================================================
// Exact shape probe tests
// ============================================================

test "SHAPE #121: IXamlReaderStatics exact shape" {
    try assertExactShape("IXamlReaderStatics");
}

test "SHAPE #121: IKeyRoutedEventArgs exact shape" {
    try assertExactShape("IKeyRoutedEventArgs");
}

test "SHAPE #121: ICharacterReceivedRoutedEventArgs exact shape" {
    try assertExactShape("ICharacterReceivedRoutedEventArgs");
}

test "SHAPE #121: IRowDefinition exact shape" {
    try assertExactShape("IRowDefinition");
}

test "SHAPE #121: IScrollEventArgs exact shape" {
    try assertExactShape("IScrollEventArgs");
}

test "SHAPE #121: IColumnDefinition exact shape" {
    try assertExactShape("IColumnDefinition");
}

test "SHAPE #121: ISolidColorBrush exact shape" {
    try assertExactShape("ISolidColorBrush");
}

test "SHAPE #121: IScrollBar exact shape" {
    try assertExactShape("IScrollBar");
}

test "SHAPE #121: ScrollEventHandler exact shape (delegate)" {
    try assertExactShape("ScrollEventHandler");
}

test "SHAPE #122: IWindow2 exact shape" {
    try assertExactShape("IWindow2");
}

test "SHAPE #122: ITabView2 exact shape" {
    try assertExactShape("ITabView2");
}

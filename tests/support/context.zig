/// WinMD context management, code generation engine, and shared utilities.
/// Provides the foundation for both parity comparison and WinUI probe tests.
const std = @import("std");
pub const winmd2zig = @import("winmd2zig_main");
pub const win_zig_metadata = @import("win_zig_metadata");
const pe = win_zig_metadata.pe;
const metadata = win_zig_metadata.metadata;
const tables = win_zig_metadata.tables;
const streams = win_zig_metadata.streams;
pub const emit = winmd2zig.emit;

pub const cache_alloc = std.heap.page_allocator;

pub const Case = struct {
    id: []const u8,
    kind: []const u8,
    args: []const u8,
};

pub const GenCtx = struct {
    arena: std.heap.ArenaAllocator,
    table_info: tables.Info,
    heaps: streams.Heaps,
    emit_ctx: emit.Context,
    winmd_path: []const u8,

    pub fn deinit(self: *GenCtx) void {
        self.arena.deinit();
    }
};

pub const CompareOptions = struct {
    allow_sys_fn_ptr_alias: bool = false,
    allow_nt_wait_compat: bool = false,
};

// ============================================================
// Utility functions
// ============================================================

pub fn freeSliceList(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8)) void {
    for (list.items) |item| allocator.free(item);
    list.deinit(allocator);
}

pub fn containsStr(items: []const []const u8, needle: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
}

pub fn appendUniqueStr(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), value: []const u8) !void {
    if (containsStr(list.items, value)) return;
    try list.append(allocator, try allocator.dupe(u8, value));
}

pub fn trimLine(line: []const u8) []const u8 {
    return std.mem.trim(u8, line, " \t\r");
}

pub fn braceDelta(line: []const u8) i32 {
    var delta: i32 = 0;
    for (line) |ch| {
        switch (ch) {
            '{' => delta += 1,
            '}' => delta -= 1,
            else => {},
        }
    }
    return delta;
}

pub fn takeIdentifier(text: []const u8) []const u8 {
    var end: usize = 0;
    while (end < text.len) : (end += 1) {
        const ch = text[end];
        if (!std.ascii.isAlphanumeric(ch) and ch != '_') break;
    }
    return text[0..end];
}

pub fn isLikelyInterfaceName(name: []const u8) bool {
    if (name.len > 1 and name[0] == 'I' and std.ascii.isUpper(name[1])) return true;
    if (std.mem.endsWith(u8, name, "Handler")) return true;
    return false;
}

pub fn shortToken(name: []const u8) []const u8 {
    const dotted = if (std.mem.lastIndexOfScalar(u8, name, '.')) |i| name[i + 1 ..] else name;
    return if (std.mem.indexOfScalar(u8, dotted, '`')) |i| dotted[0..i] else dotted;
}

// ============================================================
// WinMD loading and type lookup
// ============================================================

pub fn loadGenCtx(allocator: std.mem.Allocator, winmd_path: []const u8) !GenCtx {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const a = arena.allocator();

    const data = std.fs.cwd().readFileAlloc(a, winmd_path, std.math.maxInt(usize)) catch {
        return error.SkipZigTest;
    };
    const pe_info = try pe.parse(a, data);
    const md_info = try metadata.parse(a, pe_info);
    const table_stream = if (md_info.getStream("#~")) |s| s else if (md_info.getStream("#-")) |s| s else return error.MissingTableStream;
    const strings_stream = md_info.getStream("#Strings") orelse return error.MissingStringsStream;
    const blob_stream = md_info.getStream("#Blob") orelse return error.MissingBlobStream;
    const guid_stream = md_info.getStream("#GUID") orelse return error.MissingGuidStream;
    const table_info = try tables.parse(table_stream.data);
    const heaps = streams.Heaps{
        .strings = strings_stream.data,
        .blob = blob_stream.data,
        .guid = guid_stream.data,
    };
    return .{
        .arena = arena,
        .table_info = table_info,
        .heaps = heaps,
        .emit_ctx = .{ .table_info = table_info, .heaps = heaps, .allocator = a },
        .winmd_path = winmd_path,
    };
}

pub fn findTypeByShortName(ctx: emit.Context, short_name: []const u8) !?u32 {
    const t = ctx.table_info.getTable(.TypeDef);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const td = try ctx.table_info.readTypeDef(row);
        const name = try ctx.heaps.getString(td.type_name);
        if (std.mem.eql(u8, name, short_name) or std.mem.eql(u8, shortToken(name), short_name)) return row;
    }
    return null;
}

fn ownerTypeRowForFieldRow(ctx: emit.Context, field_row: u32) !?u32 {
    const t = ctx.table_info.getTable(.TypeDef);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const td = try ctx.table_info.readTypeDef(row);
        const start = td.field_list;
        const end_exclusive = if (row < t.row_count)
            (try ctx.table_info.readTypeDef(row + 1)).field_list
        else
            ctx.table_info.getTable(.Field).row_count + 1;
        if (field_row >= start and field_row < end_exclusive) return row;
    }
    return null;
}

pub fn findTypeByFieldName(ctx: emit.Context, field_name: []const u8) !?u32 {
    const ftab = ctx.table_info.getTable(.Field);
    var row: u32 = 1;
    while (row <= ftab.row_count) : (row += 1) {
        const f = try ctx.table_info.readField(row);
        const name = try ctx.heaps.getString(f.name);
        if (!std.mem.eql(u8, name, field_name)) continue;
        return try ownerTypeRowForFieldRow(ctx, row);
    }
    return null;
}

pub fn findTypeByMethodName(ctx: emit.Context, method_name: []const u8) !?u32 {
    const mtab = ctx.table_info.getTable(.MethodDef);
    var row: u32 = 1;
    while (row <= mtab.row_count) : (row += 1) {
        const m = try ctx.table_info.readMethodDef(row);
        const name = try ctx.heaps.getString(m.name);
        if (!std.mem.eql(u8, name, method_name)) continue;

        const t = ctx.table_info.getTable(.TypeDef);
        var td_row: u32 = 1;
        while (td_row <= t.row_count) : (td_row += 1) {
            const td = try ctx.table_info.readTypeDef(td_row);
            const start = td.method_list;
            const end_exclusive = if (td_row < t.row_count)
                (try ctx.table_info.readTypeDef(td_row + 1)).method_list
            else
                ctx.table_info.getTable(.MethodDef).row_count + 1;
            if (row >= start and row < end_exclusive) return td_row;
        }
    }
    return null;
}

pub fn findExactTypeRow(ctx: *GenCtx, filter_name: []const u8) !?u32 {
    var row_opt: ?u32 = null;
    row_opt = emit.findTypeDefRow(ctx.emit_ctx, filter_name) catch null;
    if (row_opt == null) {
        if (std.mem.lastIndexOfScalar(u8, filter_name, '.')) |_| {
            row_opt = winmd2zig.resolver.findTypeDefRowByFullName(.{ .table_info = ctx.table_info, .heaps = ctx.heaps }, filter_name) catch null;
        }
    }
    if (row_opt == null) row_opt = try findTypeByShortName(ctx.emit_ctx, shortToken(filter_name));
    return row_opt;
}

// ============================================================
// Code emission
// ============================================================

pub fn emitResolvedType(allocator: std.mem.Allocator, writer: anytype, ctx: *GenCtx, filter_name: []const u8, row: u32) !void {
    const cat = try emit.identifyTypeCategory(ctx.emit_ctx, row);
    switch (cat) {
        .interface => try emit.emitInterface(allocator, writer, ctx.emit_ctx, ctx.winmd_path, filter_name),
        .enum_type => try emit.emitEnum(allocator, writer, ctx.emit_ctx, row),
        .struct_type => try emit.emitStruct(allocator, writer, ctx.emit_ctx, row),
        .delegate => try emit.emitDelegate(allocator, writer, ctx.emit_ctx, row),
        .class, .other => {
            const td = try ctx.table_info.readTypeDef(row);
            const name = try ctx.heaps.getString(td.type_name);
            if (std.mem.endsWith(u8, name, "Apis")) {
                try emit.emitFunctions(allocator, writer, ctx.emit_ctx, row);
            } else if (cat == .class) {
                try emit.emitClass(allocator, writer, ctx.emit_ctx, row);
            } else {
                var full_name_buf: ?[]u8 = null;
                defer if (full_name_buf) |buf| allocator.free(buf);

                const class_full_name = if (std.mem.lastIndexOfScalar(u8, filter_name, '.')) |_| filter_name else blk: {
                    const ns = try ctx.heaps.getString(td.type_namespace);
                    const nm = try ctx.heaps.getString(td.type_name);
                    full_name_buf = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns, nm });
                    break :blk full_name_buf.?;
                };

                const resolved = winmd2zig.resolver.resolveDefaultInterfaceNameForRuntimeClassAlloc(
                    .{ .table_info = ctx.table_info, .heaps = ctx.heaps },
                    allocator,
                    class_full_name,
                ) catch return;
                defer allocator.free(resolved);
                try emit.emitInterface(allocator, writer, ctx.emit_ctx, ctx.winmd_path, resolved);
            }
        },
    }
}

fn emitOneExactType(allocator: std.mem.Allocator, writer: anytype, ctx: *GenCtx, filter_name: []const u8) !bool {
    const row = try findExactTypeRow(ctx, filter_name) orelse return false;
    try emitResolvedType(allocator, writer, ctx, filter_name, row);
    return true;
}

fn emitOneType(allocator: std.mem.Allocator, writer: anytype, ctx: *GenCtx, filter_name: []const u8) !bool {
    var row_opt = try findExactTypeRow(ctx, filter_name);
    if (row_opt == null) row_opt = try findTypeByFieldName(ctx.emit_ctx, shortToken(filter_name));
    if (row_opt == null) row_opt = try findTypeByMethodName(ctx.emit_ctx, shortToken(filter_name));
    if (row_opt == null) return false;
    try emitResolvedType(allocator, writer, ctx, filter_name, row_opt.?);
    return true;
}

// ============================================================
// Argument parsing
// ============================================================

pub fn parseArgsTokens(allocator: std.mem.Allocator, args: []const u8) !std.ArrayList([]const u8) {
    var toks = std.ArrayList([]const u8).empty;
    var it = std.mem.tokenizeAny(u8, args, " \t\r\n");
    while (it.next()) |t| try toks.append(allocator, t);
    return toks;
}

pub fn extractOutName(tokens: []const []const u8) ?[]const u8 {
    for (tokens, 0..) |t, i| {
        if (std.mem.eql(u8, t, "--out") and i + 1 < tokens.len) return tokens[i + 1];
    }
    return null;
}

pub fn collectFilters(allocator: std.mem.Allocator, tokens: []const []const u8) !std.ArrayList([]const u8) {
    var filters = std.ArrayList([]const u8).empty;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!std.mem.eql(u8, tokens[i], "--filter")) continue;
        i += 1;
        while (i < tokens.len and !std.mem.startsWith(u8, tokens[i], "--")) : (i += 1) {
            try filters.append(allocator, tokens[i]);
        }
        if (i > 0) i -= 1;
    }
    return filters;
}

// ============================================================
// Code generation engine
// ============================================================

pub fn generateActualOutput(
    allocator: std.mem.Allocator,
    win32: *GenCtx,
    winrt: *GenCtx,
    filters: []const []const u8,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    const writer = out.writer(allocator);

    try emit.writePrologue(writer);

    var generated_types = std.StringHashMap(void).init(allocator);
    defer generated_types.deinit();

    var deps = std.StringHashMap(void).init(allocator);
    defer {
        win32.emit_ctx.dependencies = null;
        winrt.emit_ctx.dependencies = null;
        var it = deps.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        deps.deinit();
    }
    win32.emit_ctx.dependencies = &deps;
    winrt.emit_ctx.dependencies = &deps;

    var to_generate = std.ArrayList([]const u8).empty;
    defer {
        for (to_generate.items) |item| allocator.free(item);
        to_generate.deinit(allocator);
    }

    for (filters) |f| try to_generate.append(allocator, try allocator.dupe(u8, f));

    var head: usize = 0;
    var emitted_any = false;
    while (head < to_generate.items.len) : (head += 1) {
        const filter_name = to_generate.items[head];
        if (generated_types.contains(filter_name)) continue;
        try generated_types.put(filter_name, {});

        var emitted = false;
        if (try emitOneExactType(allocator, writer, win32, filter_name)) {
            emitted = true;
            emitted_any = true;
        } else if (try emitOneExactType(allocator, writer, winrt, filter_name)) {
            emitted = true;
            emitted_any = true;
        } else if (try emitOneType(allocator, writer, win32, filter_name)) {
            emitted = true;
            emitted_any = true;
        } else if (try emitOneType(allocator, writer, winrt, filter_name)) {
            emitted = true;
            emitted_any = true;
        }

        // Search companion WinMDs if not found in primary contexts
        if (!emitted) {
            const short_name = if (std.mem.lastIndexOfScalar(u8, filter_name, '.')) |d| filter_name[d + 1 ..] else filter_name;
            for (win32.emit_ctx.companions) |comp| {
                const t = comp.table_info.getTable(.TypeDef);
                var crow: u32 = 1;
                while (crow <= t.row_count) : (crow += 1) {
                    const ctd = comp.table_info.readTypeDef(crow) catch continue;
                    const cname = comp.heaps.getString(ctd.type_name) catch continue;
                    if (!std.mem.eql(u8, cname, short_name)) continue;
                    const comp_ctx = emit.Context{
                        .table_info = comp.table_info,
                        .heaps = comp.heaps,
                        .dependencies = &deps,
                        .allocator = allocator,
                        .companions = win32.emit_ctx.companions,
                    };
                    const comp_cat = emit.identifyTypeCategory(comp_ctx, crow) catch continue;
                    switch (comp_cat) {
                        .struct_type => {
                            try emit.emitStruct(allocator, writer, comp_ctx, crow);
                            emitted = true;
                        },
                        .enum_type => {
                            try emit.emitEnum(allocator, writer, comp_ctx, crow);
                            emitted = true;
                        },
                        .delegate => {
                            try emit.emitDelegate(allocator, writer, comp_ctx, crow);
                            emitted = true;
                        },
                        .class => {
                            try emit.emitClass(allocator, writer, comp_ctx, crow);
                            emitted = true;
                        },
                        .interface => {
                            try emit.emitInterface(allocator, writer, comp_ctx, "", cname);
                            emitted = true;
                        },
                        else => continue,
                    }
                    break;
                }
                if (emitted) break;
            }
            if (emitted) emitted_any = true;
        }

        if (emitted) {
            inline for (.{ win32, winrt }) |gctx| {
                if (gctx.emit_ctx.dependencies) |ctx_deps| {
                    var it = ctx_deps.keyIterator();
                    while (it.next()) |d| {
                        if (!generated_types.contains(d.*)) {
                            var in_queue = false;
                            for (to_generate.items[head + 1 ..]) |q| {
                                if (std.mem.eql(u8, q, d.*)) {
                                    in_queue = true;
                                    break;
                                }
                            }
                            if (!in_queue) try to_generate.append(allocator, try allocator.dupe(u8, d.*));
                        }
                    }
                }
            }
        }
    }

    if (!emitted_any) return error.UnsupportedActualGeneration;
    return try out.toOwnedSlice(allocator);
}

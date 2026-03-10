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
const ui = winmd2zig.ui;

pub const FileEntry = ui.FileEntry;
pub const UnifiedContext = ui.UnifiedContext;
pub const UnifiedIndex = ui.UnifiedIndex;
pub const DependencyQueue = ui.DependencyQueue;

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
    winmd_path: []const u8,

    /// The FileEntry for this WinMD, stored as a 1-element array so we can
    /// take a slice and hand it to UnifiedIndex.
    file_entries: [1]ui.FileEntry,

    /// Single-file unified index (for standalone lookups).
    index: ui.UnifiedIndex,
    /// Dependency queue bound to `index`.
    dep_queue: ui.DependencyQueue,

    /// Build a UnifiedContext for a specific type row in this file.
    pub fn emitCtxForRow(self: *GenCtx, type_row: u32) ui.UnifiedContext {
        return ui.UnifiedContext.make(
            &self.index,
            .{ .file_idx = 0, .row = type_row },
            &self.dep_queue,
            self.arena.allocator(),
        );
    }

    /// Build a UnifiedContext with a dummy location (row 0).
    /// Suitable for lookups that only use table_info/heaps.
    pub fn emitCtx(self: *GenCtx) ui.UnifiedContext {
        return self.emitCtxForRow(0);
    }

    pub fn deinit(self: *GenCtx) void {
        self.dep_queue.deinit();
        self.index.deinit();
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

    var result = GenCtx{
        .arena = arena,
        .table_info = table_info,
        .heaps = heaps,
        .winmd_path = winmd_path,
        .file_entries = .{.{
            .path = winmd_path,
            .raw_data = data,
            .table_info = table_info,
            .heaps = heaps,
        }},
        // Placeholder — initialized below after file_entries address is stable
        .index = undefined,
        .dep_queue = undefined,
    };

    // Build single-file index from the embedded file_entries array
    result.index = try ui.UnifiedIndex.init(a, &result.file_entries);
    result.dep_queue = ui.DependencyQueue.init(a, &result.index);

    return result;
}

pub fn findTypeByShortName(uctx: emit.Context, short_name: []const u8) !?u32 {
    const t = uctx.table_info.getTable(.TypeDef);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const td = try uctx.table_info.readTypeDef(row);
        const name = try uctx.heaps.getString(td.type_name);
        if (std.mem.eql(u8, name, short_name) or std.mem.eql(u8, shortToken(name), short_name)) return row;
    }
    return null;
}

fn ownerTypeRowForFieldRow(uctx: emit.Context, field_row: u32) !?u32 {
    const t = uctx.table_info.getTable(.TypeDef);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const td = try uctx.table_info.readTypeDef(row);
        const start = td.field_list;
        const end_exclusive = if (row < t.row_count)
            (try uctx.table_info.readTypeDef(row + 1)).field_list
        else
            uctx.table_info.getTable(.Field).row_count + 1;
        if (field_row >= start and field_row < end_exclusive) return row;
    }
    return null;
}

pub fn findTypeByFieldName(uctx: emit.Context, field_name: []const u8) !?u32 {
    const ftab = uctx.table_info.getTable(.Field);
    var row: u32 = 1;
    while (row <= ftab.row_count) : (row += 1) {
        const f = try uctx.table_info.readField(row);
        const name = try uctx.heaps.getString(f.name);
        if (!std.mem.eql(u8, name, field_name)) continue;
        return try ownerTypeRowForFieldRow(uctx, row);
    }
    return null;
}

pub fn findTypeByMethodName(uctx: emit.Context, method_name: []const u8) !?u32 {
    const mtab = uctx.table_info.getTable(.MethodDef);
    var row: u32 = 1;
    while (row <= mtab.row_count) : (row += 1) {
        const m = try uctx.table_info.readMethodDef(row);
        const name = try uctx.heaps.getString(m.name);
        if (!std.mem.eql(u8, name, method_name)) continue;

        const t = uctx.table_info.getTable(.TypeDef);
        var td_row: u32 = 1;
        while (td_row <= t.row_count) : (td_row += 1) {
            const td = try uctx.table_info.readTypeDef(td_row);
            const start = td.method_list;
            const end_exclusive = if (td_row < t.row_count)
                (try uctx.table_info.readTypeDef(td_row + 1)).method_list
            else
                uctx.table_info.getTable(.MethodDef).row_count + 1;
            if (row >= start and row < end_exclusive) return td_row;
        }
    }
    return null;
}

pub fn findExactTypeRow(ctx: *GenCtx, filter_name: []const u8) !?u32 {
    const uctx = ctx.emitCtx();
    var row_opt: ?u32 = null;
    row_opt = emit.findTypeDefRow(uctx, filter_name) catch null;
    if (row_opt == null) {
        if (std.mem.lastIndexOfScalar(u8, filter_name, '.')) |_| {
            row_opt = winmd2zig.resolver.findTypeDefRowByFullName(.{ .table_info = ctx.table_info, .heaps = ctx.heaps }, filter_name) catch null;
        }
    }
    if (row_opt == null) row_opt = try findTypeByShortName(uctx, shortToken(filter_name));
    return row_opt;
}

// ============================================================
// Code emission
// ============================================================

/// Emit a single resolved type using the given UnifiedContext (which carries
/// the correct index and dep_queue for dependency tracking).
fn emitResolvedTypeWithCtx(allocator: std.mem.Allocator, writer: anytype, uctx: emit.Context, winmd_path: []const u8, table_info: tables.Info, heaps_val: streams.Heaps, filter_name: []const u8, row: u32) !void {
    const cat = try emit.identifyTypeCategory(uctx, row);
    switch (cat) {
        .interface => try emit.emitInterface(allocator, writer, uctx, winmd_path, filter_name),
        .enum_type => try emit.emitEnum(allocator, writer, uctx, row),
        .struct_type => try emit.emitStruct(allocator, writer, uctx, row),
        .delegate => try emit.emitDelegate(allocator, writer, uctx, row),
        .class, .other => {
            const td = try table_info.readTypeDef(row);
            const name = try heaps_val.getString(td.type_name);
            if (std.mem.endsWith(u8, name, "Apis")) {
                try emit.emitFunctions(allocator, writer, uctx, row);
            } else if (cat == .class) {
                try emit.emitClass(allocator, writer, uctx, row);
            } else {
                var full_name_buf: ?[]u8 = null;
                defer if (full_name_buf) |buf| allocator.free(buf);

                const class_full_name = if (std.mem.lastIndexOfScalar(u8, filter_name, '.')) |_| filter_name else blk: {
                    const ns = try heaps_val.getString(td.type_namespace);
                    const nm = try heaps_val.getString(td.type_name);
                    full_name_buf = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns, nm });
                    break :blk full_name_buf.?;
                };

                const resolved = winmd2zig.resolver.resolveDefaultInterfaceNameForRuntimeClassAlloc(
                    .{ .table_info = table_info, .heaps = heaps_val },
                    allocator,
                    class_full_name,
                ) catch return;
                defer allocator.free(resolved);
                try emit.emitInterface(allocator, writer, uctx, winmd_path, resolved);
            }
        },
    }
}

pub fn emitResolvedType(allocator: std.mem.Allocator, writer: anytype, ctx: *GenCtx, filter_name: []const u8, row: u32) !void {
    const uctx = ctx.emitCtx();
    try emitResolvedTypeWithCtx(allocator, writer, uctx, ctx.winmd_path, ctx.table_info, ctx.heaps, filter_name, row);
}

fn emitOneExactType(allocator: std.mem.Allocator, writer: anytype, ctx: *GenCtx, filter_name: []const u8) !bool {
    const row = try findExactTypeRow(ctx, filter_name) orelse return false;
    try emitResolvedType(allocator, writer, ctx, filter_name, row);
    return true;
}

fn emitOneType(allocator: std.mem.Allocator, writer: anytype, ctx: *GenCtx, filter_name: []const u8) !bool {
    const uctx = ctx.emitCtx();
    var row_opt = try findExactTypeRow(ctx, filter_name);
    if (row_opt == null) row_opt = try findTypeByFieldName(uctx, shortToken(filter_name));
    if (row_opt == null) row_opt = try findTypeByMethodName(uctx, shortToken(filter_name));
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

/// Build a UnifiedContext from a combined index for a specific GenCtx's file,
/// using row 0 (dummy). Suitable for lookups that only read table_info/heaps.
fn makeCtxForFile(
    combined_index: *ui.UnifiedIndex,
    dep_queue: *ui.DependencyQueue,
    gctx: *GenCtx,
    allocator: std.mem.Allocator,
) ui.UnifiedContext {
    // Find the file_idx in the combined index that matches this GenCtx's data
    for (combined_index.files, 0..) |f, i| {
        if (f.raw_data.ptr == gctx.file_entries[0].raw_data.ptr) {
            return ui.UnifiedContext.make(combined_index, .{ .file_idx = @intCast(i), .row = 0 }, dep_queue, allocator);
        }
    }
    // Fallback: file_idx 0 (should not happen)
    return ui.UnifiedContext.make(combined_index, .{ .file_idx = 0, .row = 0 }, dep_queue, allocator);
}

/// Find a type row within a GenCtx using the combined index's dep_queue.
fn findExactTypeRowCombined(
    uctx: emit.Context,
    gctx: *GenCtx,
    filter_name: []const u8,
) !?u32 {
    var row_opt: ?u32 = null;
    row_opt = emit.findTypeDefRow(uctx, filter_name) catch null;
    if (row_opt == null) {
        if (std.mem.lastIndexOfScalar(u8, filter_name, '.')) |_| {
            row_opt = winmd2zig.resolver.findTypeDefRowByFullName(
                .{ .table_info = gctx.table_info, .heaps = gctx.heaps },
                filter_name,
            ) catch null;
        }
    }
    if (row_opt == null) row_opt = try findTypeByShortName(uctx, shortToken(filter_name));
    return row_opt;
}

/// Emit a type from a GenCtx using the combined index context.
fn emitOneExactTypeCombined(
    allocator: std.mem.Allocator,
    writer: anytype,
    uctx: emit.Context,
    gctx: *GenCtx,
    filter_name: []const u8,
) !bool {
    const row = try findExactTypeRowCombined(uctx, gctx, filter_name) orelse return false;
    try emitResolvedTypeWithCtx(allocator, writer, uctx, gctx.winmd_path, gctx.table_info, gctx.heaps, filter_name, row);
    return true;
}

fn emitOneTypeCombined(
    allocator: std.mem.Allocator,
    writer: anytype,
    uctx: emit.Context,
    gctx: *GenCtx,
    filter_name: []const u8,
) !bool {
    var row_opt = try findExactTypeRowCombined(uctx, gctx, filter_name);
    if (row_opt == null) row_opt = try findTypeByFieldName(uctx, shortToken(filter_name));
    if (row_opt == null) row_opt = try findTypeByMethodName(uctx, shortToken(filter_name));
    if (row_opt == null) return false;
    try emitResolvedTypeWithCtx(allocator, writer, uctx, gctx.winmd_path, gctx.table_info, gctx.heaps, filter_name, row_opt.?);
    return true;
}

/// Generate output from one or two GenCtx sources plus optional extra FileEntries
/// (e.g. companion WinMDs for cross-file resolution).
pub fn generateActualOutputWithExtras(
    allocator: std.mem.Allocator,
    win32: *GenCtx,
    winrt: *GenCtx,
    filters: []const []const u8,
    extra_files: []const ui.FileEntry,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    const writer = out.writer(allocator);

    try emit.writePrologue(writer);

    // Build a combined file list.
    var combined = std.ArrayList(ui.FileEntry).empty;
    defer combined.deinit(allocator);

    // Add win32 file
    try combined.append(allocator, win32.file_entries[0]);

    // Add winrt file if different from win32
    if (win32.file_entries[0].raw_data.ptr != winrt.file_entries[0].raw_data.ptr) {
        try combined.append(allocator, winrt.file_entries[0]);
    }

    // Add any extra companion files
    for (extra_files) |ef| {
        try combined.append(allocator, ef);
    }

    // Build a unified index over all files
    var combined_index = try ui.UnifiedIndex.init(allocator, combined.items);
    defer combined_index.deinit();

    var dep_queue = ui.DependencyQueue.init(allocator, &combined_index);
    defer dep_queue.deinit();

    // Build UnifiedContext values for each primary GenCtx (pointing into the combined index)
    const win32_uctx = makeCtxForFile(&combined_index, &dep_queue, win32, allocator);
    const winrt_uctx = makeCtxForFile(&combined_index, &dep_queue, winrt, allocator);

    var generated_types = std.StringHashMap(void).init(allocator);
    defer generated_types.deinit();

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
        if (try emitOneExactTypeCombined(allocator, writer, win32_uctx, win32, filter_name)) {
            emitted = true;
        } else if (try emitOneExactTypeCombined(allocator, writer, winrt_uctx, winrt, filter_name)) {
            emitted = true;
        } else if (try emitOneTypeCombined(allocator, writer, win32_uctx, win32, filter_name)) {
            emitted = true;
        } else if (try emitOneTypeCombined(allocator, writer, winrt_uctx, winrt, filter_name)) {
            emitted = true;
        }

        // Search companion files (extras) if not found in primary contexts
        if (!emitted) {
            const short_name = if (std.mem.lastIndexOfScalar(u8, filter_name, '.')) |d| filter_name[d + 1 ..] else filter_name;
            for (combined_index.files, 0..) |file, fi| {
                // Skip primary files (already searched above)
                if (file.raw_data.ptr == win32.file_entries[0].raw_data.ptr) continue;
                if (file.raw_data.ptr == winrt.file_entries[0].raw_data.ptr) continue;

                const t = file.table_info.getTable(.TypeDef);
                var crow: u32 = 1;
                while (crow <= t.row_count) : (crow += 1) {
                    const ctd = file.table_info.readTypeDef(crow) catch continue;
                    const cname = file.heaps.getString(ctd.type_name) catch continue;
                    if (!std.mem.eql(u8, cname, short_name)) continue;
                    const comp_uctx = ui.UnifiedContext.make(
                        &combined_index,
                        .{ .file_idx = @intCast(fi), .row = crow },
                        &dep_queue,
                        allocator,
                    );
                    const comp_cat = emit.identifyTypeCategory(comp_uctx, crow) catch continue;
                    switch (comp_cat) {
                        .struct_type => {
                            emit.emitStruct(allocator, writer, comp_uctx, crow) catch continue;
                            emitted = true;
                        },
                        .enum_type => {
                            emit.emitEnum(allocator, writer, comp_uctx, crow) catch continue;
                            emitted = true;
                        },
                        .delegate => {
                            emit.emitDelegate(allocator, writer, comp_uctx, crow) catch continue;
                            emitted = true;
                        },
                        .class => {
                            emit.emitClass(allocator, writer, comp_uctx, crow) catch continue;
                            emitted = true;
                        },
                        .interface => {
                            emit.emitInterface(allocator, writer, comp_uctx, "", cname) catch continue;
                            emitted = true;
                        },
                        else => continue,
                    }
                    break;
                }
                if (emitted) break;
            }
        }

        if (emitted) {
            emitted_any = true;
            // Drain new dependencies from the queue into our to_generate list
            while (dep_queue.next()) |loc| {
                const dep_name = combined_index.typeFullNameAlloc(allocator, loc) catch continue;
                if (!generated_types.contains(dep_name)) {
                    var in_queue = false;
                    for (to_generate.items[head + 1 ..]) |q| {
                        if (std.mem.eql(u8, q, dep_name)) {
                            in_queue = true;
                            break;
                        }
                    }
                    if (!in_queue) {
                        to_generate.append(allocator, dep_name) catch {
                            allocator.free(dep_name);
                            continue;
                        };
                    } else {
                        allocator.free(dep_name);
                    }
                } else {
                    allocator.free(dep_name);
                }
            }
        }
    }

    if (!emitted_any) return error.UnsupportedActualGeneration;
    return try out.toOwnedSlice(allocator);
}

/// Generate output from one or two GenCtx sources (no companion files).
pub fn generateActualOutput(
    allocator: std.mem.Allocator,
    win32: *GenCtx,
    winrt: *GenCtx,
    filters: []const []const u8,
) ![]u8 {
    return generateActualOutputWithExtras(allocator, win32, winrt, filters, &.{});
}

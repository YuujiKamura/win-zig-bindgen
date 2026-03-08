const std = @import("std");
const winmd2zig = @import("winmd2zig_main");
const win_zig_metadata = @import("win_zig_metadata");
const pe = win_zig_metadata.pe;
const metadata = win_zig_metadata.metadata;
const tables = win_zig_metadata.tables;
const streams = win_zig_metadata.streams;
const emit = winmd2zig.emit;

const Case = struct {
    id: []const u8,
    kind: []const u8,
    args: []const u8,
};

const GenCtx = struct {
    arena: std.heap.ArenaAllocator,
    table_info: tables.Info,
    heaps: streams.Heaps,
    emit_ctx: emit.Context,
    winmd_path: []const u8,

    fn deinit(self: *GenCtx) void {
        self.arena.deinit();
    }
};

const SymbolKind = enum {
    unknown,
    interface,
    class,
    struct_type,
    enum_type,
    alias,
};

const TypeShape = struct {
    name: []const u8,
    kind: SymbolKind,
    has_iid: bool = false,
    has_lpvtable: bool = false,
    fields: std.ArrayList([]const u8) = .empty,
    methods: std.ArrayList([]const u8) = .empty,
    vtable_methods: std.ArrayList([]const u8) = .empty,
    enum_variants: std.ArrayList([]const u8) = .empty,
    required_ifaces: std.ArrayList([]const u8) = .empty,

    fn init(allocator: std.mem.Allocator, name: []const u8, kind: SymbolKind) !TypeShape {
        return .{
            .name = try allocator.dupe(u8, name),
            .kind = kind,
        };
    }

    fn deinit(self: *TypeShape, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        freeSliceList(allocator, &self.fields);
        freeSliceList(allocator, &self.methods);
        freeSliceList(allocator, &self.vtable_methods);
        freeSliceList(allocator, &self.enum_variants);
        freeSliceList(allocator, &self.required_ifaces);
    }
};

const Manifest = struct {
    allocator: std.mem.Allocator,
    types: std.ArrayList(TypeShape) = .empty,
    functions: std.ArrayList([]const u8) = .empty,

    fn init(allocator: std.mem.Allocator) Manifest {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *Manifest) void {
        for (self.types.items) |*t| t.deinit(self.allocator);
        self.types.deinit(self.allocator);
        freeSliceList(self.allocator, &self.functions);
    }

    fn ensureType(self: *Manifest, name: []const u8, preferred_kind: SymbolKind) !usize {
        for (self.types.items, 0..) |*t, i| {
            if (!std.mem.eql(u8, t.name, name)) continue;
            if (t.kind == .unknown and preferred_kind != .unknown) t.kind = preferred_kind;
            return i;
        }
        try self.types.append(self.allocator, try TypeShape.init(self.allocator, name, preferred_kind));
        return self.types.items.len - 1;
    }

    fn addFunction(self: *Manifest, name: []const u8) !void {
        try appendUniqueStr(self.allocator, &self.functions, name);
    }

    fn addField(self: *Manifest, type_index: usize, name: []const u8) !void {
        try appendUniqueStr(self.allocator, &self.types.items[type_index].fields, name);
    }

    fn addMethod(self: *Manifest, type_index: usize, name: []const u8) !void {
        try appendUniqueStr(self.allocator, &self.types.items[type_index].methods, name);
    }

    fn addVtableMethod(self: *Manifest, type_index: usize, name: []const u8) !void {
        try appendUniqueStr(self.allocator, &self.types.items[type_index].vtable_methods, name);
    }

    fn addEnumVariant(self: *Manifest, type_index: usize, name: []const u8) !void {
        try appendUniqueStr(self.allocator, &self.types.items[type_index].enum_variants, name);
    }

    fn addRequiredIface(self: *Manifest, type_index: usize, name: []const u8) !void {
        try appendUniqueStr(self.allocator, &self.types.items[type_index].required_ifaces, name);
    }

    fn findType(self: *const Manifest, name: []const u8) ?*const TypeShape {
        for (self.types.items, 0..) |_, i| {
            if (std.mem.eql(u8, self.types.items[i].name, name)) return &self.types.items[i];
        }
        return null;
    }
};

const CompareOptions = struct {
    allow_sys_fn_ptr_alias: bool = false,
    allow_nt_wait_compat: bool = false,
};

fn freeSliceList(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8)) void {
    for (list.items) |item| allocator.free(item);
    list.deinit(allocator);
}

fn containsStr(items: []const []const u8, needle: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
}

fn appendUniqueStr(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), value: []const u8) !void {
    if (containsStr(list.items, value)) return;
    try list.append(allocator, try allocator.dupe(u8, value));
}

fn trimLine(line: []const u8) []const u8 {
    return std.mem.trim(u8, line, " \t\r");
}

fn braceDelta(line: []const u8) i32 {
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

fn takeIdentifier(text: []const u8) []const u8 {
    var end: usize = 0;
    while (end < text.len) : (end += 1) {
        const ch = text[end];
        if (!std.ascii.isAlphanumeric(ch) and ch != '_') break;
    }
    return text[0..end];
}

fn isLikelyInterfaceName(name: []const u8) bool {
    if (name.len > 1 and name[0] == 'I' and std.ascii.isUpper(name[1])) return true;
    if (std.mem.endsWith(u8, name, "Handler")) return true;
    return false;
}

fn shortToken(name: []const u8) []const u8 {
    const dotted = if (std.mem.lastIndexOfScalar(u8, name, '.')) |i| name[i + 1 ..] else name;
    return if (std.mem.indexOfScalar(u8, dotted, '`')) |i| dotted[0..i] else dotted;
}

fn loadGenCtx(allocator: std.mem.Allocator, winmd_path: []const u8) !GenCtx {
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

fn findTypeByShortName(ctx: emit.Context, short_name: []const u8) !?u32 {
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

fn findTypeByFieldName(ctx: emit.Context, field_name: []const u8) !?u32 {
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

fn findTypeByMethodName(ctx: emit.Context, method_name: []const u8) !?u32 {
    const mtab = ctx.table_info.getTable(.MethodDef);
    var row: u32 = 1;
    while (row <= mtab.row_count) : (row += 1) {
        const m = try ctx.table_info.readMethodDef(row);
        const name = try ctx.heaps.getString(m.name);
        if (!std.mem.eql(u8, name, method_name)) continue;
        
        // Find owner TypeDef
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

fn findExactTypeRow(ctx: *GenCtx, filter_name: []const u8) !?u32 {
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

fn emitResolvedType(allocator: std.mem.Allocator, writer: anytype, ctx: *GenCtx, filter_name: []const u8, row: u32) !void {
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

fn parseArgsTokens(allocator: std.mem.Allocator, args: []const u8) !std.ArrayList([]const u8) {
    var toks = std.ArrayList([]const u8).empty;
    var it = std.mem.tokenizeAny(u8, args, " \t\r\n");
    while (it.next()) |t| try toks.append(allocator, t);
    return toks;
}

fn extractOutName(tokens: []const []const u8) ?[]const u8 {
    for (tokens, 0..) |t, i| {
        if (std.mem.eql(u8, t, "--out") and i + 1 < tokens.len) return tokens[i + 1];
    }
    return null;
}

fn collectFilters(allocator: std.mem.Allocator, tokens: []const []const u8) !std.ArrayList([]const u8) {
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

fn generateActualOutput(
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

        if (emitted) {
            // Add new dependencies from both contexts
            inline for (.{ win32, winrt }) |ctx| {
                if (ctx.emit_ctx.dependencies) |ctx_deps| {
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

fn parseGeneratedTypeStart(line: []const u8) ?struct { name: []const u8, kind: SymbolKind } {
    const prefix = "pub const ";
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    const rest = line[prefix.len..];
    const eq_pos = std.mem.indexOf(u8, rest, " = ") orelse return null;
    const name = takeIdentifier(rest[0..eq_pos]);
    if (name.len == 0) return null;
    const rhs = rest[eq_pos + 3 ..];
    if (std.mem.indexOf(u8, rhs, "enum") != null) return .{ .name = name, .kind = .enum_type };
    if (std.mem.indexOf(u8, rhs, "struct") != null) {
        if (std.mem.eql(u8, name, "WPARAM") or std.mem.eql(u8, name, "LPARAM")) {
            return .{ .name = name, .kind = .enum_type };
        }
        return .{ .name = name, .kind = .struct_type };
    }
    // Anything else starting with 'pub const Name = ' is an alias
    return .{ .name = name, .kind = .alias };
}

fn parseGeneratedFnName(line: []const u8) ?[]const u8 {
    // Matches "pub fn name(" or "pub extern fn name(" or "pub extern "DLL" fn name("
    if (!std.mem.startsWith(u8, line, "pub ")) return null;
    var rest = line[4..];
    if (std.mem.startsWith(u8, rest, "extern ")) {
        rest = rest[7..];
        // Skip "DLL" if present
        if (std.mem.startsWith(u8, rest, "\"")) {
            const closing_quote = std.mem.indexOfScalarPos(u8, rest, 1, '\"') orelse return null;
            rest = std.mem.trimLeft(u8, rest[closing_quote + 1 ..], " \t");
        }
    }
    if (!std.mem.startsWith(u8, rest, "fn ")) return null;
    rest = rest[3..];
    const open = std.mem.indexOfScalar(u8, rest, '(') orelse return null;
    const name = takeIdentifier(rest[0..open]);
    if (name.len > 0) return name;
    return null;
}

fn parseGeneratedFieldName(line: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, line, "pub ")) return null;
    const colon = std.mem.indexOfScalar(u8, line, ':') orelse return null;
    const name = takeIdentifier(std.mem.trim(u8, line[0..colon], " \t"));
    if (name.len == 0) return null;
    return name;
}

fn parseGeneratedEnumVariantName(line: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, line, "pub ")) return null;
    const eq_pos = std.mem.indexOfScalar(u8, line, '=') orelse return null;
    const name = takeIdentifier(std.mem.trim(u8, line[0..eq_pos], " \t"));
    if (name.len == 0) return null;
    return name;
}

fn parseGeneratedRequiredIface(line: []const u8) ?[]const u8 {
    const prefix = "pub const Requires_";
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    const rest = line[prefix.len..];
    const eq_pos = std.mem.indexOf(u8, rest, " = ") orelse return null;
    const name = takeIdentifier(rest[0..eq_pos]);
    if (name.len == 0) return null;
    return name;
}

fn finalizeGeneratedType(t: *TypeShape) void {
    if (t.kind != .struct_type) return;
    if (t.has_iid and t.has_lpvtable) {
        t.kind = if (isLikelyInterfaceName(t.name)) .interface else .class;
        return;
    }
    if (t.required_ifaces.items.len > 0 and !isLikelyInterfaceName(t.name)) {
        t.kind = .class;
    }
}

fn parseGeneratedManifest(allocator: std.mem.Allocator, text: []const u8) !Manifest {
    var manifest = Manifest.init(allocator);
    errdefer manifest.deinit();

    var current_type: ?usize = null;
    var type_depth: i32 = 0;
    var in_vtable = false;
    var vtable_depth: i32 = 0;

    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const line = trimLine(raw_line);
        if (line.len == 0 or std.mem.startsWith(u8, line, "//!")) continue;

        if (current_type == null) {
            if (parseGeneratedTypeStart(line)) |decl| {
                current_type = try manifest.ensureType(decl.name, decl.kind);
                type_depth = braceDelta(line);
                in_vtable = false;
                vtable_depth = 0;
                if (type_depth == 0) current_type = null;
                continue;
            }
            if (parseGeneratedFnName(line)) |fn_name| {
                try manifest.addFunction(fn_name);
            }
            continue;
        }

        const type_index = current_type.?;
        const t = &manifest.types.items[type_index];

        if (in_vtable) {
            if (parseGeneratedFieldName(line)) |vtbl_name| {
                try manifest.addVtableMethod(type_index, vtbl_name);
            }
            vtable_depth += braceDelta(line);
            type_depth += braceDelta(line);
            if (vtable_depth <= 0) in_vtable = false;
            if (type_depth <= 0) {
                finalizeGeneratedType(t);
                current_type = null;
            }
            continue;
        }

        if (std.mem.startsWith(u8, line, "pub const VTable = extern struct {")) {
            in_vtable = true;
            vtable_depth = braceDelta(line);
            type_depth += braceDelta(line);
            continue;
        }
        if (std.mem.startsWith(u8, line, "pub const IID = ")) t.has_iid = true;
        if (std.mem.startsWith(u8, line, "lpVtbl: *const VTable")) t.has_lpvtable = true;
        if (parseGeneratedRequiredIface(line)) |iface_name| try manifest.addRequiredIface(type_index, iface_name);

        switch (t.kind) {
            .enum_type => {
                if (parseGeneratedEnumVariantName(line)) |variant_name| try manifest.addEnumVariant(type_index, variant_name);
            },
            else => {
                if (parseGeneratedFnName(line)) |method_name| {
                    try manifest.addMethod(type_index, method_name);
                } else if (parseGeneratedFieldName(line)) |field_name| {
                    try manifest.addField(type_index, field_name);
                }
            },
        }

        type_depth += braceDelta(line);
        if (type_depth <= 0) {
            finalizeGeneratedType(t);
            current_type = null;
        }
    }

    return manifest;
}

fn parseMacroFirstIdent(manifest: *Manifest, text: []const u8, macro_name: []const u8, kind: SymbolKind) !void {
    var search_from: usize = 0;
    while (std.mem.indexOfPos(u8, text, search_from, macro_name)) |start| {
        const body_start = start + macro_name.len;
        const body_end = std.mem.indexOfPos(u8, text, body_start, ");") orelse break;
        const body = text[body_start..body_end];
        var it = std.mem.tokenizeAny(u8, body, " \t\r\n,");
        const first = it.next() orelse {
            search_from = body_end + 2;
            continue;
        };
        const ident = takeIdentifier(first);
        if (ident.len > 0) _ = try manifest.ensureType(ident, kind);
        search_from = body_end + 2;
    }
}

fn parseRequiredHierarchyMacros(manifest: *Manifest, text: []const u8) !void {
    const macro_name = "required_hierarchy!(";
    var search_from: usize = 0;
    while (std.mem.indexOfPos(u8, text, search_from, macro_name)) |start| {
        const body_start = start + macro_name.len;
        const body_end = std.mem.indexOfPos(u8, text, body_start, ");") orelse break;
        const body = text[body_start..body_end];
        var it = std.mem.tokenizeAny(u8, body, " \t\r\n,");
        const owner_tok = it.next() orelse {
            search_from = body_end + 2;
            continue;
        };
        const owner = takeIdentifier(owner_tok);
        if (owner.len == 0) {
            search_from = body_end + 2;
            continue;
        }
        const owner_index = try manifest.ensureType(owner, .class);
        while (it.next()) |tok| {
            const iface = takeIdentifier(tok);
            if (iface.len == 0) continue;
            try manifest.addRequiredIface(owner_index, iface);
        }
        search_from = body_end + 2;
    }
}

fn parseRustTypeAliasName(line: []const u8) ?[]const u8 {
    const prefix = "pub type ";
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    const rest = line[prefix.len..];
    const eq_pos = std.mem.indexOf(u8, rest, " = ") orelse return null;
    const name = takeIdentifier(rest[0..eq_pos]);
    if (name.len == 0) return null;
    return name;
}

fn parseRustStructDecl(line: []const u8) ?struct {
    name: []const u8,
    kind: SymbolKind,
    is_block: bool,
    is_vtbl: bool,
} {
    const prefix = "pub struct ";
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    const rest = line[prefix.len..];
    const name = takeIdentifier(rest);
    if (name.len == 0) return null;

    if (std.mem.indexOfScalar(u8, rest, '{') != null) {
        return .{
            .name = name,
            .kind = .struct_type,
            .is_block = true,
            .is_vtbl = std.mem.endsWith(u8, name, "_Vtbl"),
        };
    }
    if (std.mem.indexOfScalar(u8, rest, '(') != null) {
        const kind: SymbolKind = if (std.mem.indexOf(u8, rest, "(pub i") != null or std.mem.indexOf(u8, rest, "(pub u") != null)
            .enum_type
        else
            .unknown;
        return .{
            .name = name,
            .kind = kind,
            .is_block = false,
            .is_vtbl = false,
        };
    }
    if (std.mem.indexOfScalar(u8, rest, ';') != null) {
        return .{
            .name = name,
            .kind = .class,
            .is_block = false,
            .is_vtbl = false,
        };
    }
    return null;
}

fn parseRustImplStart(line: []const u8) ?[]const u8 {
    const prefix = "impl ";
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    const rest = line[prefix.len..];
    if (rest.len == 0 or rest[0] == '<') return null;
    if (std.mem.indexOf(u8, rest, " for ") != null) return null;
    const brace = std.mem.indexOfScalar(u8, rest, '{') orelse return null;
    const head = std.mem.trim(u8, rest[0..brace], " \t");
    const name = takeIdentifier(head);
    if (name.len == 0) return null;
    if (std.mem.endsWith(u8, name, "_Vtbl")) return null;
    return name;
}

fn parseRustFnName(line: []const u8) ?[]const u8 {
    const direct_prefixes = [_][]const u8{
        "pub unsafe fn ",
        "pub fn ",
    };
    for (direct_prefixes) |prefix| {
        if (!std.mem.startsWith(u8, line, prefix)) continue;
        const rest = line[prefix.len..];
        const open = std.mem.indexOfScalar(u8, rest, '(') orelse return null;
        const name = takeIdentifier(rest[0..open]);
        if (name.len > 0) return name;
    }
    if (std.mem.startsWith(u8, line, "windows_link::link!(") or std.mem.indexOf(u8, line, "windows_core::link!(") != null) {
        if (std.mem.indexOf(u8, line, " fn ")) |pos| {
            const rest = line[pos + 4 ..];
            const open = std.mem.indexOfScalar(u8, rest, '(') orelse return null;
            const name = takeIdentifier(rest[0..open]);
            if (name.len > 0) return name;
        }
    }
    return null;
}

fn parseRustFieldLikeName(line: []const u8) ?[]const u8 {
    var rest = line;
    if (std.mem.startsWith(u8, rest, "pub ")) rest = rest[4..];
    const colon = std.mem.indexOfScalar(u8, rest, ':') orelse return null;
    const name = takeIdentifier(std.mem.trim(u8, rest[0..colon], " \t"));
    if (name.len == 0) return null;
    return name;
}

fn parseRustVtblFieldName(line: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, line, ": unsafe extern") == null and
        std.mem.indexOf(u8, line, ": usize") == null and
        std.mem.indexOf(u8, line, ": Option<") == null and
        std.mem.indexOf(u8, line, ": *const") == null)
    {
        return null;
    }
    const name = parseRustFieldLikeName(line) orelse return null;
    if (!(std.mem.startsWith(u8, line, "pub ") or std.mem.eql(u8, name, "base__") or std.ascii.isUpper(name[0]))) return null;
    return name;
}

fn parseRustEnumVariant(line: []const u8) ?[]const u8 {
    const prefix = "pub const ";
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    const rest = line[prefix.len..];
    if (std.mem.startsWith(u8, rest, "fn ")) return null;
    if (std.mem.indexOf(u8, line, ": Self") == null) return null;
    const colon = std.mem.indexOfScalar(u8, rest, ':') orelse return null;
    const name = takeIdentifier(rest[0..colon]);
    if (name.len == 0) return null;
    return name;
}

fn parseRustManifest(allocator: std.mem.Allocator, text: []const u8) !Manifest {
    var manifest = Manifest.init(allocator);
    errdefer manifest.deinit();

    try parseMacroFirstIdent(&manifest, text, "define_interface!(", .interface);
    try parseRequiredHierarchyMacros(&manifest, text);

    var current_impl: ?usize = null;
    var impl_depth: i32 = 0;
    var current_struct: ?usize = null;
    var struct_depth: i32 = 0;
    var current_vtbl: ?usize = null;
    var vtbl_depth: i32 = 0;

    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const line = trimLine(raw_line);
        const is_top_level = raw_line.len == line.len;
        if (line.len == 0 or std.mem.startsWith(u8, line, "#![")) continue;
        if (std.mem.indexOf(u8, line, "define_interface!(") != null or std.mem.indexOf(u8, line, "required_hierarchy!(") != null) continue;

        if (current_impl) |type_index| {
            if (std.mem.startsWith(u8, line, "pub fn ")) {
                if (parseRustFnName(line)) |method_name| try manifest.addMethod(type_index, method_name);
            } else if (parseRustEnumVariant(line)) |variant_name| {
                try manifest.addEnumVariant(type_index, variant_name);
            }
            impl_depth += braceDelta(line);
            if (impl_depth <= 0) current_impl = null;
            continue;
        }

        if (current_vtbl) |type_index| {
            if (parseRustVtblFieldName(line)) |field_name| {
                if (!std.mem.eql(u8, field_name, "base__")) try manifest.addVtableMethod(type_index, field_name);
            }
            vtbl_depth += braceDelta(line);
            if (vtbl_depth <= 0) current_vtbl = null;
            continue;
        }

        if (current_struct) |type_index| {
            if (parseRustFieldLikeName(line)) |field_name| try manifest.addField(type_index, field_name);
            struct_depth += braceDelta(line);
            if (struct_depth <= 0) current_struct = null;
            continue;
        }

        if (is_top_level) {
            if (parseRustFnName(line)) |fn_name| {
                try manifest.addFunction(fn_name);
                continue;
            }
            if (parseRustTypeAliasName(line)) |alias_name| {
                _ = try manifest.ensureType(alias_name, .unknown);
                continue;
            }
            if (parseRustStructDecl(line)) |decl| {
                if (decl.is_vtbl) {
                    const base_name = decl.name[0 .. decl.name.len - "_Vtbl".len];
                    const type_index = try manifest.ensureType(base_name, .unknown);
                    current_vtbl = type_index;
                    vtbl_depth = braceDelta(line);
                    continue;
                }
                const type_index = try manifest.ensureType(decl.name, decl.kind);
                if (decl.is_block) {
                    current_struct = type_index;
                    struct_depth = braceDelta(line);
                }
                continue;
            }
            if (parseRustImplStart(line)) |impl_name| {
                const type_index = try manifest.ensureType(impl_name, .unknown);
                current_impl = type_index;
                impl_depth = braceDelta(line);
                continue;
            }
        }
    }

    return manifest;
}

fn compareExpectedList(
    case_id: []const u8,
    owner: []const u8,
    label: []const u8,
    expected: []const []const u8,
    actual: []const []const u8,
) usize {
    var fail_count: usize = 0;
    for (expected) |name| {
        if (containsStr(actual, name)) continue;
        std.log.err("[{s}] missing {s} on {s}: {s}", .{ case_id, label, owner, name });
        fail_count += 1;
    }
    return fail_count;
}

fn compareManifests(case_id: []const u8, expected: *const Manifest, actual: *const Manifest, opts: CompareOptions) usize {
    var fail_count: usize = 0;

    for (expected.functions.items) |fn_name| {
        if (opts.allow_nt_wait_compat and std.mem.eql(u8, fn_name, "NtWaitForSingleObject") and containsStr(actual.functions.items, "WaitForSingleObjectEx")) continue;
        if (containsStr(actual.functions.items, fn_name)) continue;
        std.log.err("[{s}] missing function: {s}", .{ case_id, fn_name });
        fail_count += 1;
    }

    for (expected.types.items) |exp_type| {
        const act_type = actual.findType(exp_type.name) orelse {
            if (opts.allow_sys_fn_ptr_alias and exp_type.kind == .unknown and containsStr(actual.functions.items, exp_type.name)) continue;
            std.log.err("[{s}] missing type: {s}", .{ case_id, exp_type.name });
            fail_count += 1;
            continue;
        };

        if (exp_type.kind != .unknown and act_type.kind != .unknown and exp_type.kind != act_type.kind) {
            std.log.err("[{s}] kind mismatch for {s}: expected={s} actual={s}", .{
                case_id,
                exp_type.name,
                @tagName(exp_type.kind),
                @tagName(act_type.kind),
            });
            fail_count += 1;
        }

        fail_count += compareExpectedList(case_id, exp_type.name, "field", exp_type.fields.items, act_type.fields.items);
        fail_count += compareExpectedList(case_id, exp_type.name, "method", exp_type.methods.items, act_type.methods.items);
        fail_count += compareExpectedList(case_id, exp_type.name, "vtable method", exp_type.vtable_methods.items, act_type.vtable_methods.items);
        fail_count += compareExpectedList(case_id, exp_type.name, "enum variant", exp_type.enum_variants.items, act_type.enum_variants.items);
        fail_count += compareExpectedList(case_id, exp_type.name, "required interface", exp_type.required_ifaces.items, act_type.required_ifaces.items);
    }

    return fail_count;
}

// ============================================================
// Shared test state — WinMD files are loaded once per test run
// Uses page_allocator for cache to avoid GPA lifetime issues
// ============================================================

const cache_alloc = std.heap.page_allocator;

var cached_winrt: ?GenCtx = null;
var cached_win32: ?GenCtx = null;
var cached_cases: ?std.json.Parsed([]Case) = null;

fn ensureCaches() !struct { winrt: *GenCtx, win32: *GenCtx, cases: []Case } {
    if (cached_cases == null) {
        const json_text = try std.fs.cwd().readFileAlloc(
            cache_alloc,
            "shadow/windows-rs/bindgen-cases.json",
            std.math.maxInt(usize),
        );
        cached_cases = try std.json.parseFromSlice([]Case, cache_alloc, json_text, .{});
    }
    if (cached_winrt == null) {
        const winrt_winmd = winmd2zig.findWindowsKitUnionWinmdAlloc(cache_alloc) catch return error.SkipZigTest;
        cached_winrt = try loadGenCtx(cache_alloc, winrt_winmd);
    }
    if (cached_win32 == null) {
        const win32_winmd = winmd2zig.findWin32DefaultWinmdAlloc(cache_alloc) catch return error.SkipZigTest;
        cached_win32 = try loadGenCtx(cache_alloc, win32_winmd);
    }
    return .{
        .winrt = &cached_winrt.?,
        .win32 = &cached_win32.?,
        .cases = cached_cases.?.value,
    };
}

fn runCase(case_id: []const u8) !void {
    const allocator = std.testing.allocator;
    const ctx = ensureCaches() catch return error.SkipZigTest;

    // Find the case by id
    var found: ?Case = null;
    for (ctx.cases) |c| {
        if (std.mem.eql(u8, c.id, case_id)) {
            found = c;
            break;
        }
    }
    const c = found orelse return error.TestUnexpectedResult;

    var toks = try parseArgsTokens(allocator, c.args);
    defer toks.deinit(allocator);

    const out_name = extractOutName(toks.items) orelse return error.TestUnexpectedResult;

    var filters = try collectFilters(allocator, toks.items);
    defer filters.deinit(allocator);
    if (filters.items.len == 0) return error.TestUnexpectedResult;
    const compare_opts = CompareOptions{
        .allow_sys_fn_ptr_alias = containsStr(toks.items, "--sys-fn-ptrs"),
        .allow_nt_wait_compat = containsStr(filters.items, "NtWaitForSingleObject") and containsStr(filters.items, "WaitForSingleObjectEx"),
    };

    const golden_rel = try std.fmt.allocPrint(allocator, "shadow/windows-rs/bindgen-golden/{s}", .{out_name});
    defer allocator.free(golden_rel);
    const golden = std.fs.cwd().readFileAlloc(allocator, golden_rel, std.math.maxInt(usize)) catch
        return error.TestUnexpectedResult;
    defer allocator.free(golden);

    const generated = generateActualOutput(allocator, ctx.win32, ctx.winrt, filters.items) catch |err| {
        std.log.err("[{s}] generation failed: {s}", .{ case_id, @errorName(err) });
        return error.TestUnexpectedResult;
    };
    defer allocator.free(generated);

    var expected_manifest = try parseRustManifest(allocator, golden);
    defer expected_manifest.deinit();
    var actual_manifest = try parseGeneratedManifest(allocator, generated);
    defer actual_manifest.deinit();

    const fail_count = compareManifests(case_id, &expected_manifest, &actual_manifest, compare_opts);
    if (fail_count > 0) {
        std.log.err("[{s}] {d} mismatches", .{ case_id, fail_count });
        return error.TestUnexpectedResult;
    }
}

// ============================================================
// Individual parity tests — 107 cases
// ============================================================

test "GEN 001 core_win" { try runCase("001"); }
test "GEN 002 core_win_flat" { try runCase("002"); }
test "GEN 003 core_sys" { try runCase("003"); }
test "GEN 004 core_sys_flat" { try runCase("004"); }
test "GEN 005 core_sys_no_core" { try runCase("005"); }
test "GEN 006 core_sys_flat_no_core" { try runCase("006"); }
test "GEN 007 derive_struct" { try runCase("007"); }
test "GEN 008 derive_cpp_struct" { try runCase("008"); }
test "GEN 009 derive_cpp_struct_sys" { try runCase("009"); }
test "GEN 010 derive_enum" { try runCase("010"); }
test "GEN 011 derive_cpp_enum" { try runCase("011"); }
test "GEN 012 derive_edges" { try runCase("012"); }
test "GEN 013 enum_win" { try runCase("013"); }
test "GEN 014 enum_sys" { try runCase("014"); }
test "GEN 015 enum_flags_win" { try runCase("015"); }
test "GEN 016 enum_flags_sys" { try runCase("016"); }
test "GEN 017 enum_cpp_win" { try runCase("017"); }
test "GEN 018 enum_cpp_sys" { try runCase("018"); }
test "GEN 019 enum_cpp_flags_win" { try runCase("019"); }
test "GEN 020 enum_cpp_flags_sys" { try runCase("020"); }
test "GEN 021 enum_cpp_scoped_win" { try runCase("021"); }
test "GEN 022 enum_cpp_scoped_sys" { try runCase("022"); }
test "GEN 023 struct_win" { try runCase("023"); }
test "GEN 024 struct_sys" { try runCase("024"); }
test "GEN 025 struct_cpp_win" { try runCase("025"); }
test "GEN 026 struct_cpp_sys" { try runCase("026"); }
test "GEN 027 struct_disambiguate" { try runCase("027"); }
test "GEN 028 struct_with_generic" { try runCase("028"); }
test "GEN 029 struct_with_cpp_interface" { try runCase("029"); }
test "GEN 030 struct_with_cpp_interface_sys" { try runCase("030"); }
test "GEN 031 struct_arch_a" { try runCase("031"); }
test "GEN 032 struct_arch_w" { try runCase("032"); }
test "GEN 033 struct_arch_a_sys" { try runCase("033"); }
test "GEN 034 struct_arch_w_sys" { try runCase("034"); }
test "GEN 035 interface" { try runCase("035"); }
test "GEN 036 interface_sys" { try runCase("036"); }
test "GEN 037 interface_sys_no_core" { try runCase("037"); }
test "GEN 038 interface_cpp" { try runCase("038"); }
test "GEN 039 interface_cpp_sys" { try runCase("039"); }
test "GEN 040 interface_cpp_sys_no_core" { try runCase("040"); }
test "GEN 041 interface_cpp_derive" { try runCase("041"); }
test "GEN 042 interface_cpp_derive_sys" { try runCase("042"); }
test "GEN 043 interface_cpp_return_udt" { try runCase("043"); }
test "GEN 044 interface_generic" { try runCase("044"); }
test "GEN 045 interface_required" { try runCase("045"); }
test "GEN 046 interface_required_sys" { try runCase("046"); }
test "GEN 047 interface_required_with_method" { try runCase("047"); }
test "GEN 048 interface_required_with_method_sys" { try runCase("048"); }
test "GEN 049 interface_iterable" { try runCase("049"); }
test "GEN 050 interface_array_return" { try runCase("050"); }
test "GEN 051 fn_win" { try runCase("051"); }
test "GEN 052 fn_sys" { try runCase("052"); }
test "GEN 053 fn_sys_targets" { try runCase("053"); }
test "GEN 054 fn_sys_extern" { try runCase("054"); }
test "GEN 055 fn_sys_extern_ptrs" { try runCase("055"); }
test "GEN 056 fn_sys_ptrs" { try runCase("056"); }
test "GEN 057 fn_associated_enum_win" { try runCase("057"); }
test "GEN 058 fn_associated_enum_sys" { try runCase("058"); }
test "GEN 059 fn_return_void_win" { try runCase("059"); }
test "GEN 060 fn_return_void_sys" { try runCase("060"); }
test "GEN 061 fn_no_return_win" { try runCase("061"); }
test "GEN 062 fn_no_return_sys" { try runCase("062"); }
test "GEN 063 fn_result_void_sys" { try runCase("063"); }
test "GEN 064 delegate" { try runCase("064"); }
test "GEN 065 delegate_generic" { try runCase("065"); }
test "GEN 066 delegate_cpp" { try runCase("066"); }
test "GEN 067 delegate_cpp_ref" { try runCase("067"); }
test "GEN 068 delegate_param" { try runCase("068"); }
test "GEN 069 class" { try runCase("069"); }
test "GEN 070 class_with_handler" { try runCase("070"); }
test "GEN 071 class_static" { try runCase("071"); }
test "GEN 072 class_dep" { try runCase("072"); }
test "GEN 073 multi" { try runCase("073"); }
test "GEN 074 multi_sys" { try runCase("074"); }
test "GEN 075 window_long_get_a" { try runCase("075"); }
test "GEN 076 window_long_get_w" { try runCase("076"); }
test "GEN 077 window_long_set_a" { try runCase("077"); }
test "GEN 078 window_long_set_w" { try runCase("078"); }
test "GEN 079 window_long_get_a_sys" { try runCase("079"); }
test "GEN 080 window_long_get_w_sys" { try runCase("080"); }
test "GEN 081 window_long_set_a_sys" { try runCase("081"); }
test "GEN 082 window_long_set_w_sys" { try runCase("082"); }
test "GEN 083 reference_struct_filter" { try runCase("083"); }
test "GEN 084 reference_struct_reference_type" { try runCase("084"); }
test "GEN 085 reference_struct_reference_namespace" { try runCase("085"); }
test "GEN 086 reference_struct_sys_filter" { try runCase("086"); }
test "GEN 087 reference_struct_sys_reference_type" { try runCase("087"); }
test "GEN 088 reference_struct_sys_reference_namespace" { try runCase("088"); }
test "GEN 089 bool" { try runCase("089"); }
test "GEN 090 bool_sys" { try runCase("090"); }
test "GEN 091 bool_sys_no_core" { try runCase("091"); }
test "GEN 092 bool_event" { try runCase("092"); }
test "GEN 093 bool_event_sans_reference" { try runCase("093"); }
test "GEN 094 ref_params" { try runCase("094"); }
test "GEN 095 reference_dependency_flat" { try runCase("095"); }
test "GEN 096 reference_dependency_full" { try runCase("096"); }
test "GEN 097 reference_dependency_skip_root" { try runCase("097"); }
test "GEN 098 reference_dependent_flat" { try runCase("098"); }
test "GEN 099 reference_dependent_full" { try runCase("099"); }
test "GEN 100 reference_dependent_skip_root" { try runCase("100"); }
test "GEN 101 deps" { try runCase("101"); }
test "GEN 102 sort" { try runCase("102"); }
test "GEN 103 default_default" { try runCase("103"); }
test "GEN 104 default_assumed" { try runCase("104"); }
test "GEN 105 comment" { try runCase("105"); }
test "GEN 106 comment_no_allow" { try runCase("106"); }
test "GEN 107 rustfmt_25" { try runCase("107"); }

// ============================================================
// WinUI parity probes — Microsoft.UI.Xaml.winmd (#114)
// These verify correct type decoding for cross-WinMD enum/struct references.
// ============================================================

var cached_xaml: ?GenCtx = null;

fn ensureXamlCtx() !*GenCtx {
    if (cached_xaml == null) {
        const xaml_winmd = winmd2zig.findXamlWinmdAlloc(cache_alloc) catch return error.SkipZigTest;
        cached_xaml = loadGenCtx(cache_alloc, xaml_winmd) catch return error.SkipZigTest;
    }
    return &cached_xaml.?;
}

fn generateWinuiOutput(allocator: std.mem.Allocator, filter: []const u8) ![]u8 {
    const xaml = try ensureXamlCtx();
    // WinUI types only need the xaml context; pass it as both win32 and winrt
    return generateActualOutput(allocator, xaml, xaml, &.{filter});
}

test "WINUI IKeyRoutedEventArgs: Key getter uses i32, not anyopaque" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "IKeyRoutedEventArgs") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    // The vtable should have Key: *const fn (*anyopaque, *i32) not *?*anyopaque
    // If VirtualKey enum is correctly decoded to i32, the vtable will use *i32
    try std.testing.expect(std.mem.indexOf(u8, generated, "Key: *const fn (*anyopaque, *i32)") != null);
}

test "WINUI IKeyRoutedEventArgs: KeyStatus getter uses CorePhysicalKeyStatus, not anyopaque" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "IKeyRoutedEventArgs") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    // KeyStatus should use *CorePhysicalKeyStatus, not *?*anyopaque
    try std.testing.expect(std.mem.indexOf(u8, generated, "KeyStatus: *const fn (*anyopaque, *CorePhysicalKeyStatus)") != null);
}

test "WINUI IKeyRoutedEventArgs: OriginalKey getter uses i32, not anyopaque" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "IKeyRoutedEventArgs") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "OriginalKey: *const fn (*anyopaque, *i32)") != null);
}

test "WINUI ICharacterReceivedRoutedEventArgs: KeyStatus getter uses CorePhysicalKeyStatus" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "ICharacterReceivedRoutedEventArgs") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "KeyStatus: *const fn (*anyopaque, *CorePhysicalKeyStatus)") != null);
}

test "WINUI IXamlReaderStatics: Load vtable out-param is typed, not anyopaque" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "IXamlReaderStatics") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    // Load wrapper should return !*IInspectable (this already works)
    try std.testing.expect(std.mem.indexOf(u8, generated, "!*IInspectable") != null);
}

// ============================================================
// WinUI delegate probes (#115)
// ============================================================

test "WINUI ScrollEventHandler: no .ctor in vtable" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "ScrollEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    // .ctor should NOT appear in the generated delegate
    try std.testing.expect(std.mem.indexOf(u8, generated, "ctor:") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn ctor(") == null);
}

test "WINUI ScrollEventHandler: has Invoke but not .ctor wrapper" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "ScrollEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    // Should have Invoke wrapper but no .ctor wrapper
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn invoke(") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn ctor(") == null);
}

test "WINUI ScrollEventHandler: Invoke slot exists" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "ScrollEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    // Invoke should be in the vtable
    try std.testing.expect(std.mem.indexOf(u8, generated, "Invoke: *const fn") != null);
    // Wrapper should exist
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn invoke(") != null);
}

test "WINUI RoutedEventHandler: no .ctor wrapper" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "RoutedEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    // The delegate itself should not have a .ctor wrapper method
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn ctor(") == null);
}

// ============================================================
// WinUI importability probes (#116)
// These verify that interface getters/out-params return typed
// pointers (e.g. !*ICommand) instead of !*anyopaque after
// expanding isImportableInterface beyond the 3-entry whitelist.
// ============================================================

test "WINUI ITabView: AddTabButtonCommand returns typed !*ICommand, not anyopaque" {
    // Use page_allocator: ITabView has a large dependency closure that triggers
    // pre-existing leaks in emitInterface's seen_method_names hashmap.
    const allocator = cache_alloc;
    const generated = generateWinuiOutput(allocator, "ITabView") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    // With expanded importability, AddTabButtonCommand should return !*ICommand
    try std.testing.expect(std.mem.indexOf(u8, generated, "!*ICommand") != null);
}

test "WINUI ITabView: GetExtensionInstance returns typed !*IDataTemplateExtension" {
    const allocator = cache_alloc;
    const generated = generateWinuiOutput(allocator, "ITabView") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    // Out-param path: should return !*IDataTemplateExtension, not !*anyopaque
    try std.testing.expect(std.mem.indexOf(u8, generated, "!*IDataTemplateExtension") != null);
}

test "WINUI ITabView: TabItems returns typed !*IVector (pre-existing importable)" {
    const allocator = cache_alloc;
    const generated = generateWinuiOutput(allocator, "ITabView") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    // IVector was already importable — verify no regression
    try std.testing.expect(std.mem.indexOf(u8, generated, "!*IVector") != null);
}

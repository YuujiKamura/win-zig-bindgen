const zig_std = @import("std");
const win_zig_metadata = @import("win_zig_metadata");
const pe = win_zig_metadata.pe;
const metadata = win_zig_metadata.metadata;
const tables = win_zig_metadata.tables;
const streams = win_zig_metadata.streams;
const coded = win_zig_metadata.coded_index;
pub const emit = @import("emit.zig");
pub const resolver = @import("resolver.zig");
const sdk_discovery = @import("sdk_discovery.zig");

pub const findWindowsKitUnionWinmdAlloc = sdk_discovery.findWindowsKitUnionWinmdAlloc;
pub const findWin32DefaultWinmdAlloc = sdk_discovery.findWin32DefaultWinmdAlloc;
pub const findXamlWinmdAlloc = sdk_discovery.findXamlWinmdAlloc;

pub fn hasTypeDefByNameAlloc(allocator: zig_std.mem.Allocator, winmd_path: []const u8, full_name: []const u8) !bool {
    var arena = zig_std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const data = try zig_std.fs.cwd().readFileAlloc(a, winmd_path, zig_std.math.maxInt(usize));
    const pe_info = try pe.parse(a, data);
    const md_info = try metadata.parse(a, pe_info);
    const table_stream = if (md_info.getStream("#~")) |s| s else if (md_info.getStream("#-")) |s| s else return error.MissingTableStream;
    const strings_stream = md_info.getStream("#Strings") orelse return error.MissingStringsStream;

    const table_info = try tables.parse(table_stream.data);
    const heaps = streams.Heaps{ .strings = strings_stream.data, .blob = &.{}, .guid = &.{} };

    const split_at = zig_std.mem.lastIndexOfScalar(u8, full_name, '.') orelse return false;
    const ns = full_name[0..split_at];
    const name = full_name[split_at + 1 ..];

    const t = table_info.getTable(.TypeDef);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const td = try table_info.readTypeDef(row);
        const n = try heaps.getString(td.type_name);
        const nspace = try heaps.getString(td.type_namespace);
        if (zig_std.mem.eql(u8, n, name) and zig_std.mem.eql(u8, nspace, ns)) return true;
    }
    return false;
}

pub fn hasMethodDefByNameAlloc(allocator: zig_std.mem.Allocator, winmd_path: []const u8, method_name: []const u8) !bool {
    var arena = zig_std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const data = try zig_std.fs.cwd().readFileAlloc(a, winmd_path, zig_std.math.maxInt(usize));
    const pe_info = try pe.parse(a, data);
    const md_info = try metadata.parse(a, pe_info);
    const table_stream = if (md_info.getStream("#~")) |s| s else if (md_info.getStream("#-")) |s| s else return error.MissingTableStream;
    const strings_stream = md_info.getStream("#Strings") orelse return error.MissingStringsStream;

    const table_info = try tables.parse(table_stream.data);
    const heaps = streams.Heaps{ .strings = strings_stream.data, .blob = &.{}, .guid = &.{} };

    const t = table_info.getTable(.MethodDef);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const md_row = try table_info.readMethodDef(row);
        const n = try heaps.getString(md_row.name);
        if (zig_std.mem.eql(u8, n, method_name)) return true;
    }
    return false;
}

const SigCursor = struct {
    data: []const u8,
    pos: usize = 0,
    fn readByte(self: *@This()) ?u8 {
        if (self.pos >= self.data.len) return null;
        const b = self.data[self.pos];
        self.pos += 1;
        return b;
    }
    fn readCompressedUInt(self: *@This()) ?u32 {
        const b1 = self.readByte() orelse return null;
        if (b1 & 0x80 == 0) return b1;
        const b2 = self.readByte() orelse return null;
        if (b1 & 0x40 == 0) return (@as(u32, b1 & 0x3F) << 8) | b2;
        const b3 = self.readByte() orelse return null;
        const b4 = self.readByte() orelse return null;
        return (@as(u32, b1 & 0x1F) << 24) | (@as(u32, b2) << 16) | (@as(u32, b3) << 8) | b4;
    }
};

fn resolveTypeDefOrRefFullNameAlloc(allocator: zig_std.mem.Allocator, table_info: tables.Info, heaps: streams.Heaps, tdor_idx: u32) ![]u8 {
    const tdor = try coded.decodeTypeDefOrRef(tdor_idx);
    return switch (tdor.table) {
        .TypeDef => blk: {
            const td = try table_info.readTypeDef(tdor.row);
            const ns = try heaps.getString(td.type_namespace);
            const name = try heaps.getString(td.type_name);
            if (ns.len == 0) break :blk try allocator.dupe(u8, name);
            break :blk try zig_std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns, name });
        },
        .TypeRef => blk: {
            const tr = try table_info.readTypeRef(tdor.row);
            const ns = try heaps.getString(tr.type_namespace);
            const name = try heaps.getString(tr.type_name);
            if (ns.len == 0) break :blk try allocator.dupe(u8, name);
            break :blk try zig_std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns, name });
        },
        else => return error.UnsupportedTypeSpec,
    };
}

fn decodeSigTypeForAbi(allocator: zig_std.mem.Allocator, table_info: tables.Info, heaps: streams.Heaps, c: *SigCursor) ![]u8 {
    const b = c.readByte() orelse return try allocator.dupe(u8, "?unknown");
    return switch (b) {
        0x01 => try allocator.dupe(u8, "void"),
        0x02 => try allocator.dupe(u8, "bool"),
        0x03 => try allocator.dupe(u8, "u16"),
        0x04 => try allocator.dupe(u8, "i8"),
        0x05 => try allocator.dupe(u8, "u8"),
        0x06 => try allocator.dupe(u8, "i16"),
        0x07 => try allocator.dupe(u8, "u16"),
        0x08 => try allocator.dupe(u8, "i32"),
        0x09 => try allocator.dupe(u8, "u32"),
        0x0a => try allocator.dupe(u8, "i64"),
        0x0b => try allocator.dupe(u8, "u64"),
        0x0c => try allocator.dupe(u8, "f32"),
        0x0d => try allocator.dupe(u8, "f64"),
        0x0e => try allocator.dupe(u8, "HSTRING"),
        0x18 => try allocator.dupe(u8, "isize"),
        0x19 => try allocator.dupe(u8, "usize"),
        0x0f, 0x10 => blk: {
            const inner = try decodeSigTypeForAbi(allocator, table_info, heaps, c);
            defer allocator.free(inner);
            break :blk try zig_std.fmt.allocPrint(allocator, "*{s}", .{inner});
        },
        0x11, 0x12 => blk: {
            const tdor_idx = c.readCompressedUInt() orelse break :blk try allocator.dupe(u8, "?unknown");
            const full_name = try resolveTypeDefOrRefFullNameAlloc(allocator, table_info, heaps, tdor_idx);
            if (zig_std.mem.eql(u8, full_name, "System.Guid")) {
                allocator.free(full_name);
                break :blk try allocator.dupe(u8, "GUID");
            }
            if (zig_std.mem.eql(u8, full_name, "System.IntPtr")) {
                allocator.free(full_name);
                break :blk try allocator.dupe(u8, "isize");
            }
            if (zig_std.mem.eql(u8, full_name, "System.UIntPtr")) {
                allocator.free(full_name);
                break :blk try allocator.dupe(u8, "usize");
            }
            break :blk full_name;
        },
        0x15 => blk: {
            // GENERICINST
            _ = c.readByte(); // CLASS or VALUETYPE
            const tdor_idx = c.readCompressedUInt() orelse break :blk try allocator.dupe(u8, "?unknown");
            const gen_arg_count = c.readCompressedUInt() orelse break :blk try allocator.dupe(u8, "?unknown");
            var ga: u32 = 0;
            while (ga < gen_arg_count) : (ga += 1) {
                const arg = try decodeSigTypeForAbi(allocator, table_info, heaps, c);
                allocator.free(arg);
            }
            const full_name = try resolveTypeDefOrRefFullNameAlloc(allocator, table_info, heaps, tdor_idx);
            if (zig_std.mem.eql(u8, full_name, "System.Guid")) {
                allocator.free(full_name);
                break :blk try allocator.dupe(u8, "GUID");
            }
            break :blk full_name;
        },
        0x1d => blk: {
            // SZARRAY
            const elem = try decodeSigTypeForAbi(allocator, table_info, heaps, c);
            defer allocator.free(elem);
            break :blk try zig_std.fmt.allocPrint(allocator, "[*]{s}", .{elem});
        },
        0x1f, 0x20 => blk: {
            // CMOD_REQD / CMOD_OPT
            _ = c.readCompressedUInt();
            break :blk try decodeSigTypeForAbi(allocator, table_info, heaps, c);
        },
        else => try allocator.dupe(u8, "?unknown"),
    };
}

pub fn inspectFunctionAbiByNameAlloc(allocator: zig_std.mem.Allocator, winmd_path: []const u8, method_name: []const u8) ![]u8 {
    var arena = zig_std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const data = try zig_std.fs.cwd().readFileAlloc(a, winmd_path, zig_std.math.maxInt(usize));

    const pe_info = try pe.parse(a, data);
    const md_info = try metadata.parse(a, pe_info);
    const table_stream = if (md_info.getStream("#~")) |s| s else if (md_info.getStream("#-")) |s| s else return error.MissingTableStream;
    const strings_stream = md_info.getStream("#Strings") orelse return error.MissingStringsStream;
    const blob_stream = md_info.getStream("#Blob") orelse return error.MissingBlobStream;

    const table_info = try tables.parse(table_stream.data);
    const heaps = streams.Heaps{ .strings = strings_stream.data, .blob = blob_stream.data, .guid = &.{} };

    // Find the method
    const t = table_info.getTable(.MethodDef);
    var found_row: ?u32 = null;
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const md_row = try table_info.readMethodDef(row);
        const n = try heaps.getString(md_row.name);
        if (zig_std.mem.eql(u8, n, method_name)) {
            found_row = row;
            break;
        }
    }
    const method_row = found_row orelse return error.MethodNotFound;
    const md_row = try table_info.readMethodDef(method_row);

    // Get signature blob
    const sig_blob = try heaps.getBlob(md_row.signature);
    var c = SigCursor{ .data = sig_blob };

    // Read calling convention
    const call_conv = c.readByte() orelse return error.InvalidSignature;
    // Skip GenParamCount for generic methods (calling convention has GENERIC flag 0x10)
    if (call_conv & 0x10 != 0) {
        _ = c.readCompressedUInt(); // generic param count
    }
    // Read param count
    const param_count = c.readCompressedUInt() orelse return error.InvalidSignature;

    // Read return type
    const ret_type = try decodeSigTypeForAbi(a, table_info, heaps, &c);

    // Read param types
    var params = zig_std.ArrayList([]const u8).empty;
    var pi: u32 = 0;
    while (pi < param_count) : (pi += 1) {
        const p_type = try decodeSigTypeForAbi(a, table_info, heaps, &c);
        try params.append(a, p_type);
    }

    // Build output string: fn(p0:type0, p1:type1) -> rettype
    var out = zig_std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const writer = out.writer(allocator);
    try writer.writeAll("fn(");
    for (params.items, 0..) |p, i| {
        if (i > 0) try writer.writeAll(", ");
        try writer.print("p{d}:{s}", .{ i, p });
    }
    try writer.writeAll(") -> ");
    try writer.writeAll(ret_type);

    return try allocator.dupe(u8, out.items);
}

pub fn main() !void {
    const allocator = zig_std.heap.page_allocator;

    const args = try zig_std.process.argsAlloc(allocator);
    defer zig_std.process.argsFree(allocator, args);

    var winmd_path: ?[]const u8 = null;
    var deploy_path: ?[]const u8 = null;
    var no_deps = false;
    var iface_names = zig_std.ArrayList([]const u8).empty;
    defer iface_names.deinit(allocator);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (zig_std.mem.eql(u8, args[i], "--winmd")) {
            if (i + 1 < args.len) { i += 1; winmd_path = args[i]; }
        } else if (zig_std.mem.eql(u8, args[i], "--iface")) {
            if (i + 1 < args.len) { i += 1; try iface_names.append(allocator, args[i]); }
        } else if (zig_std.mem.eql(u8, args[i], "--deploy")) {
            if (i + 1 < args.len) { i += 1; deploy_path = args[i]; }
        } else if (zig_std.mem.eql(u8, args[i], "--no-deps")) {
            no_deps = true;
        }
    }

    if (winmd_path == null or deploy_path == null) {
        zig_std.debug.print("Usage: --winmd <path> --deploy <path> --iface <name>\n", .{});
        return;
    }

    const data = try zig_std.fs.cwd().readFileAlloc(allocator, winmd_path.?, 1024*1024*100);
    defer allocator.free(data);

    const pe_info = try pe.parse(allocator, data);
    const md_info = try metadata.parse(allocator, pe_info);
    const table_stream = if (md_info.getStream("#~")) |s| s else if (md_info.getStream("#-")) |s| s else return error.MissingTableStream;
    const strings_stream = md_info.getStream("#Strings") orelse return error.MissingStringsStream;
    const blob_stream = md_info.getStream("#Blob") orelse return error.MissingBlobStream;
    const guid_stream = md_info.getStream("#GUID") orelse return error.MissingGuidStream;

    const table_info = try tables.parse(table_stream.data);
    const heaps = streams.Heaps{ .strings = strings_stream.data, .blob = blob_stream.data, .guid = guid_stream.data };
    var dependencies = zig_std.StringHashMap(void).init(allocator);
    defer dependencies.deinit();
    const ctx = emit.Context{ .table_info = table_info, .heaps = heaps, .dependencies = &dependencies, .allocator = allocator };
    const rctx = resolver.Context{ .table_info = table_info, .heaps = heaps };

    var generated_types = zig_std.StringHashMap(void).init(allocator);
    defer {
        var it = generated_types.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        generated_types.deinit();
    }
    var to_generate = zig_std.ArrayList([]const u8).empty;
    defer to_generate.deinit(allocator);

    for (iface_names.items) |name| try to_generate.append(allocator, name);

    var out_buf = zig_std.ArrayList(u8).empty;
    defer out_buf.deinit(allocator);
    const writer = out_buf.writer(allocator);

    try emit.writePrologue(writer);

    var head: usize = 0;
    while (head < to_generate.items.len) : (head += 1) {
        const name = to_generate.items[head];
        // Try to find in current WinMD
        const current_ctx = ctx;
        const type_row_opt = if (zig_std.mem.indexOfScalar(u8, name, '.') != null)
            resolver.findTypeDefRowByFullName(rctx, name) catch blk: {
                const dot = zig_std.mem.lastIndexOfScalar(u8, name, '.') orelse name.len - 1;
                break :blk emit.findTypeDefRow(ctx, name[dot+1..]) catch null;
            }
        else
            emit.findTypeDefRow(ctx, name) catch null;

        if (type_row_opt == null) continue;

        const type_row = type_row_opt.?;
        const type_def = try table_info.readTypeDef(type_row);
        const type_name = try heaps.getString(type_def.type_name);
        const type_namespace = try heaps.getString(type_def.type_namespace);
        const canonical_name = if (type_namespace.len == 0)
            try allocator.dupe(u8, type_name)
        else
            try zig_std.fmt.allocPrint(allocator, "{s}.{s}", .{ type_namespace, type_name });
        errdefer allocator.free(canonical_name);

        if (generated_types.contains(canonical_name)) continue;
        try generated_types.put(canonical_name, {});

        const cat = try emit.identifyTypeCategory(current_ctx, type_row);
        switch (cat) {
            .interface => try emit.emitInterface(allocator, writer, current_ctx, winmd_path.?, name),
            .enum_type => try emit.emitEnum(allocator, writer, current_ctx, type_row),
            .struct_type => try emit.emitStruct(allocator, writer, current_ctx, type_row),
            .delegate => try emit.emitDelegate(allocator, writer, current_ctx, type_row),
            .class, .other => {
                // If it's a class with name "Apis" or ends with "Apis", it's likely a Win32 standalone function container
                if (zig_std.mem.endsWith(u8, name, "Apis")) {
                    try emit.emitFunctions(allocator, writer, current_ctx, type_row);
                } else if (cat == .class) {
                    try emit.emitClass(allocator, writer, current_ctx, type_row);
                } else {
                    const resolved = resolver.resolveDefaultInterfaceNameForRuntimeClassAlloc(rctx, allocator, name) catch continue;
                    defer allocator.free(resolved);
                    try emit.emitInterface(allocator, writer, current_ctx, winmd_path.?, resolved);
                }
            },
        }

        // Add newly discovered dependencies to the list (unless --no-deps)
        if (!no_deps) {
            var dit = dependencies.keyIterator();
            while (dit.next()) |d| {
                if (!generated_types.contains(d.*)) {
                    // Check if already in queue
                    var in_queue = false;
                    for (to_generate.items[head+1..]) |q| {
                        if (zig_std.mem.eql(u8, q, d.*)) { in_queue = true; break; }
                    }
                    if (!in_queue) try to_generate.append(allocator, try allocator.dupe(u8, d.*));
                }
            }
        }
    }

    try zig_std.fs.cwd().writeFile(.{ .sub_path = deploy_path.?, .data = out_buf.items });
    zig_std.debug.print("Successfully deployed to {s}\n", .{deploy_path.?});
}

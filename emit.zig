const std = @import("std");
const tables = @import("tables.zig");
const streams = @import("streams.zig");
const coded = @import("coded_index.zig");
const winrt_guid = @import("winrt_guid.zig");

pub const Context = struct {
    table_info: tables.Info,
    heaps: streams.Heaps,
};

const MethodMeta = struct {
    row: u32,
    name: []const u8,
    unique_name: []const u8,
};

pub fn emitInterface(
    allocator: std.mem.Allocator,
    writer: anytype,
    ctx: Context,
    source_path: []const u8,
    interface_name: []const u8,
) !void {
    const type_row = try findTypeDefRow(ctx, interface_name);
    const type_def = try ctx.table_info.readTypeDef(type_row);
    const type_name = try ctx.heaps.getString(type_def.type_name);
    const ns = try ctx.heaps.getString(type_def.type_namespace);
    const is_winrt_iface = !std.mem.startsWith(u8, ns, "Windows.Win32.") and
        !std.mem.startsWith(u8, ns, "Windows.Wdk.");
    const full_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns, type_name });
    defer allocator.free(full_name);

    const guid = try extractGuid(ctx, type_row);

    const method_range = try methodRange(ctx.table_info, type_row);
    var methods: std.ArrayList(MethodMeta) = .empty;
    defer {
        for (methods.items) |m| allocator.free(m.unique_name);
        methods.deinit(allocator);
    }
    var seen_method_names = std.StringHashMap(u32).init(allocator);
    defer seen_method_names.deinit();
    var i = method_range.start;
    while (i < method_range.end_exclusive) : (i += 1) {
        const m = try ctx.table_info.readMethodDef(i);
        const name = try ctx.heaps.getString(m.name);
        const prev = seen_method_names.get(name) orelse 0;
        const next_count = prev + 1;
        try seen_method_names.put(name, next_count);
        const unique_name = if (next_count == 1)
            try allocator.dupe(u8, name)
        else
            try std.fmt.allocPrint(allocator, "{s}_{d}", .{ name, next_count });
        try methods.append(allocator, .{
            .row = i,
            .name = name,
            .unique_name = unique_name,
        });
    }

    try writer.print("// Auto-generated from {s}\n", .{source_path});
    try writer.print("// DO NOT EDIT — regenerate with: winmd2zig {s} {s}\n", .{ source_path, interface_name });
    try writer.print("pub const {s} = extern struct {{\n", .{type_name});
    try writer.print("    // WinMD: {s}\n", .{full_name});
    const blob_hex = try formatGuidBlobHex(allocator, guid);
    defer allocator.free(blob_hex);
    try writer.print("    // Blob: 01 00 {s}\n", .{blob_hex});

    try writer.writeAll("    pub const IID = GUID{ ");
    try writer.print(".Data1 = 0x{x:0>8}, .Data2 = 0x{x:0>4}, .Data3 = 0x{x:0>4},\n", .{
        std.mem.readInt(u32, guid[0..4], .little),
        std.mem.readInt(u16, guid[4..6], .little),
        std.mem.readInt(u16, guid[6..8], .little),
    });
    try writer.writeAll("        .Data4 = .{ ");
    for (guid[8..], 0..) |b, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try writer.print("0x{x:0>2}", .{b});
    }
    try writer.writeAll(" } };\n\n");

    try writer.writeAll("    lpVtbl: *const VTable,\n\n");
    try writer.writeAll("    const VTable = extern struct {\n");
    try writer.writeAll("        // IUnknown (slots 0-2)\n");
    try writer.writeAll("        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,\n");
    try writer.writeAll("        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,\n");
    try writer.writeAll("        Release: *const fn (*anyopaque) callconv(.winapi) u32,\n");
    if (is_winrt_iface) {
        try writer.writeAll("        // IInspectable (slots 3-5)\n");
        try writer.writeAll("        GetIids: VtblPlaceholder,\n");
        try writer.writeAll("        GetRuntimeClassName: VtblPlaceholder,\n");
        try writer.writeAll("        GetTrustLevel: VtblPlaceholder,\n");
    }

    const start_slot: u32 = if (is_winrt_iface) 6 else 3;
    const end_slot: u32 = start_slot + @as(u32, @intCast(methods.items.len)) - 1;
    if (methods.items.len > 0) {
        try writer.print("        // {s} (slots {d}-{d})\n", .{ type_name, start_slot, end_slot });
        for (methods.items, 0..) |m, idx| {
            if (try buildMethodFnType(allocator, ctx, m.row, is_winrt_iface)) |fn_type| {
                defer allocator.free(fn_type);
                try writer.print("        {s}: {s}, // {d}\n", .{
                    m.unique_name,
                    fn_type,
                    start_slot + @as(u32, @intCast(idx)),
                });
            } else {
                try writer.print("        {s}: VtblPlaceholder, // {d}\n", .{
                    m.unique_name,
                    start_slot + @as(u32, @intCast(idx)),
                });
            }
        }
    } else if (is_winrt_iface) {
        try writer.print("        // {s} (slots 6-5)\n", .{type_name});
    } else {
        try writer.print("        // {s} (slots 3-2)\n", .{type_name});
    }
    try writer.writeAll("    };\n\n");
    try writer.print("    pub fn release(self: *{s}) void {{\n", .{type_name});
    try writer.writeAll("        _ = self.lpVtbl.Release(@ptrCast(self));\n");
    try writer.writeAll("    }\n");
    try writer.writeAll("};\n");
}

fn findTypeDefRow(ctx: Context, interface_name: []const u8) !u32 {
    const dot_index = std.mem.lastIndexOfScalar(u8, interface_name, '.');
    const want_ns = if (dot_index) |i| interface_name[0..i] else null;
    const want_name = if (dot_index) |i| interface_name[i + 1 ..] else interface_name;

    const t = ctx.table_info.getTable(.TypeDef);
    var fallback_row: ?u32 = null;
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const td = try ctx.table_info.readTypeDef(row);
        const name = try ctx.heaps.getString(td.type_name);
        if (!std.mem.eql(u8, name, want_name)) continue;
        if (want_ns) |ns| {
            const actual_ns = try ctx.heaps.getString(td.type_namespace);
            if (!std.mem.eql(u8, actual_ns, ns)) continue;
        }
        if (want_ns != null) return row;
        if (fallback_row == null) fallback_row = row;
        if (try hasGuidAttribute(ctx, row)) return row;
    }
    if (fallback_row) |r| return r;
    return error.InterfaceNotFound;
}

const MethodRange = struct {
    start: u32,
    end_exclusive: u32,
};

fn methodRange(info: tables.Info, type_row: u32) !MethodRange {
    const td = try info.readTypeDef(type_row);
    const method_table = info.getTable(.MethodDef);
    const start = td.method_list;
    const type_table = info.getTable(.TypeDef);
    const end_exclusive: u32 = if (type_row < type_table.row_count)
        (try info.readTypeDef(type_row + 1)).method_list
    else
        method_table.row_count + 1;
    return .{ .start = start, .end_exclusive = end_exclusive };
}

fn extractGuid(ctx: Context, type_row: u32) ![16]u8 {
    const ca_table = ctx.table_info.getTable(.CustomAttribute);
    var row: u32 = 1;
    while (row <= ca_table.row_count) : (row += 1) {
        const ca = try ctx.table_info.readCustomAttribute(row);
        const parent = try coded.decodeHasCustomAttribute(ca.parent);
        if (parent.table != .TypeDef or parent.row != type_row) continue;

        const ca_type = try coded.decodeCustomAttributeType(ca.ca_type);
        if (ca_type.table != .MemberRef) continue;
        const mr = try ctx.table_info.readMemberRef(ca_type.row);
        const member_name = try ctx.heaps.getString(mr.name);
        if (!std.mem.eql(u8, member_name, ".ctor")) continue;

        const class_decoded = decodeMemberRefParent(mr.class) catch continue;
        if (class_decoded.table != .TypeRef) continue;
        const tref = try ctx.table_info.readTypeRef(class_decoded.row);
        const tref_name = try ctx.heaps.getString(tref.type_name);
        if (!std.mem.eql(u8, tref_name, "GuidAttribute")) continue;

        const blob = try ctx.heaps.getBlob(ca.value);
        return try parseGuidAttributeValue(blob);
    }
    return error.MissingGuidAttribute;
}

fn decodeMemberRefParent(raw: u32) coded.IndexError!coded.Decoded {
    const tag = raw & 0x7;
    const row = raw >> 3;
    return switch (tag) {
        0 => .{ .table = .TypeDef, .row = row },
        1 => .{ .table = .TypeRef, .row = row },
        2 => .{ .table = .ModuleRef, .row = row },
        3 => .{ .table = .MethodDef, .row = row },
        4 => .{ .table = .TypeSpec, .row = row },
        else => error.InvalidTag,
    };
}

fn formatGuidBlobHex(allocator: std.mem.Allocator, guid: [16]u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    for (guid, 0..) |b, idx| {
        if (idx != 0) try out.append(allocator, ' ');
        try out.writer(allocator).print("{x:0>2}", .{b});
    }
    return try out.toOwnedSlice(allocator);
}

fn parseGuidAttributeValue(blob: []const u8) ![16]u8 {
    if (blob.len < 2 or blob[0] != 0x01 or blob[1] != 0x00) return error.InvalidGuidBlob;
    if (blob.len >= 18) return blob[2..18].*;

    const payload = blob[2..];
    if (payload.len == 0 or payload[0] == 0xFF) return error.InvalidGuidBlob;
    const len_info = streams.decodeCompressedUInt(payload) catch return error.InvalidGuidBlob;
    const start = len_info.used;
    const end = start + len_info.value;
    if (end > payload.len) return error.InvalidGuidBlob;
    const g = winrt_guid.parseGuidText(payload[start..end]) catch return error.InvalidGuidBlob;
    return g.toBlob();
}

fn buildMethodFnType(allocator: std.mem.Allocator, ctx: Context, method_row: u32, is_winrt_iface: bool) !?[]u8 {
    const m = try ctx.table_info.readMethodDef(method_row);
    const sig_blob = try ctx.heaps.getBlob(m.signature);
    if (sig_blob.len == 0) return null;

    var c = SigCursor{ .data = sig_blob };
    const sig_cc = c.readByte() orelse return null;
    if ((sig_cc & 0x0f) != 0x00 and (sig_cc & 0x0f) != 0x05) return null;
    if ((sig_cc & 0x10) != 0) {
        _ = c.readCompressedUInt() orelse return null;
    }

    const param_count = c.readCompressedUInt() orelse return null;
    const ret_ty = try decodeSigType(allocator, ctx, &c, is_winrt_iface) orelse return null;
    defer allocator.free(ret_ty);

    var param_tys: std.ArrayList([]const u8) = .empty;
    defer {
        for (param_tys.items) |p| allocator.free(p);
        param_tys.deinit(allocator);
    }

    var n: usize = 0;
    while (n < param_count) : (n += 1) {
        const p = try decodeSigType(allocator, ctx, &c, is_winrt_iface) orelse return null;
        try param_tys.append(allocator, p);
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    const w = out.writer(allocator);
    try w.writeAll("*const fn (*anyopaque");
    for (param_tys.items) |p| {
        if (std.mem.eql(u8, p, "com_array") or std.mem.eql(u8, p, "*com_array")) {
            try w.writeAll(", *u32, *?*anyopaque");
        } else {
            try w.print(", {s}", .{p});
        }
    }
    if (is_winrt_iface and std.mem.eql(u8, ret_ty, "com_array")) {
        try w.writeAll(", *u32, *?*anyopaque");
    } else if (is_winrt_iface and !std.mem.eql(u8, ret_ty, "void")) {
        try w.print(", *{s}", .{ret_ty});
    }
    if (is_winrt_iface) {
        try w.writeAll(") callconv(.winapi) HRESULT");
    } else {
        const ret_out = if (std.mem.eql(u8, ret_ty, "i32")) "HRESULT" else ret_ty;
        try w.print(") callconv(.winapi) {s}", .{ret_out});
    }
    return try out.toOwnedSlice(allocator);
}

const SigCursor = struct {
    data: []const u8,
    pos: usize = 0,

    fn readByte(self: *SigCursor) ?u8 {
        if (self.pos >= self.data.len) return null;
        const b = self.data[self.pos];
        self.pos += 1;
        return b;
    }

    fn readCompressedUInt(self: *SigCursor) ?usize {
        if (self.pos >= self.data.len) return null;
        const info = streams.decodeCompressedUInt(self.data[self.pos..]) catch return null;
        self.pos += info.used;
        return info.value;
    }
};

fn decodeSigType(allocator: std.mem.Allocator, ctx: Context, c: *SigCursor, is_winrt_iface: bool) !?[]u8 {
    const et = c.readByte() orelse return null;
    return switch (et) {
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
        0x18 => try allocator.dupe(u8, "isize"),
        0x19 => try allocator.dupe(u8, "usize"),
        0x1c => try allocator.dupe(u8, "?*anyopaque"),
        0x0e => try allocator.dupe(u8, "?HSTRING"),
        0x0f => blk: {
            const inner = try decodeSigType(allocator, ctx, c, is_winrt_iface) orelse break :blk null;
            defer allocator.free(inner);
            break :blk try std.fmt.allocPrint(allocator, "*{s}", .{inner});
        },
        0x10 => blk: {
            const inner = try decodeSigType(allocator, ctx, c, is_winrt_iface) orelse break :blk null;
            defer allocator.free(inner);
            break :blk try std.fmt.allocPrint(allocator, "*{s}", .{inner});
        },
        0x1f, 0x20 => blk: {
            // cmod_reqd / cmod_opt: consume TypeDefOrRef then actual type.
            _ = c.readCompressedUInt() orelse break :blk null;
            break :blk try decodeSigType(allocator, ctx, c, is_winrt_iface);
        },
        0x11, 0x12 => blk: {
            const coded_idx = c.readCompressedUInt() orelse break :blk null;
            const tdor = coded.decodeTypeDefOrRef(@intCast(coded_idx)) catch break :blk null;
            const full = try resolveTypeDefOrRefName(allocator, ctx, tdor) orelse break :blk null;
            defer allocator.free(full);
            if (std.mem.eql(u8, full, "Windows.Foundation.Guid") or std.mem.eql(u8, full, "System.Guid")) {
                break :blk try allocator.dupe(u8, "GUID");
            }
            if (std.mem.eql(u8, full, "Windows.Win32.Foundation.HRESULT")) {
                break :blk try allocator.dupe(u8, "HRESULT");
            }
            if (std.mem.eql(u8, full, "Windows.Foundation.EventRegistrationToken")) {
                break :blk try allocator.dupe(u8, "EventRegistrationToken");
            }
            if (std.mem.eql(u8, full, "System.IntPtr")) {
                break :blk try allocator.dupe(u8, "isize");
            }
            if (std.mem.eql(u8, full, "System.UIntPtr")) {
                break :blk try allocator.dupe(u8, "usize");
            }
            if (!is_winrt_iface and std.mem.startsWith(u8, full, "Windows.Win32.Foundation.P")) {
                break :blk try allocator.dupe(u8, "?*anyopaque");
            }
            break :blk try allocator.dupe(u8, "?*anyopaque");
        },
        0x1d => blk: {
            const inner = try decodeSigType(allocator, ctx, c, is_winrt_iface) orelse break :blk null;
            defer allocator.free(inner);
            if (is_winrt_iface) break :blk try allocator.dupe(u8, "com_array");
            break :blk try allocator.dupe(u8, "?*anyopaque");
        },
        0x13, 0x1e => blk: {
            // VAR / MVAR
            _ = c.readCompressedUInt() orelse break :blk null;
            break :blk try allocator.dupe(u8, "?*anyopaque");
        },
        0x14 => blk: {
            // ARRAY: <type> <rank> <numsizes> size* <numlbounds> lbound*
            const inner = try decodeSigType(allocator, ctx, c, is_winrt_iface) orelse break :blk null;
            defer allocator.free(inner);
            const rank = c.readCompressedUInt() orelse break :blk null;
            const num_sizes = c.readCompressedUInt() orelse break :blk null;
            var i: usize = 0;
            while (i < num_sizes) : (i += 1) _ = c.readCompressedUInt() orelse break :blk null;
            const num_lbounds = c.readCompressedUInt() orelse break :blk null;
            i = 0;
            while (i < num_lbounds) : (i += 1) _ = c.readCompressedUInt() orelse break :blk null;
            _ = rank;
            break :blk try allocator.dupe(u8, "?*anyopaque");
        },
        0x15 => blk: {
            // GENERICINST: CLASS|VALUETYPE, TypeDefOrRef, GenArgCount, GenArg*
            _ = c.readByte() orelse break :blk null;
            _ = c.readCompressedUInt() orelse break :blk null;
            const argc = c.readCompressedUInt() orelse break :blk null;
            var i: usize = 0;
            while (i < argc) : (i += 1) {
                const arg = try decodeSigType(allocator, ctx, c, is_winrt_iface) orelse break :blk null;
                defer allocator.free(arg);
            }
            break :blk try allocator.dupe(u8, "?*anyopaque");
        },
        0x1b => try allocator.dupe(u8, "?*anyopaque"), // FNPTR
        0x41 => try decodeSigType(allocator, ctx, c, is_winrt_iface), // SENTINEL
        0x45 => blk: {
            // PINNED
            break :blk try decodeSigType(allocator, ctx, c, is_winrt_iface);
        },
        else => null,
    };
}


fn resolveTypeDefOrRefName(
    allocator: std.mem.Allocator,
    ctx: Context,
    tdor: coded.Decoded,
) !?[]u8 {
    return switch (tdor.table) {
        .TypeDef => blk: {
            const td = try ctx.table_info.readTypeDef(tdor.row);
            const ns = try ctx.heaps.getString(td.type_namespace);
            const name = try ctx.heaps.getString(td.type_name);
            break :blk try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns, name });
        },
        .TypeRef => blk: {
            const tr = try ctx.table_info.readTypeRef(tdor.row);
            const ns = try ctx.heaps.getString(tr.type_namespace);
            const name = try ctx.heaps.getString(tr.type_name);
            break :blk try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns, name });
        },
        else => null,
    };
}

fn hasGuidAttribute(ctx: Context, type_row: u32) !bool {
    const ca_table = ctx.table_info.getTable(.CustomAttribute);
    var row: u32 = 1;
    while (row <= ca_table.row_count) : (row += 1) {
        const ca = try ctx.table_info.readCustomAttribute(row);
        const parent = try coded.decodeHasCustomAttribute(ca.parent);
        if (parent.table != .TypeDef or parent.row != type_row) continue;

        const ca_type = try coded.decodeCustomAttributeType(ca.ca_type);
        if (ca_type.table != .MemberRef) continue;
        const mr = try ctx.table_info.readMemberRef(ca_type.row);
        const member_name = try ctx.heaps.getString(mr.name);
        if (!std.mem.eql(u8, member_name, ".ctor")) continue;

        const class_decoded = decodeMemberRefParent(mr.class) catch continue;
        if (class_decoded.table != .TypeRef) continue;
        const tr = try ctx.table_info.readTypeRef(class_decoded.row);
        const tr_name = try ctx.heaps.getString(tr.type_name);
        if (!std.mem.eql(u8, tr_name, "GuidAttribute")) continue;
        return true;
    }
    return false;
}

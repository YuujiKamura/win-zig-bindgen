const std = @import("std");
const win_zig_metadata = @import("win_zig_metadata");
const tables = win_zig_metadata.tables;
const streams = win_zig_metadata.streams;
const coded = win_zig_metadata.coded_index;
const context = @import("context.zig");
const type_predicates = @import("type_predicates.zig");
const metadata_nav = @import("metadata_nav.zig");
const sig_decode = @import("sig_decode.zig");

const Context = context.Context;
const MethodMeta = context.MethodMeta;
const MethodRange = context.MethodRange;
const SigCursor = sig_decode.SigCursor;

pub fn registerAssociatedEnumDependencies(allocator: std.mem.Allocator, ctx: Context, method_row: u32) !void {
    if (ctx.dependencies == null) return;
    const range = try metadata_nav.paramRange(ctx.table_info, method_row);
    const ca_table = ctx.table_info.getTable(.CustomAttribute);
    var ca_row: u32 = 1;
    while (ca_row <= ca_table.row_count) : (ca_row += 1) {
        const ca = try ctx.table_info.readCustomAttribute(ca_row);
        const parent = coded.decodeHasCustomAttribute(ca.parent) catch continue;
        if (parent.table != .Param or parent.row < range.start or parent.row >= range.end_exclusive) continue;
        const attr_name = try sig_decode.customAttributeTypeName(ctx, ca.ca_type) orelse continue;
        if (!std.mem.eql(u8, attr_name, "AssociatedEnumAttribute")) continue;
        const blob = try ctx.heaps.getBlob(ca.value);
        const enum_name = sig_decode.decodeCustomAttributeString(blob) orelse continue;
        try ctx.registerDependency(allocator, enum_name);
    }
}

/// Collect parent interface method names for COM interfaces by walking the extends chain.
/// Stops at IUnknown/IInspectable (already hardcoded in vtable).
/// Returns method names in vtable order (grandparent first, then parent, etc.).
pub fn collectParentMethods(allocator: std.mem.Allocator, ctx: Context, type_row: u32) !std.ArrayList(MethodMeta) {
    var parent_chain = std.ArrayList(u32).empty;
    defer parent_chain.deinit(allocator);

    // Walk extends chain to collect parent TypeDef rows (excluding IUnknown/IInspectable)
    var cur_row = type_row;
    while (true) {
        const td = try ctx.table_info.readTypeDef(cur_row);
        if (td.extends == 0) break;
        const extends_tdor = coded.decodeTypeDefOrRef(td.extends) catch break;
        const parent_name = sig_decode.resolveTypeDefOrRefNameRaw(ctx, extends_tdor) catch break;
        if (parent_name == null) break;
        // Stop at IUnknown/IInspectable — these are already in the hardcoded vtable base
        if (std.mem.eql(u8, parent_name.?, "IUnknown") or std.mem.eql(u8, parent_name.?, "IInspectable")) break;
        if (try sig_decode.resolveTypeDefOrRefFullNameAlloc(allocator, ctx, extends_tdor)) |parent_full| {
            defer allocator.free(parent_full);
            try ctx.registerDependency(allocator, parent_full);
        } else {
            try ctx.registerDependency(allocator, parent_name.?);
        }
        const parent_row = sig_decode.resolveTypeDefOrRefToRow(ctx, extends_tdor) catch break;
        if (parent_row == null) break;
        try parent_chain.append(allocator, parent_row.?);
        cur_row = parent_row.?;
    }

    // Reverse so grandparent methods come first
    std.mem.reverse(u32, parent_chain.items);

    var result = std.ArrayList(MethodMeta).empty;
    for (parent_chain.items) |parent_row| {
        const range = try metadata_nav.methodRange(ctx.table_info, parent_row);
        var mi = range.start;
        while (mi < range.end_exclusive) : (mi += 1) {
            const m = try ctx.table_info.readMethodDef(mi);
            const name = try ctx.heaps.getString(m.name);
            // Build a simple VtblPlaceholder entry for inherited methods
            try result.append(allocator, .{
                .raw_name = try allocator.dupe(u8, name),
                .norm_name = try allocator.dupe(u8, name),
                .vtbl_sig = try allocator.dupe(u8, "VtblPlaceholder"),
                .wrapper_sig = try allocator.dupe(u8, ""),
                .wrapper_call = try allocator.dupe(u8, ""),
                .raw_wrapper_sig = try allocator.dupe(u8, ""),
                .raw_wrapper_call = try allocator.dupe(u8, ""),
            });
        }
    }
    return result;
}

/// Collect required interface names from the InterfaceImpl table (for WinRT interfaces).
pub fn collectRequiredInterfaces(allocator: std.mem.Allocator, ctx: Context, type_row: u32) !std.ArrayList([]const u8) {
    var result = std.ArrayList([]const u8).empty;
    const t = ctx.table_info.getTable(.InterfaceImpl);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const impl = ctx.table_info.readInterfaceImpl(row) catch continue;
        if (impl.class != type_row) continue;
        const iface_tdor = coded.decodeTypeDefOrRef(impl.interface) catch continue;
        if (iface_tdor.table == .TypeSpec) {
            const ts = ctx.table_info.readTypeSpec(iface_tdor.row) catch continue;
            const sig = try ctx.heaps.getBlob(ts.signature);
            var sig_c = SigCursor{ .data = sig };
            const parsed = try sig_decode.decodeSigType(allocator, ctx, &sig_c, true);
            if (parsed) |p| allocator.free(p);
        }
        const iface_name = sig_decode.resolveTypeDefOrRefNameRaw(ctx, iface_tdor) catch continue;
        if (iface_name) |n| {
            // Skip generic types (e.g., "IIterable`1") — they can't be emitted as concrete types
            if (std.mem.indexOfScalar(u8, n, '`') != null) continue;
            if (try sig_decode.resolveTypeDefOrRefFullNameAlloc(allocator, ctx, iface_tdor)) |iface_full| {
                defer allocator.free(iface_full);
                try ctx.registerDependency(allocator, iface_full);
            } else {
                try ctx.registerDependency(allocator, n);
            }
            try result.append(allocator, try allocator.dupe(u8, n));
        }
    }
    return result;
}

pub fn appendUniqueShortName(
    allocator: std.mem.Allocator,
    list: *std.ArrayList([]const u8),
    name: []const u8,
) !void {
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse 0;
    const short_raw = if (dot > 0) name[dot + 1 ..] else name;
    // Strip backtick arity suffix (e.g., "IVector`1" -> "IVector") and trim whitespace/null
    const backtick = std.mem.indexOfScalar(u8, short_raw, '`');
    const short_bt = if (backtick) |bt| short_raw[0..bt] else short_raw;
    const short = std.mem.trim(u8, short_bt, " \t\r\n\x00");
    if (short.len == 0) return;
    for (list.items) |existing| {
        if (std.mem.eql(u8, existing, short)) return;
    }
    try list.append(allocator, try allocator.dupe(u8, short));
}

pub fn normalizeWinRtMethodName(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    if (std.mem.startsWith(u8, name, "get_")) {
        return allocator.dupe(u8, name["get_".len..]);
    }
    if (std.mem.startsWith(u8, name, "put_")) {
        return std.fmt.allocPrint(allocator, "Set{s}", .{name["put_".len..]});
    }
    if (std.mem.startsWith(u8, name, "add_")) {
        return std.fmt.allocPrint(allocator, "Add{s}", .{name["add_".len..]});
    }
    if (std.mem.startsWith(u8, name, "remove_")) {
        return std.fmt.allocPrint(allocator, "Remove{s}", .{name["remove_".len..]});
    }
    return allocator.dupe(u8, name);
}

pub fn collectInterfaceMethodsByName(
    allocator: std.mem.Allocator,
    ctx: Context,
    iface_name: []const u8,
) !std.ArrayList(MethodMeta) {
    var result = std.ArrayList(MethodMeta).empty;
    const iface_row = metadata_nav.findTypeDefRow(ctx, iface_name) catch return result;
    const range = try metadata_nav.methodRange(ctx.table_info, iface_row);
    var mi = range.start;
    while (mi < range.end_exclusive) : (mi += 1) {
        const m = try ctx.table_info.readMethodDef(mi);
        const name = try ctx.heaps.getString(m.name);

        // Decode signature to trigger registerDependency for types used in this method
        const sig_blob = try ctx.heaps.getBlob(m.signature);
        var sig_c = SigCursor{ .data = sig_blob };
        _ = sig_c.readByte();
        const param_count = sig_c.readCompressedUInt() orelse 0;
        if (sig_decode.decodeSigType(allocator, ctx, &sig_c, true) catch null) |ret_type| {
            allocator.free(ret_type);
        }
        var p_idx: u32 = 0;
        while (p_idx < param_count) : (p_idx += 1) {
            _ = (sig_c.pos < sig_c.data.len and sig_c.data[sig_c.pos] == 0x10);
            if (sig_decode.decodeSigType(allocator, ctx, &sig_c, true) catch null) |p_type| {
                allocator.free(p_type);
            }
        }

        try result.append(allocator, .{
            .raw_name = try allocator.dupe(u8, name),
            .norm_name = try normalizeWinRtMethodName(allocator, name),
            .vtbl_sig = try allocator.dupe(u8, "VtblPlaceholder"),
            .wrapper_sig = try allocator.dupe(u8, ""),
            .wrapper_call = try allocator.dupe(u8, ""),
            .raw_wrapper_sig = try allocator.dupe(u8, ""),
            .raw_wrapper_call = try allocator.dupe(u8, ""),
        });
    }
    return result;
}

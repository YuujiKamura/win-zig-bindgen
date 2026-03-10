const std = @import("std");
const win_zig_metadata = @import("win_zig_metadata");
const tables = win_zig_metadata.tables;
const streams = win_zig_metadata.streams;
const coded = win_zig_metadata.coded_index;
const ui = @import("unified_index.zig");
const context = @import("context.zig");
const type_predicates = @import("type_predicates.zig");
const metadata_nav = @import("metadata_nav.zig");
const sig_decode = @import("sig_decode.zig");

const Context = ui.UnifiedContext;
const TypeLocation = ui.TypeLocation;
const FileEntry = ui.FileEntry;
const MethodMeta = context.MethodMeta;
const MethodRange = context.MethodRange;
const SigCursor = sig_decode.SigCursor;

pub fn registerAssociatedEnumDependencies(allocator: std.mem.Allocator, ctx: Context, method_row: u32) !void {
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
    const ParentEntry = struct {
        loc: TypeLocation,
    };
    var parent_chain = std.ArrayList(ParentEntry).empty;
    defer parent_chain.deinit(allocator);

    // Walk extends chain to collect parent TypeLocations (excluding IUnknown/IInspectable)
    // Start from the current file + type_row
    var cur_table_info = ctx.table_info;
    var cur_heaps = ctx.heaps;
    var cur_file = ctx.file();
    var cur_row = type_row;

    while (true) {
        const td = try cur_table_info.readTypeDef(cur_row);
        if (td.extends == 0) break;
        const extends_tdor = coded.decodeTypeDefOrRef(td.extends) catch break;

        // Resolve name from the current file's heaps (TypeRef name is in the referencing file)
        const parent_name = resolveNameRaw(cur_table_info, cur_heaps, extends_tdor) catch break;
        if (parent_name == null) break;

        // Stop at IUnknown/IInspectable — these are already in the hardcoded vtable base
        if (std.mem.eql(u8, parent_name.?, "IUnknown") or std.mem.eql(u8, parent_name.?, "IInspectable")) break;

        // Register dependency using full name
        if (resolveFullNameAlloc(allocator, cur_table_info, cur_heaps, extends_tdor) catch null) |parent_full| {
            defer allocator.free(parent_full);
            try ctx.registerDependency(allocator, parent_full);
        } else {
            try ctx.registerDependency(allocator, parent_name.?);
        }

        // Resolve to a TypeLocation via unified index (handles cross-file references)
        const parent_loc = ctx.index.resolveTypeDefOrRef(cur_file, extends_tdor) orelse break;
        try parent_chain.append(allocator, .{ .loc = parent_loc });

        // Advance to the parent's file for the next iteration
        const parent_file = ctx.index.fileOf(parent_loc);
        cur_table_info = parent_file.table_info;
        cur_heaps = parent_file.heaps;
        cur_file = parent_file;
        cur_row = parent_loc.row;
    }

    // Reverse so grandparent methods come first
    std.mem.reverse(ParentEntry, parent_chain.items);

    var result = std.ArrayList(MethodMeta).empty;
    for (parent_chain.items) |entry| {
        const pfile = ctx.index.fileOf(entry.loc);
        const range = try metadata_nav.methodRange(pfile.table_info, entry.loc.row);
        var mi = range.start;
        while (mi < range.end_exclusive) : (mi += 1) {
            const m = try pfile.table_info.readMethodDef(mi);
            const name = try pfile.heaps.getString(m.name);
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

        // Resolve name from current file's tables
        const iface_name = resolveNameRaw(ctx.table_info, ctx.heaps, iface_tdor) catch continue;
        if (iface_name) |n| {
            // Strip backtick arity suffix (e.g., "IIterable`1" → "IIterable")
            const backtick = std.mem.indexOfScalar(u8, n, '`');
            const clean_name = if (backtick) |bt| n[0..bt] else n;

            // Register dependency using full name
            if (resolveFullNameAlloc(allocator, ctx.table_info, ctx.heaps, iface_tdor) catch null) |iface_full| {
                defer allocator.free(iface_full);
                // Register tick-trimmed full name
                const full_bt = std.mem.indexOfScalar(u8, iface_full, '`');
                if (full_bt) |bt| {
                    const trimmed = try std.fmt.allocPrint(allocator, "{s}", .{iface_full[0..bt]});
                    defer allocator.free(trimmed);
                    try ctx.registerDependency(allocator, trimmed);
                } else {
                    try ctx.registerDependency(allocator, iface_full);
                }
            } else {
                try ctx.registerDependency(allocator, clean_name);
            }
            try result.append(allocator, try allocator.dupe(u8, clean_name));
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

    // Resolve the interface type via the unified index (cross-file capable)
    const loc = ctx.index.findByShortName(iface_name) orelse
        ctx.index.findByFullName(iface_name) orelse
        return result;

    const iface_file = ctx.index.fileOf(loc);
    // Build a context for the interface's file so sig_decode resolves types correctly
    const iface_ctx = Context.make(ctx.index, loc, ctx.dep_queue, allocator);
    const range = try metadata_nav.methodRange(iface_file.table_info, loc.row);
    var mi = range.start;
    while (mi < range.end_exclusive) : (mi += 1) {
        const m = try iface_file.table_info.readMethodDef(mi);
        const name = try iface_file.heaps.getString(m.name);

        // Decode signature to trigger registerDependency for types used in this method
        const sig_blob = try iface_file.heaps.getBlob(m.signature);
        var sig_c = SigCursor{ .data = sig_blob };
        _ = sig_c.readByte();
        const param_count = sig_c.readCompressedUInt() orelse 0;
        if (sig_decode.decodeSigType(allocator, iface_ctx, &sig_c, true) catch null) |ret_type| {
            allocator.free(ret_type);
        }
        var p_idx: u32 = 0;
        while (p_idx < param_count) : (p_idx += 1) {
            _ = (sig_c.pos < sig_c.data.len and sig_c.data[sig_c.pos] == 0x10);
            if (sig_decode.decodeSigType(allocator, iface_ctx, &sig_c, true) catch null) |p_type| {
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

// ---------------------------------------------------------------------------
// Local helpers: resolve names from table_info + heaps directly
// (avoids depending on sig_decode for simple name resolution, which would
//  create a circular dependency when sig_decode is also being rewritten)
// ---------------------------------------------------------------------------

/// Resolve a TypeDefOrRef coded index to a short type name using the given table/heaps.
fn resolveNameRaw(table_info: tables.Info, heaps: streams.Heaps, tdor: coded.Decoded) !?[]const u8 {
    return switch (tdor.table) {
        .TypeDef => blk: {
            const td = try table_info.readTypeDef(tdor.row);
            break :blk try heaps.getString(td.type_name);
        },
        .TypeRef => blk: {
            const tr = try table_info.readTypeRef(tdor.row);
            break :blk try heaps.getString(tr.type_name);
        },
        .TypeSpec => null, // TypeSpec name resolution requires blob parsing; skip for now
        else => null,
    };
}

/// Resolve a TypeDefOrRef coded index to a fully-qualified "Namespace.TypeName" string.
fn resolveFullNameAlloc(allocator: std.mem.Allocator, table_info: tables.Info, heaps: streams.Heaps, tdor: coded.Decoded) !?[]const u8 {
    return switch (tdor.table) {
        .TypeDef => blk: {
            const td = try table_info.readTypeDef(tdor.row);
            const ns = try heaps.getString(td.type_namespace);
            const name = try heaps.getString(td.type_name);
            if (ns.len == 0) break :blk try allocator.dupe(u8, name);
            break :blk try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns, name });
        },
        .TypeRef => blk: {
            const tr = try table_info.readTypeRef(tdor.row);
            const ns = try heaps.getString(tr.type_namespace);
            const name = try heaps.getString(tr.type_name);
            if (ns.len == 0) break :blk try allocator.dupe(u8, name);
            break :blk try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns, name });
        },
        .TypeSpec => null,
        else => null,
    };
}

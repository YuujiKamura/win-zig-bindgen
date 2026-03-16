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
        const parent_ctx = Context.make(ctx.index, entry.loc, ctx.dep_queue, allocator);
        const range = try metadata_nav.methodRange(pfile.table_info, entry.loc.row);
        var mi = range.start;
        while (mi < range.end_exclusive) : (mi += 1) {
            const m = try pfile.table_info.readMethodDef(mi);
            const name = try pfile.heaps.getString(m.name);
            const vtbl_sig = buildMethodVtblSig(allocator, parent_ctx, pfile, m) catch
                try allocator.dupe(u8, "VtblPlaceholder");
            try result.append(allocator, .{
                .raw_name = try allocator.dupe(u8, name),
                .norm_name = try allocator.dupe(u8, name),
                .vtbl_sig = vtbl_sig,
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

        const vtbl_sig = buildMethodVtblSig(allocator, iface_ctx, iface_file, m) catch
            try allocator.dupe(u8, "VtblPlaceholder");

        try result.append(allocator, .{
            .raw_name = try allocator.dupe(u8, name),
            .norm_name = try normalizeWinRtMethodName(allocator, name),
            .vtbl_sig = vtbl_sig,
            .wrapper_sig = try allocator.dupe(u8, ""),
            .wrapper_call = try allocator.dupe(u8, ""),
            .raw_wrapper_sig = try allocator.dupe(u8, ""),
            .raw_wrapper_call = try allocator.dupe(u8, ""),
        });
    }
    return result;
}

/// Collect all ancestor methods for a Win32 COM interface by recursively walking
/// the InterfaceImpl chain. Returns methods in vtable order: grandparent first,
/// then parent, then direct parent — excluding IUnknown (already hardcoded).
pub fn collectWin32ComParentMethods(
    allocator: std.mem.Allocator,
    ctx: Context,
    type_row: u32,
) !std.ArrayList(MethodMeta) {
    // First, find the direct parent interface(s) from the InterfaceImpl table
    var parent_names = std.ArrayList([]const u8).empty;
    defer {
        for (parent_names.items) |n| allocator.free(n);
        parent_names.deinit(allocator);
    }

    const t = ctx.table_info.getTable(.InterfaceImpl);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const impl = ctx.table_info.readInterfaceImpl(row) catch continue;
        if (impl.class != type_row) continue;
        const iface_tdor = coded.decodeTypeDefOrRef(impl.interface) catch continue;
        const iface_name = resolveNameRaw(ctx.table_info, ctx.heaps, iface_tdor) catch continue;
        if (iface_name) |n| {
            // Skip IUnknown/IInspectable — already hardcoded in vtable base
            if (std.mem.eql(u8, n, "IUnknown") or std.mem.eql(u8, n, "IInspectable")) continue;
            const backtick = std.mem.indexOfScalar(u8, n, '`');
            const clean_name = if (backtick) |bt| n[0..bt] else n;
            try parent_names.append(allocator, try allocator.dupe(u8, clean_name));
        }
    }

    var result = std.ArrayList(MethodMeta).empty;

    // For each parent interface, recursively collect ITS parents first, then its own methods
    for (parent_names.items) |parent_name| {
        const loc = ctx.index.findByShortName(parent_name) orelse
            ctx.index.findByFullName(parent_name) orelse
            continue;

        const parent_file = ctx.index.fileOf(loc);
        const parent_ctx = Context.make(ctx.index, loc, ctx.dep_queue, allocator);

        // Recurse: collect grandparent methods first
        var ancestor_methods = try collectWin32ComParentMethods(allocator, parent_ctx, loc.row);
        defer ancestor_methods.deinit(allocator);
        for (ancestor_methods.items) |m| {
            try result.append(allocator, .{
                .raw_name = try allocator.dupe(u8, m.raw_name),
                .norm_name = try allocator.dupe(u8, m.norm_name),
                .vtbl_sig = try allocator.dupe(u8, m.vtbl_sig),
                .wrapper_sig = try allocator.dupe(u8, m.wrapper_sig),
                .wrapper_call = try allocator.dupe(u8, m.wrapper_call),
                .raw_wrapper_sig = try allocator.dupe(u8, m.raw_wrapper_sig),
                .raw_wrapper_call = try allocator.dupe(u8, m.raw_wrapper_call),
            });
        }
        // Free ancestor method strings
        for (ancestor_methods.items) |m| {
            allocator.free(m.raw_name);
            allocator.free(m.norm_name);
            allocator.free(m.vtbl_sig);
            allocator.free(m.wrapper_sig);
            allocator.free(m.wrapper_call);
            allocator.free(m.raw_wrapper_sig);
            allocator.free(m.raw_wrapper_call);
        }

        // Then collect this parent's own methods
        const range = try metadata_nav.methodRange(parent_file.table_info, loc.row);
        var mi = range.start;
        while (mi < range.end_exclusive) : (mi += 1) {
            const m = try parent_file.table_info.readMethodDef(mi);
            const name = try parent_file.heaps.getString(m.name);

            const vtbl_sig = buildMethodVtblSigEx(allocator, parent_ctx, parent_file, m, false) catch
                try allocator.dupe(u8, "VtblPlaceholder");

            try result.append(allocator, .{
                .raw_name = try allocator.dupe(u8, name),
                .norm_name = try allocator.dupe(u8, name),
                .vtbl_sig = vtbl_sig,
                .wrapper_sig = try allocator.dupe(u8, ""),
                .wrapper_call = try allocator.dupe(u8, ""),
                .raw_wrapper_sig = try allocator.dupe(u8, ""),
                .raw_wrapper_call = try allocator.dupe(u8, ""),
            });
        }
    }
    return result;
}

/// Build a vtbl_sig string for a method, using the same ABI logic as emit.zig.
/// Returns e.g. "*const fn (*anyopaque, *f64) callconv(.winapi) HRESULT".
/// When is_winrt is false (Win32 COM), the return type is kept as-is instead of
/// converting non-void returns into out parameters.
fn buildMethodVtblSig(
    allocator: std.mem.Allocator,
    parent_ctx: Context,
    pfile: *const FileEntry,
    m: @import("win_zig_metadata").tables.MethodDefRow,
) ![]const u8 {
    return buildMethodVtblSigEx(allocator, parent_ctx, pfile, m, true);
}

fn buildMethodVtblSigEx(
    allocator: std.mem.Allocator,
    parent_ctx: Context,
    pfile: *const FileEntry,
    m: @import("win_zig_metadata").tables.MethodDefRow,
    is_winrt: bool,
) ![]const u8 {
    const tp = type_predicates;
    const sig_blob = try pfile.heaps.getBlob(m.signature);
    var sig_c = SigCursor{ .data = sig_blob };
    _ = sig_c.readByte(); // calling convention
    const param_count = sig_c.readCompressedUInt() orelse return error.InvalidSignature;
    const ret_type_opt = try sig_decode.decodeSigType(allocator, parent_ctx, &sig_c, is_winrt);
    const ret_type_raw = ret_type_opt orelse "void";
    defer if (ret_type_opt != null) allocator.free(ret_type_raw);

    var vtbl_params = std.ArrayList(u8).empty;
    defer vtbl_params.deinit(allocator);
    try vtbl_params.appendSlice(allocator, "*anyopaque");

    var p_idx: u32 = 0;
    while (p_idx < param_count) : (p_idx += 1) {
        _ = (sig_c.pos < sig_c.data.len and sig_c.data[sig_c.pos] == 0x10); // byref check (consumed by decodeSigType)
        const p_type_opt = try sig_decode.decodeSigType(allocator, parent_ctx, &sig_c, is_winrt);
        const p_type_raw = p_type_opt orelse "?*anyopaque";
        defer if (p_type_opt != null) allocator.free(p_type_raw);

        const p_type_vtbl = if (std.mem.eql(u8, p_type_raw, "anyopaque"))
            try allocator.dupe(u8, "?*anyopaque")
        else if (tp.isBuiltinType(p_type_raw))
            try allocator.dupe(u8, p_type_raw)
        else if (std.mem.startsWith(u8, p_type_raw, "*")) blk: {
            const inner = p_type_raw[1..];
            if (tp.isBuiltinType(inner) or std.mem.eql(u8, inner, "EventRegistrationToken") or tp.isKnownStruct(inner))
                break :blk try allocator.dupe(u8, p_type_raw)
            else
                break :blk try allocator.dupe(u8, "*?*anyopaque");
        } else if (std.mem.startsWith(u8, p_type_raw, "?"))
            try allocator.dupe(u8, p_type_raw)
        else if (tp.isKnownStruct(p_type_raw) or std.mem.eql(u8, p_type_raw, "EventRegistrationToken"))
            try allocator.dupe(u8, p_type_raw)
        else if (tp.isInterfaceType(p_type_raw) or sig_decode.isComObjectType(parent_ctx, p_type_raw))
            try allocator.dupe(u8, "?*anyopaque")
        else
            try allocator.dupe(u8, "?*anyopaque");
        defer allocator.free(p_type_vtbl);

        try vtbl_params.appendSlice(allocator, ", ");
        try vtbl_params.appendSlice(allocator, p_type_vtbl);
    }

    if (is_winrt) {
        // WinRT: non-void return becomes out parameter, return type is always HRESULT
        if (!std.mem.eql(u8, ret_type_raw, "void") and !std.mem.startsWith(u8, ret_type_raw, "SZARRAY:")) {
            const is_known_value = tp.isBuiltinType(ret_type_raw) or tp.isKnownStruct(ret_type_raw) or std.mem.eql(u8, ret_type_raw, "EventRegistrationToken");
            if (!is_known_value) {
                try vtbl_params.appendSlice(allocator, ", *?*anyopaque");
            } else {
                const out_type = try std.fmt.allocPrint(allocator, ", *{s}", .{ret_type_raw});
                defer allocator.free(out_type);
                try vtbl_params.appendSlice(allocator, out_type);
            }
        } else if (std.mem.startsWith(u8, ret_type_raw, "SZARRAY:")) {
            try vtbl_params.appendSlice(allocator, ", *u32, *?*anyopaque");
        }
        return std.fmt.allocPrint(allocator, "*const fn ({s}) callconv(.winapi) HRESULT", .{vtbl_params.items});
    } else {
        // Win32 COM: keep the actual return type as-is (no out-param conversion)
        return std.fmt.allocPrint(allocator, "*const fn ({s}) callconv(.winapi) {s}", .{ vtbl_params.items, ret_type_raw });
    }
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

/// Compute parameterized TypedEventHandler<TSender, TResult> IIDs from method signatures.
///
/// This module extracts generic type arguments from GENERICINST-encoded method
/// parameters, computes their WinRT type signatures, and derives the IID via
/// SHA-1 (pinterface computation) using winrt_guid.zig.
const std = @import("std");
const win_zig_metadata = @import("win_zig_metadata");
const tables = win_zig_metadata.tables;
const streams = win_zig_metadata.streams;
const coded = win_zig_metadata.coded_index;
const resolver = @import("resolver.zig");
const guidmod = @import("winrt_guid.zig");
const sig_decode = @import("sig_decode.zig");
const ui = @import("unified_index.zig");

const Context = ui.UnifiedContext;
const SigCursor = sig_decode.SigCursor;

pub const EventIidResult = struct {
    guid: guidmod.Guid,
    event_suffix: []const u8, // owned, caller must free
    is_typed: bool,
};

/// Attempt to compute a parameterized EventHandler/TypedEventHandler IID for a method that is an event adder.
///
/// Returns null if:
/// - The method's first parameter is not a GENERICINST delegate we handle
/// - Type resolution fails for any generic argument
///
/// The returned `event_suffix` is allocated and must be freed by the caller.
pub fn computeParameterizedEventHandlerIid(
    allocator: std.mem.Allocator,
    ctx: Context,
    method_row: u32,
) !?EventIidResult {
    const m = try ctx.table_info.readMethodDef(method_row);
    const method_name = try ctx.heaps.getString(m.name);

    // Only process add_ methods
    if (!std.mem.startsWith(u8, method_name, "add_")) return null;
    const event_suffix = method_name["add_".len..];

    const sig_blob = try ctx.heaps.getBlob(m.signature);
    var c = SigCursor{ .data = sig_blob };

    // Skip calling convention byte
    _ = c.readByte() orelse return null;
    // Read param count
    const param_count = c.readCompressedUInt() orelse return null;
    if (param_count < 1) return null;

    // Skip return type
    _ = try skipSigType(&c);

    // Read first param: check if it's GENERICINST
    const first_byte = c.readByte() orelse return null;
    if (first_byte != 0x15) return null; // Not GENERICINST

    // Read CLASS (0x12) or VALUETYPE (0x11)
    const class_or_vt = c.readByte() orelse return null;
    _ = class_or_vt;

    // Read TypeDefOrRef coded index for the base generic type
    const tdor_idx = c.readCompressedUInt() orelse return null;
    const tdor = try coded.decodeTypeDefOrRef(tdor_idx);

    // Resolve the base type name to check if it's EventHandler/TypedEventHandler
    const base_name = try resolveTypeDefOrRefName(ctx, tdor) orelse return null;
    const is_typed_event_handler = std.mem.eql(u8, base_name, "TypedEventHandler`2") or
        std.mem.eql(u8, base_name, "TypedEventHandler");
    const is_event_handler = std.mem.eql(u8, base_name, "EventHandler`1") or
        std.mem.eql(u8, base_name, "EventHandler");

    if (!is_typed_event_handler and !is_event_handler) return null;

    // Read generic arg count
    const gen_arg_count = c.readCompressedUInt() orelse return null;
    if (is_typed_event_handler and gen_arg_count != 2) return null;
    if (is_event_handler and gen_arg_count != 1) return null;

    // Read generic arguments signatures
    var signatures = std.ArrayList([]const u8).empty;
    defer {
        for (signatures.items) |s| allocator.free(s);
        signatures.deinit(allocator);
    }

    var i: u32 = 0;
    while (i < gen_arg_count) : (i += 1) {
        const sig = try readTypeArgWinRTSignature(allocator, ctx, &c) orelse return null;
        try signatures.append(allocator, sig);
    }

    // Compute the IID
    const guid = if (is_typed_event_handler)
        try guidmod.typedEventHandlerIid(signatures.items[0], signatures.items[1], allocator)
    else
        try guidmod.eventHandlerIid(signatures.items[0], allocator);

    return EventIidResult{
        .guid = guid,
        .event_suffix = try allocator.dupe(u8, event_suffix),
        .is_typed = is_typed_event_handler,
    };
}

/// Read a type argument from the signature and produce its WinRT type signature string.
///
/// For IInspectable (0x1c / ELEMENT_TYPE_OBJECT): "cinterface(IInspectable)"
/// For runtime classes: "rc(Full.Name;{default-interface-guid})"
/// For interfaces/delegates: "{guid}"
fn readTypeArgWinRTSignature(
    allocator: std.mem.Allocator,
    ctx: Context,
    c: *SigCursor,
) !?[]const u8 {
    const b = c.readByte() orelse return null;
    switch (b) {
        0x1c => {
            // ELEMENT_TYPE_OBJECT -> IInspectable
            return try allocator.dupe(u8, "cinterface(IInspectable)");
        },
        0x11, 0x12 => {
            // VALUETYPE or CLASS
            const tdor_idx = c.readCompressedUInt() orelse return null;
            const tdor = try coded.decodeTypeDefOrRef(tdor_idx);
            return try resolveTypeArgSignature(allocator, ctx, tdor);
        },
        0x15 => {
            // GENERICINST — nested generic (e.g., IVector<String>)
            // Skip for now — not needed for TypedEventHandler scenarios
            _ = c.readByte(); // CLASS or VALUETYPE
            const tdor_idx = c.readCompressedUInt() orelse return null;
            _ = tdor_idx;
            const inner_count = c.readCompressedUInt() orelse return null;
            var gi: u32 = 0;
            while (gi < inner_count) : (gi += 1) {
                _ = try skipSigType(c);
            }
            return null;
        },
        else => {
            // Primitive types or unsupported
            return null;
        },
    }
}

/// Given a TypeDefOrRef, determine whether it's a runtime class or interface/delegate,
/// and produce the appropriate WinRT type signature.
fn resolveTypeArgSignature(
    allocator: std.mem.Allocator,
    ctx: Context,
    tdor: coded.Decoded,
) !?[]const u8 {
    // Get the full name of the type
    const full_name = try sig_decode.resolveTypeDefOrRefFullNameAlloc(allocator, ctx, tdor) orelse return null;
    defer allocator.free(full_name);

    // Try to find the TypeDef row (same file first)
    const td_row = try findTypeDefRow(ctx, full_name);
    if (td_row) |row| {
        return try computeSignatureForRow(allocator, ctx, full_name, row);
    }

    // Cross-file resolution via unified index
    if (ctx.index.findByFullName(full_name)) |loc| {
        const cross_ctx = ui.UnifiedContext.make(ctx.index, loc, ctx.dep_queue, ctx.allocator);
        return try computeSignatureForRow(allocator, cross_ctx, full_name, loc.row);
    }

    return null;
}

/// Compute the WinRT type signature for a TypeDef at a known row.
fn computeSignatureForRow(
    allocator: std.mem.Allocator,
    ctx: Context,
    full_name: []const u8,
    row: u32,
) !?[]const u8 {
    const cat = sig_decode.identifyTypeCategory(ctx, row) catch return null;
    const rctx = resolver.Context{ .table_info = ctx.table_info, .heaps = ctx.heaps };

    switch (cat) {
        .class => {
            // Runtime class: rc(Full.Name;{default-interface-guid})
            const default_guid = resolver.resolveDefaultInterfaceGuidForRuntimeClass(rctx, full_name) catch return null;
            return try guidmod.classSignatureAlloc(allocator, full_name, default_guid);
        },
        .interface, .delegate => {
            // Interface/delegate: {guid}
            const guid = resolver.extractGuidForTypeDef(rctx, row) catch return null;
            const guid_str = try guid.toDashedLowerAlloc(allocator);
            defer allocator.free(guid_str);
            return try std.fmt.allocPrint(allocator, "{{{s}}}", .{guid_str});
        },
        else => return null,
    }
}

/// Find a TypeDef row by full name within the current context's metadata file.
fn findTypeDefRow(ctx: Context, full_name: []const u8) !?u32 {
    const dot = std.mem.lastIndexOfScalar(u8, full_name, '.') orelse return null;
    const want_ns = full_name[0..dot];
    const want_name = full_name[dot + 1 ..];

    const t = ctx.table_info.getTable(.TypeDef);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const td = try ctx.table_info.readTypeDef(row);
        const name = try ctx.heaps.getString(td.type_name);
        const ns = try ctx.heaps.getString(td.type_namespace);
        if (std.mem.eql(u8, name, want_name) and std.mem.eql(u8, ns, want_ns)) return row;
        // Also match with backtick suffix stripped
        if (std.mem.indexOfScalar(u8, name, '`')) |bt| {
            if (std.mem.eql(u8, name[0..bt], want_name) and std.mem.eql(u8, ns, want_ns)) return row;
        }
    }
    return null;
}

/// Resolve a TypeDefOrRef coded index to a type name (raw, without namespace).
fn resolveTypeDefOrRefName(ctx: Context, tdor: coded.Decoded) !?[]const u8 {
    return switch (tdor.table) {
        .TypeDef => blk: {
            const td = try ctx.table_info.readTypeDef(tdor.row);
            break :blk try ctx.heaps.getString(td.type_name);
        },
        .TypeRef => blk: {
            const tr = try ctx.table_info.readTypeRef(tdor.row);
            break :blk try ctx.heaps.getString(tr.type_name);
        },
        else => null,
    };
}

/// Skip over a complete type in a signature blob (advance cursor past it).
fn skipSigType(c: *SigCursor) !void {
    const b = c.readByte() orelse return;
    switch (b) {
        // Primitive types: single byte
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x18, 0x19,
        0x1c,
        => {},
        // BYREF, PTR
        0x0f, 0x10 => try skipSigType(c),
        // CLASS, VALUETYPE
        0x11, 0x12 => {
            _ = c.readCompressedUInt();
        },
        // GENERICINST
        0x15 => {
            _ = c.readByte(); // CLASS or VALUETYPE
            _ = c.readCompressedUInt(); // TypeDefOrRef
            const count = c.readCompressedUInt() orelse return;
            var i: u32 = 0;
            while (i < count) : (i += 1) {
                try skipSigType(c);
            }
        },
        // VAR, MVAR
        0x13, 0x1e => {
            _ = c.readCompressedUInt();
        },
        // SZARRAY
        0x1d => try skipSigType(c),
        // CMOD_REQD, CMOD_OPT
        0x1f, 0x20 => {
            _ = c.readCompressedUInt();
            try skipSigType(c);
        },
        else => {},
    }
}

/// Format a GUID as a Zig GUID literal string for code generation.
pub fn formatGuidLiteral(guid: guidmod.Guid, writer: anytype) !void {
    try writer.print("GUID{{ .data1 = 0x{x:0>8}, .data2 = 0x{x:0>4}, .data3 = 0x{x:0>4}, .data4 = .{{ 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2} }} }}", .{
        guid.data1,
        guid.data2,
        guid.data3,
        guid.data4[0],
        guid.data4[1],
        guid.data4[2],
        guid.data4[3],
        guid.data4[4],
        guid.data4[5],
        guid.data4[6],
        guid.data4[7],
    });
}

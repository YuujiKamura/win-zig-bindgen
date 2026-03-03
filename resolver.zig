const std = @import("std");
const tables = @import("tables.zig");
const streams = @import("streams.zig");
const coded = @import("coded_index.zig");
const guidmod = @import("winrt_guid.zig");

pub const Context = struct {
    table_info: tables.Info,
    heaps: streams.Heaps,
};

pub const ResolveError = error{
    TypeNotFound,
    InterfaceNotFound,
    MissingGuidAttribute,
    InvalidGuidBlob,
    UnsupportedTypeRef,
    InvalidGuidText,
} || tables.TableError || streams.HeapError || coded.IndexError || std.mem.Allocator.Error;

pub fn findTypeDefRowByFullName(ctx: Context, full_name: []const u8) ResolveError!u32 {
    const dot_index = std.mem.lastIndexOfScalar(u8, full_name, '.') orelse return error.TypeNotFound;
    const want_ns = full_name[0..dot_index];
    const want_name = full_name[dot_index + 1 ..];

    const t = ctx.table_info.getTable(.TypeDef);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const td = try ctx.table_info.readTypeDef(row);
        const name = try ctx.heaps.getString(td.type_name);
        if (!std.mem.eql(u8, name, want_name)) continue;
        const ns = try ctx.heaps.getString(td.type_namespace);
        if (std.mem.eql(u8, ns, want_ns)) return row;
    }
    return error.TypeNotFound;
}

pub fn typeDefFullNameAlloc(ctx: Context, allocator: std.mem.Allocator, row: u32) ResolveError![]u8 {
    const td = try ctx.table_info.readTypeDef(row);
    const ns = try ctx.heaps.getString(td.type_namespace);
    const name = try ctx.heaps.getString(td.type_name);
    return std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns, name });
}

pub fn extractGuidForTypeDef(ctx: Context, type_row: u32) ResolveError!guidmod.Guid {
    const ca_table = ctx.table_info.getTable(.CustomAttribute);
    var row: u32 = 1;
    while (row <= ca_table.row_count) : (row += 1) {
        const ca = try ctx.table_info.readCustomAttribute(row);
        const parent = try coded.decodeHasCustomAttribute(ca.parent);
        if (parent.table != .TypeDef or parent.row != type_row) continue;

        if (!try isCustomAttributeCtorAnyNamespace(ctx, ca.ca_type, "GuidAttribute"))
        {
            continue;
        }

        const blob = try ctx.heaps.getBlob(ca.value);
        return try parseGuidAttributeValue(blob);
    }
    return error.MissingGuidAttribute;
}

pub fn resolveDefaultInterfaceGuidForRuntimeClass(ctx: Context, runtime_class_full_name: []const u8) ResolveError!guidmod.Guid {
    const iface_row = try resolveDefaultInterfaceTypeDefRowForRuntimeClass(ctx, runtime_class_full_name);
    return extractGuidForTypeDef(ctx, iface_row);
}

pub fn resolveDefaultInterfaceNameForRuntimeClassAlloc(
    ctx: Context,
    allocator: std.mem.Allocator,
    runtime_class_full_name: []const u8,
) ResolveError![]u8 {
    const iface_row = try resolveDefaultInterfaceTypeDefRowForRuntimeClass(ctx, runtime_class_full_name);
    return typeDefFullNameAlloc(ctx, allocator, iface_row);
}

fn resolveDefaultInterfaceTypeDefRowForRuntimeClass(ctx: Context, runtime_class_full_name: []const u8) ResolveError!u32 {
    const class_row = try findTypeDefRowByFullName(ctx, runtime_class_full_name);
    const impl_table = ctx.table_info.getTable(.InterfaceImpl);

    var fallback_iface_row: ?u32 = null;
    var row: u32 = 1;
    while (row <= impl_table.row_count) : (row += 1) {
        const impl = try ctx.table_info.readInterfaceImpl(row);
        if (impl.class != class_row) continue;

        const decoded = try coded.decodeTypeDefOrRef(impl.interface);
        const iface_row = try resolveTypeDefOrRefToTypeDef(ctx, decoded);
        if (fallback_iface_row == null) fallback_iface_row = iface_row;

        if (try hasDefaultAttributeOnInterfaceImpl(ctx, row)) {
            return iface_row;
        }
    }

    if (fallback_iface_row) |iface_row| {
        return iface_row;
    }
    return error.InterfaceNotFound;
}

fn resolveTypeDefOrRefToTypeDef(ctx: Context, decoded: coded.Decoded) ResolveError!u32 {
    return switch (decoded.table) {
        .TypeDef => decoded.row,
        .TypeRef => blk: {
            const tr = try ctx.table_info.readTypeRef(decoded.row);
            const want_name = try ctx.heaps.getString(tr.type_name);
            const want_ns = try ctx.heaps.getString(tr.type_namespace);
            const t = ctx.table_info.getTable(.TypeDef);
            var row: u32 = 1;
            while (row <= t.row_count) : (row += 1) {
                const td = try ctx.table_info.readTypeDef(row);
                const name = try ctx.heaps.getString(td.type_name);
                if (!std.mem.eql(u8, name, want_name)) continue;
                const ns = try ctx.heaps.getString(td.type_namespace);
                if (std.mem.eql(u8, ns, want_ns)) break :blk row;
            }
            return error.UnsupportedTypeRef;
        },
        else => error.UnsupportedTypeRef,
    };
}

fn hasDefaultAttributeOnInterfaceImpl(ctx: Context, interface_impl_row: u32) ResolveError!bool {
    const ca_table = ctx.table_info.getTable(.CustomAttribute);
    var row: u32 = 1;
    while (row <= ca_table.row_count) : (row += 1) {
        const ca = try ctx.table_info.readCustomAttribute(row);
        const parent = try coded.decodeHasCustomAttribute(ca.parent);
        if (parent.table != .InterfaceImpl or parent.row != interface_impl_row) continue;
        if (try isCustomAttributeCtor(ctx, ca.ca_type, "DefaultAttribute", "Windows.Foundation.Metadata")) {
            return true;
        }
    }
    return false;
}

fn isCustomAttributeCtor(ctx: Context, ca_type_raw: u32, attr_name: []const u8, attr_ns: []const u8) ResolveError!bool {
    const ca_type = try coded.decodeCustomAttributeType(ca_type_raw);
    if (ca_type.table != .MemberRef) return false;
    const mr = try ctx.table_info.readMemberRef(ca_type.row);
    const member_name = try ctx.heaps.getString(mr.name);
    if (!std.mem.eql(u8, member_name, ".ctor")) return false;

    const class_decoded = decodeMemberRefParent(mr.class) catch return false;
    if (class_decoded.table != .TypeRef) return false;

    const tr = try ctx.table_info.readTypeRef(class_decoded.row);
    const tr_name = try ctx.heaps.getString(tr.type_name);
    const tr_ns = try ctx.heaps.getString(tr.type_namespace);
    return std.mem.eql(u8, tr_name, attr_name) and std.mem.eql(u8, tr_ns, attr_ns);
}

fn isCustomAttributeCtorAnyNamespace(ctx: Context, ca_type_raw: u32, attr_name: []const u8) ResolveError!bool {
    const ca_type = try coded.decodeCustomAttributeType(ca_type_raw);
    if (ca_type.table != .MemberRef) return false;
    const mr = try ctx.table_info.readMemberRef(ca_type.row);
    const member_name = try ctx.heaps.getString(mr.name);
    if (!std.mem.eql(u8, member_name, ".ctor")) return false;

    const class_decoded = decodeMemberRefParent(mr.class) catch return false;
    if (class_decoded.table != .TypeRef) return false;

    const tr = try ctx.table_info.readTypeRef(class_decoded.row);
    const tr_name = try ctx.heaps.getString(tr.type_name);
    return std.mem.eql(u8, tr_name, attr_name);
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

fn parseGuidAttributeValue(blob: []const u8) ResolveError!guidmod.Guid {
    if (blob.len < 2 or blob[0] != 0x01 or blob[1] != 0x00) return error.InvalidGuidBlob;
    if (blob.len >= 18) {
        // WinRT-style fixed 16-byte GUID payload.
        return guidmod.Guid.fromBlob(blob[2..18].*);
    }

    // COM-style GuidAttribute(string): SerString after prolog.
    const payload = blob[2..];
    if (payload.len == 0 or payload[0] == 0xFF) return error.InvalidGuidBlob;
    const len_info = streams.decodeCompressedUInt(payload) catch return error.InvalidGuidBlob;
    const start = len_info.used;
    const end = start + len_info.value;
    if (end > payload.len) return error.InvalidGuidBlob;
    return guidmod.parseGuidText(payload[start..end]) catch error.InvalidGuidText;
}

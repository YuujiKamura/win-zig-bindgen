const std = @import("std");
const win_zig_metadata = @import("win_zig_metadata");
const tables = win_zig_metadata.tables;
const streams = win_zig_metadata.streams;
const coded = win_zig_metadata.coded_index;
const context = @import("context.zig");
const ui = @import("unified_index.zig");
const type_predicates = @import("type_predicates.zig");

const Context = ui.UnifiedContext;
const MethodRange = context.MethodRange;

pub fn findTypeDefRow(ctx: Context, interface_name: []const u8) !u32 {
    const dot_index = std.mem.lastIndexOfScalar(u8, interface_name, '.');
    const want_ns = if (dot_index) |idx| interface_name[0..idx] else null;
    const want_name = if (dot_index) |idx| interface_name[idx + 1 ..] else interface_name;
    const t = ctx.table_info.getTable(.TypeDef);
    var first_name_match: ?u32 = null;
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const td = try ctx.table_info.readTypeDef(row);
        const name = try ctx.heaps.getString(td.type_name);
        const ns = try ctx.heaps.getString(td.type_namespace);
        if (!type_predicates.typeNameMatches(want_name, name)) continue;
        if (want_ns == null) return row;
        if (std.mem.eql(u8, ns, want_ns.?)) return row;
        if (std.mem.endsWith(u8, ns, want_ns.?)) return row;
        if (first_name_match == null) first_name_match = row;
    }
    if (first_name_match) |r| return r;
    return error.InterfaceNotFound;
}

pub fn methodRange(info: tables.Info, type_row: u32) !MethodRange {
    const td = try info.readTypeDef(type_row);
    return .{ .start = td.method_list, .end_exclusive = if (type_row < info.getTable(.TypeDef).row_count) (try info.readTypeDef(type_row + 1)).method_list else info.getTable(.MethodDef).row_count + 1 };
}

pub fn fieldRange(info: tables.Info, type_row: u32) !MethodRange {
    const td = try info.readTypeDef(type_row);
    return .{ .start = td.field_list, .end_exclusive = if (type_row < info.getTable(.TypeDef).row_count) (try info.readTypeDef(type_row + 1)).field_list else info.getTable(.Field).row_count + 1 };
}

pub fn paramRange(info: tables.Info, method_row: u32) !MethodRange {
    const md = try info.readMethodDef(method_row);
    return .{ .start = md.param_list, .end_exclusive = if (method_row < info.getTable(.MethodDef).row_count) (try info.readMethodDef(method_row + 1)).param_list else info.getTable(.Param).row_count + 1 };
}

pub fn extractGuid(ctx: Context, type_row: u32) ![16]u8 {
    const ca_table = ctx.table_info.getTable(.CustomAttribute);
    var row: u32 = 1;
    while (row <= ca_table.row_count) : (row += 1) {
        const ca = try ctx.table_info.readCustomAttribute(row);
        const parent = try coded.decodeHasCustomAttribute(ca.parent);
        if (parent.table == .TypeDef and parent.row == type_row) {
            const ty = try coded.decodeCustomAttributeType(ca.ca_type);
            const tr = try ctx.table_info.readMemberRef(ty.row);
            const tr_parent = try coded.decodeMemberRefParent(tr.class);
            const tr_type = try ctx.table_info.readTypeRef(tr_parent.row);
            const tr_name = try ctx.heaps.getString(tr_type.type_name);
            if (std.mem.eql(u8, tr_name, "GuidAttribute")) {
                const blob = try ctx.heaps.getBlob(ca.value);
                if (blob.len >= 18) return blob[2..18].*;
            }
        }
    }
    return error.MissingGuidAttribute;
}

pub fn hasAttribute(ctx: Context, type_row: u32, attr_name: []const u8) !bool {
    const ca_table = ctx.table_info.getTable(.CustomAttribute);
    var row: u32 = 1;
    while (row <= ca_table.row_count) : (row += 1) {
        const ca = try ctx.table_info.readCustomAttribute(row);
        const parent = try coded.decodeHasCustomAttribute(ca.parent);
        if (parent.table == .TypeDef and parent.row == type_row) {
            const ty = try coded.decodeCustomAttributeType(ca.ca_type);
            if (ty.table == .MemberRef) {
                const tr = try ctx.table_info.readMemberRef(ty.row);
                const tr_parent = try coded.decodeMemberRefParent(tr.class);
                if (tr_parent.table == .TypeRef) {
                    const tr_type = try ctx.table_info.readTypeRef(tr_parent.row);
                    const tr_name = try ctx.heaps.getString(tr_type.type_name);
                    if (std.mem.eql(u8, tr_name, attr_name)) return true;
                }
            }
        }
    }
    return false;
}

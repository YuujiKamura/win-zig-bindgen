const std = @import("std");
const win_zig_metadata = @import("win_zig_metadata");
const tables = win_zig_metadata.tables;
const streams = win_zig_metadata.streams;
const coded = win_zig_metadata.coded_index;
const resolver = @import("resolver.zig");
const ui = @import("unified_index.zig");
const context = @import("context.zig");
const type_predicates = @import("type_predicates.zig");
const metadata_nav = @import("metadata_nav.zig");

const Context = ui.UnifiedContext;
const TypeCategory = context.TypeCategory;
const MethodRange = context.MethodRange;

pub const SigCursor = struct {
    data: []const u8,
    pos: usize = 0,
    pub fn readByte(self: *@This()) ?u8 {
        if (self.pos >= self.data.len) return null;
        const b = self.data[self.pos];
        self.pos += 1;
        return b;
    }
    pub fn readCompressedUInt(self: *@This()) ?u32 {
        const b1 = self.readByte() orelse return null;
        if (b1 & 0x80 == 0) return b1;
        const b2 = self.readByte() orelse return null;
        if (b1 & 0x40 == 0) return (@as(u32, b1 & 0x3F) << 8) | b2;
        const b3 = self.readByte() orelse return null;
        const b4 = self.readByte() orelse return null;
        return (@as(u32, b1 & 0x1F) << 24) | (@as(u32, b2) << 16) | (@as(u32, b3) << 8) | b4;
    }
};

pub fn resolveTypeDefOrRefFullNameAlloc(allocator: std.mem.Allocator, ctx: Context, tdor: coded.Decoded) !?[]const u8 {
    return switch (tdor.table) {
        .TypeDef => blk: {
            const td = try ctx.table_info.readTypeDef(tdor.row);
            const ns = try ctx.heaps.getString(td.type_namespace);
            const name = try ctx.heaps.getString(td.type_name);
            if (ns.len == 0) break :blk try allocator.dupe(u8, name);
            break :blk try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns, name });
        },
        .TypeRef => blk: {
            const tr = try ctx.table_info.readTypeRef(tdor.row);
            const ns = try ctx.heaps.getString(tr.type_namespace);
            const name = try ctx.heaps.getString(tr.type_name);
            if (ns.len == 0) break :blk try allocator.dupe(u8, name);
            break :blk try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns, name });
        },
        .TypeSpec => blk: {
            const base = try resolveTypeSpecBaseType(ctx, tdor.row) orelse break :blk null;
            break :blk try resolveTypeDefOrRefFullNameAlloc(allocator, ctx, base);
        },
        else => null,
    };
}

pub fn resolveTypeDefOrRefNameRaw(ctx: Context, tdor: coded.Decoded) !?[]const u8 {
    return switch (tdor.table) {
        .TypeDef => blk: {
            const td = try ctx.table_info.readTypeDef(tdor.row);
            break :blk try ctx.heaps.getString(td.type_name);
        },
        .TypeRef => blk: {
            const tr = try ctx.table_info.readTypeRef(tdor.row);
            break :blk try ctx.heaps.getString(tr.type_name);
        },
        .TypeSpec => blk: {
            const base = try resolveTypeSpecBaseType(ctx, tdor.row) orelse break :blk null;
            break :blk try resolveTypeDefOrRefNameRaw(ctx, base);
        },
        else => null,
    };
}

/// Resolve a TypeDefOrRef coded index to a TypeDef row in the same metadata.
/// For TypeDef, returns the row directly. For TypeRef, searches TypeDef table by name.
/// Falls back to unified index for cross-file resolution.
/// Returns null if unresolvable (e.g., TypeSpec or not found).
pub fn resolveTypeDefOrRefToRow(ctx: Context, tdor: coded.Decoded) !?u32 {
    switch (tdor.table) {
        .TypeDef => return tdor.row,
        .TypeRef => {
            const tr = try ctx.table_info.readTypeRef(tdor.row);
            const ref_name = try ctx.heaps.getString(tr.type_name);
            const ref_ns = try ctx.heaps.getString(tr.type_namespace);
            const t = ctx.table_info.getTable(.TypeDef);
            var first_name_match: ?u32 = null;
            var row: u32 = 1;
            while (row <= t.row_count) : (row += 1) {
                const td = try ctx.table_info.readTypeDef(row);
                const name = try ctx.heaps.getString(td.type_name);
                const ns = try ctx.heaps.getString(td.type_namespace);
                if (type_predicates.typeNameMatches(ref_name, name) and std.mem.eql(u8, ns, ref_ns)) return row;
                if (first_name_match == null and type_predicates.typeNameMatches(ref_name, name)) first_name_match = row;
            }
            if (first_name_match) |m| return m;

            // Cross-file resolution via unified index
            if (ctx.index.resolveTypeRef(ctx.file(), tdor.row)) |loc| {
                // If the resolved type is in the same file, return the row directly
                if (loc.file_idx == ctx.loc.file_idx) return loc.row;
                // For cross-file types, return null — caller should use unified index directly
            }
            return null;
        },
        .TypeSpec => {
            const base = try resolveTypeSpecBaseType(ctx, tdor.row) orelse return null;
            return try resolveTypeDefOrRefToRow(ctx, base);
        },
        else => return null,
    }
}

pub fn resolveTypeSpecBaseType(ctx: Context, type_spec_row: u32) !?coded.Decoded {
    const ts = ctx.table_info.readTypeSpec(type_spec_row) catch return null;
    const blob = try ctx.heaps.getBlob(ts.signature);
    var c = SigCursor{ .data = blob };
    const lead = c.readByte() orelse return null;
    return switch (lead) {
        0x11, 0x12 => blk: {
            const tdor_idx = c.readCompressedUInt() orelse return null;
            break :blk try coded.decodeTypeDefOrRef(tdor_idx);
        },
        0x15 => blk: {
            _ = c.readByte() orelse return null; // CLASS or VALUETYPE
            const tdor_idx = c.readCompressedUInt() orelse return null;
            break :blk try coded.decodeTypeDefOrRef(tdor_idx);
        },
        else => null,
    };
}

pub fn identifyTypeCategory(ctx: Context, type_row: u32) !TypeCategory {
    const td = try ctx.table_info.readTypeDef(type_row);
    if ((td.flags & 0x00000020) != 0) return .interface;
    if (td.extends == 0) return .other;
    const extends_tdor = try coded.decodeTypeDefOrRef(td.extends);
    const base = try resolveTypeDefOrRefNameRaw(ctx, extends_tdor) orelse return .other;
    if (std.mem.eql(u8, base, "Enum")) return .enum_type;
    if (std.mem.eql(u8, base, "ValueType")) return .struct_type;
    if (std.mem.eql(u8, base, "MulticastDelegate")) return .delegate;
    return .class;
}

/// Returns true if the resolved type name represents a COM object (interface/class/delegate)
/// by looking it up in the TypeDef table and the unified index.
pub fn isComObjectType(ctx: Context, name: []const u8) bool {
    if (type_predicates.isBuiltinType(name)) return false;
    if (type_predicates.isKnownStruct(name)) return false;
    if (std.mem.eql(u8, name, "EventRegistrationToken")) return false;
    if (std.mem.eql(u8, name, "?*anyopaque") or std.mem.eql(u8, name, "anyopaque")) return false;

    // Scan primary TypeDef table
    const t = ctx.table_info.getTable(.TypeDef);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const td = ctx.table_info.readTypeDef(row) catch continue;
        const td_name = ctx.heaps.getString(td.type_name) catch continue;
        if (!type_predicates.typeNameMatches(name, td_name)) continue;
        const cat = identifyTypeCategory(ctx, row) catch continue;
        return cat == .interface or cat == .class or cat == .delegate;
    }

    // Cross-file resolution via unified index
    if (ctx.index.findByShortName(name)) |found_loc| {
        const tmp = ui.UnifiedContext.make(ctx.index, found_loc, ctx.dep_queue, ctx.allocator);
        const cat = identifyTypeCategory(tmp, found_loc.row) catch return false;
        return cat == .interface or cat == .class or cat == .delegate;
    }

    return false;
}

pub fn decodeSigType(allocator: std.mem.Allocator, ctx: Context, c: *SigCursor, is_winrt_iface: bool) !?[]const u8 {
    const b = c.readByte() orelse return null;
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
        0x0e => try allocator.dupe(u8, if (is_winrt_iface) "HSTRING" else "[*]const u16"),
        0x10 => blk: {
            const inner = try decodeSigType(allocator, ctx, c, is_winrt_iface) orelse break :blk null;
            defer allocator.free(inner);
            break :blk try std.fmt.allocPrint(allocator, "*{s}", .{inner});
        },
        0x0f => blk: {
            const inner = try decodeSigType(allocator, ctx, c, is_winrt_iface) orelse break :blk null;
            defer allocator.free(inner);
            break :blk try std.fmt.allocPrint(allocator, "*{s}", .{inner});
        },
        0x1f, 0x20 => blk: {
            _ = c.readCompressedUInt() orelse break :blk null;
            break :blk try decodeSigType(allocator, ctx, c, is_winrt_iface);
        },
        0x1c => try allocator.dupe(u8, "IInspectable"), // ELEMENT_TYPE_OBJECT -> System.Object -> IInspectable
        0x11, 0x12 => blk: {
            const tdor_idx = c.readCompressedUInt() orelse break :blk null;
            const tdor = try coded.decodeTypeDefOrRef(tdor_idx);
            const full = try resolveTypeDefOrRefFullNameAlloc(allocator, ctx, tdor) orelse break :blk null;
            defer allocator.free(full);

            if (std.mem.eql(u8, full, "System.Guid") or std.mem.eql(u8, full, "Guid")) break :blk try allocator.dupe(u8, "GUID");
            if (std.mem.eql(u8, full, "System.IntPtr")) break :blk try allocator.dupe(u8, "isize");
            if (std.mem.eql(u8, full, "System.UIntPtr")) break :blk try allocator.dupe(u8, "usize");
            if (std.mem.endsWith(u8, full, ".HWND")) break :blk try allocator.dupe(u8, "HWND");
            if (std.mem.endsWith(u8, full, ".HANDLE")) break :blk try allocator.dupe(u8, "HANDLE");
            if (std.mem.endsWith(u8, full, ".BOOL")) break :blk try allocator.dupe(u8, "BOOL");
            if (std.mem.endsWith(u8, full, ".WPARAM")) break :blk try allocator.dupe(u8, "WPARAM");
            if (std.mem.endsWith(u8, full, ".LPARAM")) break :blk try allocator.dupe(u8, "LPARAM");
            if (std.mem.endsWith(u8, full, ".LPCWSTR")) break :blk try allocator.dupe(u8, "LPCWSTR");
            if (std.mem.endsWith(u8, full, ".LPWSTR")) break :blk try allocator.dupe(u8, "LPWSTR");
            if (std.mem.endsWith(u8, full, ".HRESULT")) break :blk try allocator.dupe(u8, "HRESULT");
            const dot = std.mem.lastIndexOfScalar(u8, full, '.');
            const short = if (dot) |d| full[d + 1 ..] else full;

            try ctx.registerDependency(allocator, full);

            var found_td: ?u32 = null;
            if (tdor.table == .TypeDef) {
                found_td = tdor.row;
            } else {
                found_td = resolveTypeDefOrRefToRow(ctx, tdor) catch null;
            }

            if (found_td) |td_row| {
                const cat = identifyTypeCategory(ctx, td_row) catch .other;
                if (cat == .enum_type) break :blk try allocator.dupe(u8, "i32");
                if (cat == .struct_type) break :blk try allocator.dupe(u8, short);
                if (cat == .class) {
                    // Runtime class: resolve to default interface name for ABI compatibility.
                    const rctx = resolver.Context{ .table_info = ctx.table_info, .heaps = ctx.heaps };
                    if (resolver.resolveDefaultInterfaceNameForRuntimeClassAlloc(rctx, allocator, full)) |iface_full| {
                        defer allocator.free(iface_full);
                        try ctx.registerDependency(allocator, iface_full);
                        const iface_dot = std.mem.lastIndexOfScalar(u8, iface_full, '.') orelse 0;
                        const iface_short = if (iface_dot > 0) iface_full[iface_dot + 1 ..] else iface_full;
                        break :blk try allocator.dupe(u8, iface_short);
                    } else |_| {
                        break :blk try allocator.dupe(u8, short);
                    }
                }
                if (cat == .interface or cat == .delegate) break :blk try allocator.dupe(u8, short);
            }

            // Cross-file resolution via unified index
            if (found_td == null) {
                if (ctx.index.findByFullName(full)) |comp_loc| {
                    const tmp = ui.UnifiedContext.make(ctx.index, comp_loc, ctx.dep_queue, ctx.allocator);
                    const cat = identifyTypeCategory(tmp, comp_loc.row) catch .other;
                    if (cat == .enum_type) break :blk try allocator.dupe(u8, "i32");
                    if (cat == .struct_type) break :blk try allocator.dupe(u8, short);
                    if (cat == .class) {
                        // Cross-file class: resolve default interface
                        const comp_file = ctx.index.fileOf(comp_loc);
                        const rctx = resolver.Context{ .table_info = comp_file.table_info, .heaps = comp_file.heaps };
                        if (resolver.resolveDefaultInterfaceNameForRuntimeClassAlloc(rctx, allocator, full)) |iface_full| {
                            defer allocator.free(iface_full);
                            try ctx.registerDependency(allocator, iface_full);
                            const iface_dot = std.mem.lastIndexOfScalar(u8, iface_full, '.') orelse 0;
                            const iface_short = if (iface_dot > 0) iface_full[iface_dot + 1 ..] else iface_full;
                            break :blk try allocator.dupe(u8, iface_short);
                        } else |_| {
                            // Default interface not found, use class name
                            break :blk try allocator.dupe(u8, short);
                        }
                    }
                    if (cat == .interface or cat == .delegate) break :blk try allocator.dupe(u8, short);
                }
            }

            // Well-known types
            if (std.mem.eql(u8, short, "IInspectable")) break :blk try allocator.dupe(u8, "IInspectable");
            if (std.mem.eql(u8, short, "IXamlType")) break :blk try allocator.dupe(u8, "IXamlType");
            if (std.mem.eql(u8, short, "EventRegistrationToken")) break :blk try allocator.dupe(u8, "EventRegistrationToken");
            if (type_predicates.isKnownExternalEnum(short)) break :blk try allocator.dupe(u8, "i32");
            if (type_predicates.isKnownStruct(short)) break :blk try allocator.dupe(u8, short);

            break :blk try allocator.dupe(u8, "?*anyopaque");
        },
        0x1d => blk: {
            // SZARRAY: consume element type to keep cursor aligned
            const elem = try decodeSigType(allocator, ctx, c, is_winrt_iface);
            if (elem) |e| allocator.free(e);
            // WinRT array return: becomes [out] uint32, [out] T* at ABI level
            break :blk try allocator.dupe(u8, "SZARRAY");
        },
        0x15 => blk: {
            // GENERICINST: marker CLASS/VALUETYPE, TypeDefOrRef, count, type_args...
            _ = c.readByte() orelse break :blk try allocator.dupe(u8, "?*anyopaque"); // CLASS (0x12) or VALUETYPE (0x11)
            const tdor_idx = c.readCompressedUInt() orelse break :blk try allocator.dupe(u8, "?*anyopaque");
            const gen_arg_count = c.readCompressedUInt() orelse break :blk try allocator.dupe(u8, "?*anyopaque");
            // Consume generic type arguments AND register dependencies for each
            var ga: u32 = 0;
            while (ga < gen_arg_count) : (ga += 1) {
                const arg = try decodeSigType(allocator, ctx, c, is_winrt_iface);
                if (arg) |a| {
                    if (!std.mem.eql(u8, a, "?*anyopaque") and !type_predicates.isBuiltinType(a)) {
                        try ctx.registerDependency(allocator, a);
                    }
                    allocator.free(a);
                }
            }
            // Resolve the base type using the same logic as 0x11/0x12
            const tdor = try coded.decodeTypeDefOrRef(tdor_idx);
            const full = try resolveTypeDefOrRefFullNameAlloc(allocator, ctx, tdor) orelse break :blk try allocator.dupe(u8, "?*anyopaque");
            defer allocator.free(full);

            const dot = std.mem.lastIndexOfScalar(u8, full, '.');
            const short_raw = if (dot) |d| full[d + 1 ..] else full;
            const is_generic = std.mem.indexOfScalar(u8, short_raw, '`') != null;
            const short = if (is_generic) short_raw[0..std.mem.indexOfScalar(u8, short_raw, '`').?] else short_raw;

            // Register dependency with tick-trimmed name so generic base types
            // (e.g., IVector`1 -> IVector) enter the generation queue
            if (is_generic) {
                if (dot) |d| {
                    const trimmed_full = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ full[0..d], short });
                    defer allocator.free(trimmed_full);
                    try ctx.registerDependency(allocator, trimmed_full);
                } else {
                    try ctx.registerDependency(allocator, short);
                }
                // Return the trimmed type name; Stage 2 in emit.zig handles ABI ?*anyopaque conversion
                break :blk try allocator.dupe(u8, short);
            }

            try ctx.registerDependency(allocator, full);

            // Try resolving via TypeDef table (same as 0x11/0x12)
            var found_td: ?u32 = null;
            if (tdor.table == .TypeDef) {
                found_td = tdor.row;
            } else {
                found_td = resolveTypeDefOrRefToRow(ctx, tdor) catch null;
            }

            if (found_td) |td_row| {
                const cat = identifyTypeCategory(ctx, td_row) catch .other;
                if (cat == .enum_type) break :blk try allocator.dupe(u8, "i32");
                if (cat == .struct_type) break :blk try allocator.dupe(u8, short);
                if (cat == .interface or cat == .delegate) break :blk try allocator.dupe(u8, short);
            }

            // Cross-file resolution via unified index for GENERICINST
            if (found_td == null) {
                if (ctx.index.findByFullName(full)) |comp_loc| {
                    const tmp = ui.UnifiedContext.make(ctx.index, comp_loc, ctx.dep_queue, ctx.allocator);
                    const cat = identifyTypeCategory(tmp, comp_loc.row) catch .other;
                    if (cat == .enum_type) break :blk try allocator.dupe(u8, "i32");
                    if (cat == .struct_type or cat == .interface or cat == .delegate or cat == .class) {
                        break :blk try allocator.dupe(u8, short);
                    }
                }
            }

            // Cross-file fallback: known types and interface-like names
            if (std.mem.eql(u8, short, "IInspectable")) break :blk try allocator.dupe(u8, "IInspectable");
            if (std.mem.eql(u8, short, "EventRegistrationToken")) break :blk try allocator.dupe(u8, "EventRegistrationToken");
            if (type_predicates.isKnownExternalEnum(short)) break :blk try allocator.dupe(u8, "i32");
            if (type_predicates.isKnownStruct(short)) break :blk try allocator.dupe(u8, short);
            if (type_predicates.isInterfaceType(short) or std.mem.startsWith(u8, full, "Windows.") or std.mem.startsWith(u8, full, "Microsoft.")) {
                break :blk try allocator.dupe(u8, short);
            }

            break :blk try allocator.dupe(u8, "?*anyopaque");
        },
        0x13, 0x1e => blk: {
            // VAR / MVAR: generic type/method parameter — consume the index
            _ = c.readCompressedUInt();
            break :blk try allocator.dupe(u8, "?*anyopaque");
        },
        0x18 => try allocator.dupe(u8, "isize"),
        0x19 => try allocator.dupe(u8, "usize"),
        else => try allocator.dupe(u8, "?*anyopaque"),
    };
}

pub fn collectParamNames(allocator: std.mem.Allocator, ctx: Context, method_row: u32) !std.ArrayList([]const u8) {
    var result = std.ArrayList([]const u8).empty;
    const range = try metadata_nav.paramRange(ctx.table_info, method_row);
    var pi = range.start;
    while (pi < range.end_exclusive) : (pi += 1) {
        const p = try ctx.table_info.readParam(pi);
        if (p.sequence == 0) continue; // Skip return type
        try result.append(allocator, try ctx.heaps.getString(p.name));
    }
    return result;
}

pub fn detectEnumBackingType(ctx: Context, range: MethodRange) ![]const u8 {
    var i = range.start;
    while (i < range.end_exclusive) : (i += 1) {
        const f = try ctx.table_info.readField(i);
        const name = try ctx.heaps.getString(f.name);
        if (std.mem.eql(u8, name, "value__")) {
            const sig_blob = try ctx.heaps.getBlob(f.signature);
            if (sig_blob.len < 3) return "i32";
            // Field sig: 0x06 (FIELD), optional custom mods, then element type
            const elem = sig_blob[2];
            return switch (elem) {
                0x04 => "i8",
                0x05 => "u8",
                0x06 => "i16",
                0x07 => "u16",
                0x08 => "i32",
                0x09 => "u32",
                0x0A => "i64",
                0x0B => "u64",
                else => "i32",
            };
        }
    }
    return "i32";
}

pub fn readSignedConstant(blob: []const u8, backing_type: []const u8) i64 {
    if (std.mem.eql(u8, backing_type, "i8")) {
        if (blob.len >= 1) return @as(i64, @as(i8, @bitCast(blob[0])));
    } else if (std.mem.eql(u8, backing_type, "i16")) {
        if (blob.len >= 2) return @as(i64, std.mem.readInt(i16, blob[0..2], .little));
    } else if (std.mem.eql(u8, backing_type, "i64")) {
        if (blob.len >= 8) return std.mem.readInt(i64, blob[0..8], .little);
    } else {
        if (blob.len >= 4) return @as(i64, std.mem.readInt(i32, blob[0..4], .little));
    }
    return 0;
}

pub fn readUnsignedConstant(blob: []const u8, backing_type: []const u8) u64 {
    if (std.mem.eql(u8, backing_type, "u8")) {
        if (blob.len >= 1) return @as(u64, blob[0]);
    } else if (std.mem.eql(u8, backing_type, "u16")) {
        if (blob.len >= 2) return @as(u64, std.mem.readInt(u16, blob[0..2], .little));
    } else if (std.mem.eql(u8, backing_type, "u64")) {
        if (blob.len >= 8) return std.mem.readInt(u64, blob[0..8], .little);
    } else {
        if (blob.len >= 4) return @as(u64, std.mem.readInt(u32, blob[0..4], .little));
    }
    return 0;
}

pub fn customAttributeTypeName(ctx: Context, ca_type: u32) !?[]const u8 {
    const ty = coded.decodeCustomAttributeType(ca_type) catch return null;
    if (ty.table != .MemberRef) return null;
    const mr = try ctx.table_info.readMemberRef(ty.row);
    const parent = coded.decodeMemberRefParent(mr.class) catch return null;
    return switch (parent.table) {
        .TypeRef => blk: {
            const tr = try ctx.table_info.readTypeRef(parent.row);
            break :blk try ctx.heaps.getString(tr.type_name);
        },
        .TypeDef => blk: {
            const td = try ctx.table_info.readTypeDef(parent.row);
            break :blk try ctx.heaps.getString(td.type_name);
        },
        else => null,
    };
}

pub fn decodeCustomAttributeString(blob: []const u8) ?[]const u8 {
    if (blob.len < 3) return null;
    if (blob[0] != 0x01 or blob[1] != 0x00) return null;
    var c = SigCursor{ .data = blob[2..] };
    const len = c.readCompressedUInt() orelse return null;
    if (len == 0xFF) return null;
    if (c.pos + len > c.data.len) return null;
    return c.data[c.pos .. c.pos + len];
}

const std = @import("std");
const coded = @import("coded_index.zig");

pub const TableError = error{
    Truncated,
    MissingTableStream,
    InvalidTableRow,
    UnsupportedTable,
};

pub const TableInfo = struct {
    row_count: u32 = 0,
    row_size: u32 = 0,
    offset: usize = 0,
    present: bool = false,
};

pub const TypeDefRow = struct {
    flags: u32,
    type_name: u32,
    type_namespace: u32,
    extends: u32,
    field_list: u32,
    method_list: u32,
};

pub const MethodDefRow = struct {
    rva: u32,
    impl_flags: u16,
    flags: u16,
    name: u32,
    signature: u32,
    param_list: u32,
};

pub const ParamRow = struct {
    flags: u16,
    sequence: u16,
    name: u32,
};

pub const TypeRefRow = struct {
    resolution_scope: u32,
    type_name: u32,
    type_namespace: u32,
};

pub const MemberRefRow = struct {
    class: u32,
    name: u32,
    signature: u32,
};

pub const CustomAttributeRow = struct {
    parent: u32,
    ca_type: u32,
    value: u32,
};

pub const InterfaceImplRow = struct {
    class: u32,
    interface: u32, // TypeDefOrRef coded index
};

pub const IndexSizes = struct {
    string: u8,
    guid: u8,
    blob: u8,
    tdor: u8,
    resolution_scope: u8,
    member_ref_parent: u8,
    has_constant: u8,
    has_custom_attribute: u8,
    custom_attribute_type: u8,
    has_field_marshal: u8,
    has_decl_security: u8,
    has_semantics: u8,
    method_def_or_ref: u8,
    member_forwarded: u8,
    implementation: u8,
    type_or_method_def: u8,
};

pub const Info = struct {
    data: []const u8,
    heap_sizes: u8,
    valid_mask: u64,
    row_counts: [64]u32,
    tables: [64]TableInfo,
    indexes: IndexSizes,

    pub fn getTable(self: Info, id: coded.TableId) TableInfo {
        return self.tables[@intFromEnum(id)];
    }

    pub fn readTypeDef(self: Info, row: u32) TableError!TypeDefRow {
        const t = self.getTable(.TypeDef);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .TypeDef, row) catch return error.InvalidTableRow;
        return .{
            .flags = c.readU32(),
            .type_name = c.readIdx(self.indexes.string),
            .type_namespace = c.readIdx(self.indexes.string),
            .extends = c.readIdx(self.indexes.tdor),
            .field_list = c.readIdx(simpleSize(self, .Field)),
            .method_list = c.readIdx(simpleSize(self, .MethodDef)),
        };
    }

    pub fn readMethodDef(self: Info, row: u32) TableError!MethodDefRow {
        const t = self.getTable(.MethodDef);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .MethodDef, row) catch return error.InvalidTableRow;
        return .{
            .rva = c.readU32(),
            .impl_flags = c.readU16(),
            .flags = c.readU16(),
            .name = c.readIdx(self.indexes.string),
            .signature = c.readIdx(self.indexes.blob),
            .param_list = c.readIdx(simpleSize(self, .Param)),
        };
    }

    pub fn readParam(self: Info, row: u32) TableError!ParamRow {
        const t = self.getTable(.Param);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .Param, row) catch return error.InvalidTableRow;
        return .{
            .flags = c.readU16(),
            .sequence = c.readU16(),
            .name = c.readIdx(self.indexes.string),
        };
    }

    pub fn readTypeRef(self: Info, row: u32) TableError!TypeRefRow {
        const t = self.getTable(.TypeRef);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .TypeRef, row) catch return error.InvalidTableRow;
        return .{
            .resolution_scope = c.readIdx(self.indexes.resolution_scope),
            .type_name = c.readIdx(self.indexes.string),
            .type_namespace = c.readIdx(self.indexes.string),
        };
    }

    pub fn readMemberRef(self: Info, row: u32) TableError!MemberRefRow {
        const t = self.getTable(.MemberRef);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .MemberRef, row) catch return error.InvalidTableRow;
        return .{
            .class = c.readIdx(self.indexes.member_ref_parent),
            .name = c.readIdx(self.indexes.string),
            .signature = c.readIdx(self.indexes.blob),
        };
    }

    pub fn readCustomAttribute(self: Info, row: u32) TableError!CustomAttributeRow {
        const t = self.getTable(.CustomAttribute);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .CustomAttribute, row) catch return error.InvalidTableRow;
        return .{
            .parent = c.readIdx(self.indexes.has_custom_attribute),
            .ca_type = c.readIdx(self.indexes.custom_attribute_type),
            .value = c.readIdx(self.indexes.blob),
        };
    }

    pub fn readInterfaceImpl(self: Info, row: u32) TableError!InterfaceImplRow {
        const t = self.getTable(.InterfaceImpl);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .InterfaceImpl, row) catch return error.InvalidTableRow;
        return .{
            .class = c.readIdx(simpleSize(self, .TypeDef)),
            .interface = c.readIdx(self.indexes.tdor),
        };
    }
};

pub fn parse(stream_data: []const u8) TableError!Info {
    if (stream_data.len < 24) return error.Truncated;
    if (std.mem.readInt(u32, stream_data[0..4], .little) != 0) return error.UnsupportedTable;

    var cursor: usize = 0;
    cursor += 4; // reserved
    _ = stream_data[cursor]; // major
    cursor += 1;
    _ = stream_data[cursor]; // minor
    cursor += 1;
    const heap_sizes = stream_data[cursor];
    cursor += 1;
    cursor += 1; // reserved

    const valid = std.mem.readInt(u64, stream_data[cursor..][0..8], .little);
    cursor += 8;
    _ = std.mem.readInt(u64, stream_data[cursor..][0..8], .little); // sorted
    cursor += 8;

    var row_counts = std.mem.zeroes([64]u32);
    for (0..64) |i| {
        if ((valid & (@as(u64, 1) << @as(u6, @intCast(i)))) != 0) {
            if (cursor + 4 > stream_data.len) return error.Truncated;
            row_counts[i] = std.mem.readInt(u32, stream_data[cursor..][0..4], .little);
            cursor += 4;
        }
    }

    var out = Info{
        .data = stream_data,
        .heap_sizes = heap_sizes,
        .valid_mask = valid,
        .row_counts = row_counts,
        .tables = [_]TableInfo{.{}} ** 64,
        .indexes = undefined,
    };
    out.indexes = computeIndexSizes(row_counts, heap_sizes);

    var data_off = cursor;
    for (0..64) |i| {
        if ((valid & (@as(u64, 1) << @as(u6, @intCast(i)))) == 0) continue;
        const table_id: coded.TableId = @enumFromInt(i);
        const row_size = try rowSize(table_id, &out);
        const bytes = @as(usize, row_size) * row_counts[i];
        if (data_off + bytes > stream_data.len) return error.Truncated;
        out.tables[i] = .{
            .row_count = row_counts[i],
            .row_size = row_size,
            .offset = data_off,
            .present = true,
        };
        data_off += bytes;
    }

    return out;
}

fn computeIndexSizes(row_counts: [64]u32, heap_sizes: u8) IndexSizes {
    const str_ix: u8 = if ((heap_sizes & 0x01) != 0) 4 else 2;
    const guid_ix: u8 = if ((heap_sizes & 0x02) != 0) 4 else 2;
    const blob_ix: u8 = if ((heap_sizes & 0x04) != 0) 4 else 2;

    return .{
        .string = str_ix,
        .guid = guid_ix,
        .blob = blob_ix,
        .tdor = coded.codedIndexSize(row_counts, 2, &.{ .TypeDef, .TypeRef, .TypeSpec }),
        .resolution_scope = coded.codedIndexSize(row_counts, 2, &.{ .Module, .ModuleRef, .AssemblyRef, .TypeRef }),
        .member_ref_parent = coded.codedIndexSize(row_counts, 3, &.{ .TypeDef, .TypeRef, .ModuleRef, .MethodDef, .TypeSpec }),
        .has_constant = coded.codedIndexSize(row_counts, 2, &.{ .Field, .Param, .Property }),
        .has_custom_attribute = coded.codedIndexSize(row_counts, 5, &.{
            .MethodDef,    .Field,        .TypeRef,          .TypeDef,       .Param,                  .InterfaceImpl, .MemberRef, .Module,
            .DeclSecurity, .Property,     .Event,            .StandAloneSig, .ModuleRef,              .TypeSpec,      .Assembly,  .AssemblyRef,
            .File,         .ExportedType, .ManifestResource, .GenericParam,  .GenericParamConstraint, .MethodSpec,
        }),
        .custom_attribute_type = coded.codedIndexSize(row_counts, 3, &.{ .MethodDef, .MemberRef }),
        .has_field_marshal = coded.codedIndexSize(row_counts, 1, &.{ .Field, .Param }),
        .has_decl_security = coded.codedIndexSize(row_counts, 2, &.{ .TypeDef, .MethodDef, .Assembly }),
        .has_semantics = coded.codedIndexSize(row_counts, 1, &.{ .Event, .Property }),
        .method_def_or_ref = coded.codedIndexSize(row_counts, 1, &.{ .MethodDef, .MemberRef }),
        .member_forwarded = coded.codedIndexSize(row_counts, 1, &.{ .Field, .MethodDef }),
        .implementation = coded.codedIndexSize(row_counts, 2, &.{ .File, .AssemblyRef, .ExportedType }),
        .type_or_method_def = coded.codedIndexSize(row_counts, 1, &.{ .TypeDef, .MethodDef }),
    };
}

fn rowSize(id: coded.TableId, info: *const Info) TableError!u32 {
    const s = info.indexes;
    const size = switch (id) {
        .Module => 2 + s.string + s.guid + s.guid + s.guid,
        .TypeRef => s.resolution_scope + s.string + s.string,
        .TypeDef => 4 + s.string + s.string + s.tdor + simpleSize(info.*, .Field) + simpleSize(info.*, .MethodDef),
        .FieldPtr => simpleSize(info.*, .Field),
        .Field => 2 + s.string + s.blob,
        .MethodPtr => simpleSize(info.*, .MethodDef),
        .MethodDef => 4 + 2 + 2 + s.string + s.blob + simpleSize(info.*, .Param),
        .ParamPtr => simpleSize(info.*, .Param),
        .Param => 2 + 2 + s.string,
        .InterfaceImpl => simpleSize(info.*, .TypeDef) + s.tdor,
        .MemberRef => s.member_ref_parent + s.string + s.blob,
        .Constant => 2 + s.has_constant + s.blob,
        .CustomAttribute => s.has_custom_attribute + s.custom_attribute_type + s.blob,
        .FieldMarshal => s.has_field_marshal + s.blob,
        .DeclSecurity => 2 + s.has_decl_security + s.blob,
        .ClassLayout => 2 + 4 + simpleSize(info.*, .TypeDef),
        .FieldLayout => 4 + simpleSize(info.*, .Field),
        .StandAloneSig => s.blob,
        .EventMap => simpleSize(info.*, .TypeDef) + simpleSize(info.*, .Event),
        .EventPtr => simpleSize(info.*, .Event),
        .Event => 2 + s.string + s.tdor,
        .PropertyMap => simpleSize(info.*, .TypeDef) + simpleSize(info.*, .Property),
        .PropertyPtr => simpleSize(info.*, .Property),
        .Property => 2 + s.string + s.blob,
        .MethodSemantics => 2 + simpleSize(info.*, .MethodDef) + s.has_semantics,
        .MethodImpl => simpleSize(info.*, .TypeDef) + s.method_def_or_ref + s.method_def_or_ref,
        .ModuleRef => s.string,
        .TypeSpec => s.blob,
        .ImplMap => 2 + s.member_forwarded + s.string + simpleSize(info.*, .ModuleRef),
        .FieldRVA => 4 + simpleSize(info.*, .Field),
        .ENCLog => 8,
        .ENCMap => 4,
        .Assembly => 4 + 2 + 2 + 2 + 2 + 4 + s.blob + s.string + s.string,
        .AssemblyProcessor => 4,
        .AssemblyOS => 12,
        .AssemblyRef => 2 + 2 + 2 + 2 + 4 + s.blob + s.string + s.string + s.blob,
        .AssemblyRefProcessor => 4 + simpleSize(info.*, .AssemblyRef),
        .AssemblyRefOS => 12 + simpleSize(info.*, .AssemblyRef),
        .File => 4 + s.string + s.blob,
        .ExportedType => 4 + 4 + s.string + s.string + s.implementation,
        .ManifestResource => 4 + 4 + s.string + s.implementation,
        .NestedClass => simpleSize(info.*, .TypeDef) + simpleSize(info.*, .TypeDef),
        .GenericParam => 2 + 2 + s.type_or_method_def + s.string,
        .MethodSpec => s.method_def_or_ref + s.blob,
        .GenericParamConstraint => simpleSize(info.*, .GenericParam) + s.tdor,
    };
    return size;
}

fn simpleSize(info: Info, id: coded.TableId) u8 {
    return if (info.row_counts[@intFromEnum(id)] < 0x10000) 2 else 4;
}

const Cursor = struct {
    data: []const u8,
    pos: usize = 0,

    fn readU16(self: *Cursor) u16 {
        const out = std.mem.readInt(u16, self.data[self.pos..][0..2], .little);
        self.pos += 2;
        return out;
    }

    fn readU32(self: *Cursor) u32 {
        const out = std.mem.readInt(u32, self.data[self.pos..][0..4], .little);
        self.pos += 4;
        return out;
    }

    fn readIdx(self: *Cursor, width: u8) u32 {
        return switch (width) {
            2 => self.readU16(),
            4 => self.readU32(),
            else => unreachable,
        };
    }
};

fn rowCursor(info: Info, id: coded.TableId, row: u32) TableError!Cursor {
    const t = info.getTable(id);
    if (!t.present or row == 0 or row > t.row_count) return error.InvalidTableRow;
    const start = t.offset + (@as(usize, row - 1) * t.row_size);
    const end = start + t.row_size;
    if (end > info.data.len) return error.Truncated;
    return .{ .data = info.data[start..end] };
}

test "parse accepts minimal valid metadata table stream with no tables" {
    var d: [24]u8 = .{0} ** 24;
    // reserved=0 at [0..4]
    d[4] = 2; // major
    d[5] = 0; // minor
    d[6] = 0; // heap sizes
    d[7] = 1; // reserved
    // valid mask = 0, sorted = 0
    const info = try parse(&d);
    try std.testing.expectEqual(@as(u64, 0), info.valid_mask);
    try std.testing.expectEqual(@as(u32, 0), info.getTable(.TypeDef).row_count);
}

test "parse rejects non-zero reserved field" {
    var d: [24]u8 = .{0} ** 24;
    d[0] = 1;
    try std.testing.expectError(error.UnsupportedTable, parse(&d));
}

test "parse detects truncation when row count table is incomplete" {
    var d: [24]u8 = .{0} ** 24;
    // valid bit 2 (TypeDef) set, but no room for row count u32.
    std.mem.writeInt(u64, d[8..][0..8], (@as(u64, 1) << 2), .little);
    try std.testing.expectError(error.Truncated, parse(&d));
}

test "parse and read single TypeDef row" {
    // Header(24) + one row-count(4) + one TypeDef row(14)
    var d: [42]u8 = .{0} ** 42;
    d[4] = 2; // major
    d[5] = 0; // minor
    d[6] = 0; // heap sizes => 2-byte heap indexes
    d[7] = 1;

    std.mem.writeInt(u64, d[8..][0..8], (@as(u64, 1) << 2), .little); // valid TypeDef
    std.mem.writeInt(u64, d[16..][0..8], 0, .little); // sorted
    std.mem.writeInt(u32, d[24..][0..4], 1, .little); // TypeDef row count

    // Row starts at 28
    const row: usize = 28;
    std.mem.writeInt(u32, d[row..][0..4], 0x11223344, .little); // flags
    std.mem.writeInt(u16, d[row + 4 ..][0..2], 1, .little); // type_name
    std.mem.writeInt(u16, d[row + 6 ..][0..2], 2, .little); // type_namespace
    std.mem.writeInt(u16, d[row + 8 ..][0..2], 3, .little); // extends
    std.mem.writeInt(u16, d[row + 10 ..][0..2], 4, .little); // field_list
    std.mem.writeInt(u16, d[row + 12 ..][0..2], 5, .little); // method_list

    const info = try parse(&d);
    const td = try info.readTypeDef(1);
    try std.testing.expectEqual(@as(u32, 0x11223344), td.flags);
    try std.testing.expectEqual(@as(u32, 1), td.type_name);
    try std.testing.expectEqual(@as(u32, 2), td.type_namespace);
    try std.testing.expectEqual(@as(u32, 3), td.extends);
    try std.testing.expectEqual(@as(u32, 4), td.field_list);
    try std.testing.expectEqual(@as(u32, 5), td.method_list);
}

test "readTypeDef invalid row returns error" {
    var d: [24]u8 = .{0} ** 24;
    const info = try parse(&d);
    try std.testing.expectError(error.InvalidTableRow, info.readTypeDef(1));
}

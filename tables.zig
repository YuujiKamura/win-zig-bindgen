const std = @import("std");
const coded = @import("coded_index.zig");
const TableId = coded.TableId;

pub const TableError = error{
    Truncated,
    UnsupportedTable,
    InvalidTableRow,
    MissingTable,
    InvalidCodedIndex,
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

pub const TableInfo = struct {
    row_count: u32 = 0,
    row_size: u8 = 0,
    offset: usize = 0,
    present: bool = false,
};

pub const Info = struct {
    data: []const u8,
    heap_sizes: u8,
    valid_mask: u64,
    row_counts: [64]u32,
    tables: [64]TableInfo,
    indexes: IndexSizes,

    pub fn getTable(self: Info, id: TableId) TableInfo {
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

    pub fn readField(self: Info, row: u32) TableError!FieldRow {
        const t = self.getTable(.Field);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .Field, row) catch return error.InvalidTableRow;
        return .{
            .flags = c.readU16(),
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

    pub fn readInterfaceImpl(self: Info, row: u32) TableError!InterfaceImplRow {
        const t = self.getTable(.InterfaceImpl);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .InterfaceImpl, row) catch return error.InvalidTableRow;
        return .{
            .class = c.readIdx(simpleSize(self, .TypeDef)),
            .interface = c.readIdx(self.indexes.tdor),
        };
    }

    pub fn readTypeSpec(self: Info, row: u32) TableError!TypeSpecRow {
        const t = self.getTable(.TypeSpec);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .TypeSpec, row) catch return error.InvalidTableRow;
        return .{
            .signature = c.readIdx(self.indexes.blob),
        };
    }

    pub fn readConstant(self: Info, row: u32) TableError!ConstantRow {
        const t = self.getTable(.Constant);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .Constant, row) catch return error.InvalidTableRow;
        return .{
            .type = c.readU16(),
            .parent = c.readIdx(self.indexes.has_constant),
            .value = c.readIdx(self.indexes.blob),
        };
    }

    pub fn readProperty(self: Info, row: u32) TableError!PropertyRow {
        const t = self.getTable(.Property);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .Property, row) catch return error.InvalidTableRow;
        return .{
            .flags = c.readU16(),
            .name = c.readIdx(self.indexes.string),
            .signature = c.readIdx(self.indexes.blob),
        };
    }

    pub fn readPropertyMap(self: Info, row: u32) TableError!PropertyMapRow {
        const t = self.getTable(.PropertyMap);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .PropertyMap, row) catch return error.InvalidTableRow;
        return .{
            .parent = c.readIdx(simpleSize(self, .TypeDef)),
            .property_list = c.readIdx(simpleSize(self, .Property)),
        };
    }

    pub fn readEvent(self: Info, row: u32) TableError!EventRow {
        const t = self.getTable(.Event);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .Event, row) catch return error.InvalidTableRow;
        return .{
            .event_flags = c.readU16(),
            .name = c.readIdx(self.indexes.string),
            .event_type = c.readIdx(self.indexes.tdor),
        };
    }

    pub fn readEventMap(self: Info, row: u32) TableError!EventMapRow {
        const t = self.getTable(.EventMap);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .EventMap, row) catch return error.InvalidTableRow;
        return .{
            .parent = c.readIdx(simpleSize(self, .TypeDef)),
            .event_list = c.readIdx(simpleSize(self, .Event)),
        };
    }

    pub fn readMethodSemantics(self: Info, row: u32) TableError!MethodSemanticsRow {
        const t = self.getTable(.MethodSemantics);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .MethodSemantics, row) catch return error.InvalidTableRow;
        return .{
            .semantics = c.readU16(),
            .method = c.readIdx(simpleSize(self, .MethodDef)),
            .association = c.readIdx(self.indexes.has_semantics),
        };
    }

    pub fn readNestedClass(self: Info, row: u32) TableError!NestedClassRow {
        const t = self.getTable(.NestedClass);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .NestedClass, row) catch return error.InvalidTableRow;
        return .{
            .nested_class = c.readIdx(simpleSize(self, .TypeDef)),
            .enclosing_class = c.readIdx(simpleSize(self, .TypeDef)),
        };
    }

    pub fn readGenericParam(self: Info, row: u32) TableError!GenericParamRow {
        const t = self.getTable(.GenericParam);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .GenericParam, row) catch return error.InvalidTableRow;
        return .{
            .number = c.readU16(),
            .flags = c.readU16(),
            .owner = c.readIdx(self.indexes.type_or_method_def),
            .name = c.readIdx(self.indexes.string),
        };
    }

    pub fn readMethodSpec(self: Info, row: u32) TableError!MethodSpecRow {
        const t = self.getTable(.MethodSpec);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .MethodSpec, row) catch return error.InvalidTableRow;
        return .{
            .method = c.readIdx(self.indexes.method_def_or_ref),
            .instantiation = c.readIdx(self.indexes.blob),
        };
    }

    pub fn readClassLayout(self: Info, row: u32) TableError!ClassLayoutRow {
        const t = self.getTable(.ClassLayout);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .ClassLayout, row) catch return error.InvalidTableRow;
        return .{
            .packing_size = c.readU16(),
            .class_size = c.readU32(),
            .parent = c.readIdx(simpleSize(self, .TypeDef)),
        };
    }

    pub fn readImplMap(self: Info, row: u32) TableError!ImplMapRow {
        const t = self.getTable(.ImplMap);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .ImplMap, row) catch return error.InvalidTableRow;
        return .{
            .mapping_flags = c.readU16(),
            .member_forwarded = c.readIdx(self.indexes.member_forwarded),
            .import_name = c.readIdx(self.indexes.string),
            .import_scope = c.readIdx(simpleSize(self, .ModuleRef)),
        };
    }

    pub fn readFieldRVA(self: Info, row: u32) TableError!FieldRVARow {
        const t = self.getTable(.FieldRVA);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .FieldRVA, row) catch return error.InvalidTableRow;
        return .{
            .rva = c.readU32(),
            .field = c.readIdx(simpleSize(self, .Field)),
        };
    }

    pub fn readModuleRef(self: Info, row: u32) TableError!ModuleRefRow {
        const t = self.getTable(.ModuleRef);
        if (row == 0 or row > t.row_count) return error.InvalidTableRow;
        var c = rowCursor(self, .ModuleRef, row) catch return error.InvalidTableRow;
        return .{
            .name = c.readIdx(self.indexes.string),
        };
    }
};

pub fn parse(stream_data: []const u8) TableError!Info {
    if (stream_data.len < 24) return error.Truncated;

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
        const table_id: TableId = @enumFromInt(i);
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
        .has_custom_attribute = coded.codedIndexSize(row_counts, 5, &.{ .MethodDef, .Field, .TypeRef, .TypeDef, .Param, .InterfaceImpl, .MemberRef, .Module, .DeclSecurity, .Property, .Event, .StandAloneSig, .ModuleRef, .TypeSpec, .Assembly, .AssemblyRef, .File, .ExportedType, .ManifestResource, .GenericParam, .GenericParamConstraint, .MethodSpec }),
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

fn simpleSize(info: Info, id: TableId) u8 {
    return if (info.row_counts[@intFromEnum(id)] < 65536) 2 else 4;
}

fn rowSize(id: TableId, info: *const Info) TableError!u8 {
    const s = info.indexes;
    const size: u32 = switch (id) {
        .Module => 2 + s.string + s.guid + s.guid + s.guid,
        .TypeRef => s.resolution_scope + s.string + s.string,
        .TypeDef => 4 + s.string + s.string + s.tdor + simpleSize(info.*, .Field) + simpleSize(info.*, .MethodDef),
        .Field => 2 + s.string + s.blob,
        .MethodDef => 4 + 2 + 2 + s.string + s.blob + simpleSize(info.*, .Param),
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
        .Event => 2 + s.string + s.tdor,
        .PropertyMap => simpleSize(info.*, .TypeDef) + simpleSize(info.*, .Property),
        .Property => 2 + s.string + s.blob,
        .MethodSemantics => 2 + simpleSize(info.*, .MethodDef) + s.has_semantics,
        .MethodImpl => simpleSize(info.*, .TypeDef) + s.method_def_or_ref + s.method_def_or_ref,
        .ModuleRef => s.string,
        .TypeSpec => s.blob,
        .ImplMap => 2 + s.member_forwarded + s.string + simpleSize(info.*, .ModuleRef),
        .FieldRVA => 4 + simpleSize(info.*, .Field),
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
        else => return error.UnsupportedTable,
    };
    return @intCast(size);
}

const Cursor = struct {
    data: []const u8,
    pos: usize,

    fn readU16(self: *Cursor) u16 {
        const v = std.mem.readInt(u16, self.data[self.pos..][0..2], .little);
        self.pos += 2;
        return v;
    }

    fn readU32(self: *Cursor) u32 {
        const v = std.mem.readInt(u32, self.data[self.pos..][0..4], .little);
        self.pos += 4;
        return v;
    }

    fn readIdx(self: *Cursor, size: u8) u32 {
        if (size == 2) {
            return self.readU16();
        } else {
            return self.readU32();
        }
    }
};

fn rowCursor(info: Info, id: TableId, row: u32) !Cursor {
    const t = info.getTable(id);
    return Cursor{
        .data = info.data,
        .pos = t.offset + (row - 1) * t.row_size,
    };
}

pub const TypeDefRow = struct {
    flags: u32,
    type_name: u32,
    type_namespace: u32,
    extends: u32,
    field_list: u32,
    method_list: u32,
};

pub const TypeRefRow = struct {
    resolution_scope: u32,
    type_name: u32,
    type_namespace: u32,
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

pub const FieldRow = struct {
    flags: u16,
    name: u32,
    signature: u32,
};

pub const CustomAttributeRow = struct {
    parent: u32,
    ca_type: u32,
    value: u32,
};

pub const MemberRefRow = struct {
    class: u32,
    name: u32,
    signature: u32,
};

pub const InterfaceImplRow = struct {
    class: u32,
    interface: u32,
};

pub const TypeSpecRow = struct {
    signature: u32,
};

pub const ConstantRow = struct {
    type: u16,
    parent: u32,
    value: u32,
};

pub const PropertyRow = struct {
    flags: u16,
    name: u32,
    signature: u32,
};

pub const PropertyMapRow = struct {
    parent: u32,
    property_list: u32,
};

pub const EventRow = struct {
    event_flags: u16,
    name: u32,
    event_type: u32,
};

pub const EventMapRow = struct {
    parent: u32,
    event_list: u32,
};

pub const MethodSemanticsRow = struct {
    semantics: u16,
    method: u32,
    association: u32,
};

pub const NestedClassRow = struct {
    nested_class: u32,
    enclosing_class: u32,
};

pub const GenericParamRow = struct {
    number: u16,
    flags: u16,
    owner: u32,
    name: u32,
};

pub const MethodSpecRow = struct {
    method: u32,
    instantiation: u32,
};

pub const ClassLayoutRow = struct {
    packing_size: u16,
    class_size: u32,
    parent: u32,
};

pub const ImplMapRow = struct {
    mapping_flags: u16,
    member_forwarded: u32,
    import_name: u32,
    import_scope: u32,
};

pub const FieldRVARow = struct {
    rva: u32,
    field: u32,
};

pub const ModuleRefRow = struct {
    name: u32,
};

test "simpleSize uses row_counts not tables for large row counts" {
    // Regression test for the bug where simpleSize() used info.tables[id].row_count
    // (which could be 0/uninitialized during parse) instead of info.row_counts[id].
    // With Param >= 65536, simpleSize must return 4.
    var info = Info{
        .data = &[_]u8{},
        .heap_sizes = 0,
        .valid_mask = 0,
        .row_counts = std.mem.zeroes([64]u32),
        .tables = [_]TableInfo{.{}} ** 64,
        .indexes = undefined,
    };
    // Param (table 8) with 78401 rows (>= 65536)
    info.row_counts[@intFromEnum(coded.TableId.Param)] = 78401;
    try std.testing.expectEqual(@as(u8, 4), simpleSize(info, .Param));

    // Below threshold → 2
    info.row_counts[@intFromEnum(coded.TableId.Param)] = 100;
    try std.testing.expectEqual(@as(u8, 2), simpleSize(info, .Param));

    // Boundary: exactly 65536 → 4
    info.row_counts[@intFromEnum(coded.TableId.Param)] = 65536;
    try std.testing.expectEqual(@as(u8, 4), simpleSize(info, .Param));

    // Boundary: 65535 → 2
    info.row_counts[@intFromEnum(coded.TableId.Param)] = 65535;
    try std.testing.expectEqual(@as(u8, 2), simpleSize(info, .Param));
}

test "readFieldRVA decodes a single row" {
    var row_data = [_]u8{ 0x78, 0x56, 0x34, 0x12, 0x09, 0x00 };
    var tables_arr = [_]TableInfo{.{}} ** 64;
    tables_arr[@intFromEnum(TableId.FieldRVA)] = .{
        .row_count = 1,
        .row_size = 6,
        .offset = 0,
        .present = true,
    };

    var info = Info{
        .data = &row_data,
        .heap_sizes = 0,
        .valid_mask = 0,
        .row_counts = std.mem.zeroes([64]u32),
        .tables = tables_arr,
        .indexes = undefined,
    };
    info.row_counts[@intFromEnum(TableId.Field)] = 10;

    const row = try info.readFieldRVA(1);
    try std.testing.expectEqual(@as(u32, 0x12345678), row.rva);
    try std.testing.expectEqual(@as(u32, 9), row.field);
}

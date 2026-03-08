const std = @import("std");

pub const TableId = enum(u8) {
    Module = 0,
    TypeRef = 1,
    TypeDef = 2,
    FieldPtr = 3,
    Field = 4,
    MethodPtr = 5,
    MethodDef = 6,
    ParamPtr = 7,
    Param = 8,
    InterfaceImpl = 9,
    MemberRef = 10,
    Constant = 11,
    CustomAttribute = 12,
    FieldMarshal = 13,
    DeclSecurity = 14,
    ClassLayout = 15,
    FieldLayout = 16,
    StandAloneSig = 17,
    EventMap = 18,
    EventPtr = 19,
    Event = 20,
    PropertyMap = 21,
    PropertyPtr = 22,
    Property = 23,
    MethodSemantics = 24,
    MethodImpl = 25,
    ModuleRef = 26,
    TypeSpec = 27,
    ImplMap = 28,
    FieldRVA = 29,
    ENCLog = 30,
    ENCMap = 31,
    Assembly = 32,
    AssemblyProcessor = 33,
    AssemblyOS = 34,
    AssemblyRef = 35,
    AssemblyRefProcessor = 36,
    AssemblyRefOS = 37,
    File = 38,
    ExportedType = 39,
    ManifestResource = 40,
    NestedClass = 41,
    GenericParam = 42,
    MethodSpec = 43,
    GenericParamConstraint = 44,
};

pub const Decoded = struct {
    table: TableId,
    row: u32,
};

pub const IndexError = error{InvalidTag};

pub fn codedIndexSize(row_counts: [64]u32, tag_bits: u8, tables: []const TableId) u8 {
    const max_small_rows: u32 = (@as(u32, 1) << (@as(u5, @intCast(16 - tag_bits)))) - 1;
    var max_rows: u32 = 0;
    for (tables) |table| {
        max_rows = @max(max_rows, row_counts[@intFromEnum(table)]);
    }
    return if (max_rows <= max_small_rows) 2 else 4;
}

pub fn decodeTypeDefOrRef(raw: u32) IndexError!Decoded {
    const tag = raw & 0x3;
    const row = raw >> 2;
    return switch (tag) {
        0 => .{ .table = .TypeDef, .row = row },
        1 => .{ .table = .TypeRef, .row = row },
        2 => .{ .table = .TypeSpec, .row = row },
        else => error.InvalidTag,
    };
}

pub fn decodeHasConstant(raw: u32) IndexError!Decoded {
    const tag = raw & 0x3;
    const row = raw >> 2;
    return switch (tag) {
        0 => .{ .table = .Field, .row = row },
        1 => .{ .table = .Param, .row = row },
        2 => .{ .table = .Property, .row = row },
        else => error.InvalidTag,
    };
}

pub fn decodeHasCustomAttribute(raw: u32) IndexError!Decoded {
    const tag = raw & 0x1f;
    const row = raw >> 5;
    return switch (tag) {
        0 => .{ .table = .MethodDef, .row = row },
        1 => .{ .table = .Field, .row = row },
        2 => .{ .table = .TypeRef, .row = row },
        3 => .{ .table = .TypeDef, .row = row },
        4 => .{ .table = .Param, .row = row },
        5 => .{ .table = .InterfaceImpl, .row = row },
        6 => .{ .table = .MemberRef, .row = row },
        7 => .{ .table = .Module, .row = row },
        8 => .{ .table = .DeclSecurity, .row = row },
        9 => .{ .table = .Property, .row = row },
        10 => .{ .table = .Event, .row = row },
        11 => .{ .table = .StandAloneSig, .row = row },
        12 => .{ .table = .ModuleRef, .row = row },
        13 => .{ .table = .TypeSpec, .row = row },
        14 => .{ .table = .Assembly, .row = row },
        15 => .{ .table = .AssemblyRef, .row = row },
        16 => .{ .table = .File, .row = row },
        17 => .{ .table = .ExportedType, .row = row },
        18 => .{ .table = .ManifestResource, .row = row },
        19 => .{ .table = .GenericParam, .row = row },
        20 => .{ .table = .GenericParamConstraint, .row = row },
        21 => .{ .table = .MethodSpec, .row = row },
        else => error.InvalidTag,
    };
}

pub fn decodeCustomAttributeType(raw: u32) IndexError!Decoded {
    const tag = raw & 0x7;
    const row = raw >> 3;
    return switch (tag) {
        2 => .{ .table = .MethodDef, .row = row },
        3 => .{ .table = .MemberRef, .row = row },
        else => error.InvalidTag,
    };
}

pub fn decodeMemberRefParent(raw: u32) IndexError!Decoded {
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

pub fn decodeHasFieldMarshal(raw: u32) IndexError!Decoded {
    const tag = raw & 0x1;
    const row = raw >> 1;
    return switch (tag) {
        0 => .{ .table = .Field, .row = row },
        1 => .{ .table = .Param, .row = row },
        else => error.InvalidTag,
    };
}

pub fn decodeHasDeclSecurity(raw: u32) IndexError!Decoded {
    const tag = raw & 0x3;
    const row = raw >> 2;
    return switch (tag) {
        0 => .{ .table = .TypeDef, .row = row },
        1 => .{ .table = .MethodDef, .row = row },
        2 => .{ .table = .Assembly, .row = row },
        else => error.InvalidTag,
    };
}

pub fn decodeImplementation(raw: u32) IndexError!Decoded {
    const tag = raw & 0x3;
    const row = raw >> 2;
    return switch (tag) {
        0 => .{ .table = .File, .row = row },
        1 => .{ .table = .AssemblyRef, .row = row },
        2 => .{ .table = .ExportedType, .row = row },
        else => error.InvalidTag,
    };
}

pub fn decodeMemberForwarded(raw: u32) IndexError!Decoded {
    const tag = raw & 0x1;
    const row = raw >> 1;
    return switch (tag) {
        0 => .{ .table = .Field, .row = row },
        1 => .{ .table = .MethodDef, .row = row },
        else => error.InvalidTag,
    };
}

pub fn decodeMethodDefOrRef(raw: u32) IndexError!Decoded {
    const tag = raw & 0x1;
    const row = raw >> 1;
    return switch (tag) {
        0 => .{ .table = .MethodDef, .row = row },
        1 => .{ .table = .MemberRef, .row = row },
        else => error.InvalidTag,
    };
}

pub fn decodeHasSemantics(raw: u32) IndexError!Decoded {
    const tag = raw & 0x1;
    const row = raw >> 1;
    return switch (tag) {
        0 => .{ .table = .Event, .row = row },
        1 => .{ .table = .Property, .row = row },
        else => error.InvalidTag,
    };
}

pub fn decodeResolutionScope(raw: u32) IndexError!Decoded {
    const tag = raw & 0x3;
    const row = raw >> 2;
    return switch (tag) {
        0 => .{ .table = .Module, .row = row },
        1 => .{ .table = .ModuleRef, .row = row },
        2 => .{ .table = .AssemblyRef, .row = row },
        3 => .{ .table = .TypeRef, .row = row },
        else => error.InvalidTag,
    };
}

pub fn decodeTypeOrMethodDef(raw: u32) IndexError!Decoded {
    const tag = raw & 0x1;
    const row = raw >> 1;
    return switch (tag) {
        0 => .{ .table = .TypeDef, .row = row },
        1 => .{ .table = .MethodDef, .row = row },
        else => error.InvalidTag,
    };
}

// --- Unit tests ---

const testing = std.testing;

test "decodeTypeDefOrRef" {
    // tag=0 (TypeDef), row=5 => raw = (5 << 2) | 0 = 20
    const d0 = try decodeTypeDefOrRef(20);
    try testing.expectEqual(TableId.TypeDef, d0.table);
    try testing.expectEqual(@as(u32, 5), d0.row);
    // tag=1 (TypeRef), row=3 => raw = (3 << 2) | 1 = 13
    const d1 = try decodeTypeDefOrRef(13);
    try testing.expectEqual(TableId.TypeRef, d1.table);
    try testing.expectEqual(@as(u32, 3), d1.row);
    // tag=2 (TypeSpec), row=1 => raw = (1 << 2) | 2 = 6
    const d2 = try decodeTypeDefOrRef(6);
    try testing.expectEqual(TableId.TypeSpec, d2.table);
    try testing.expectEqual(@as(u32, 1), d2.row);
    // tag=3 => invalid
    try testing.expectError(error.InvalidTag, decodeTypeDefOrRef(3));
}

test "decodeHasConstant" {
    // tag=0 (Field), row=7 => raw = (7 << 2) | 0 = 28
    const d0 = try decodeHasConstant(28);
    try testing.expectEqual(TableId.Field, d0.table);
    try testing.expectEqual(@as(u32, 7), d0.row);
    // tag=1 (Param), row=2 => raw = (2 << 2) | 1 = 9
    const d1 = try decodeHasConstant(9);
    try testing.expectEqual(TableId.Param, d1.table);
    try testing.expectEqual(@as(u32, 2), d1.row);
    // tag=2 (Property), row=4 => raw = (4 << 2) | 2 = 18
    const d2 = try decodeHasConstant(18);
    try testing.expectEqual(TableId.Property, d2.table);
    try testing.expectEqual(@as(u32, 4), d2.row);
    // tag=3 => invalid
    try testing.expectError(error.InvalidTag, decodeHasConstant(3));
}

test "decodeCustomAttributeType" {
    // tag=2 (MethodDef), row=10 => raw = (10 << 3) | 2 = 82
    const d0 = try decodeCustomAttributeType(82);
    try testing.expectEqual(TableId.MethodDef, d0.table);
    try testing.expectEqual(@as(u32, 10), d0.row);
    // tag=3 (MemberRef), row=5 => raw = (5 << 3) | 3 = 43
    const d1 = try decodeCustomAttributeType(43);
    try testing.expectEqual(TableId.MemberRef, d1.table);
    try testing.expectEqual(@as(u32, 5), d1.row);
    // tag=0 => invalid
    try testing.expectError(error.InvalidTag, decodeCustomAttributeType(0));
}

test "decodeMemberRefParent" {
    // tag=0 (TypeDef), row=3 => raw = (3 << 3) | 0 = 24
    const d0 = try decodeMemberRefParent(24);
    try testing.expectEqual(TableId.TypeDef, d0.table);
    try testing.expectEqual(@as(u32, 3), d0.row);
    // tag=4 (TypeSpec), row=2 => raw = (2 << 3) | 4 = 20
    const d4 = try decodeMemberRefParent(20);
    try testing.expectEqual(TableId.TypeSpec, d4.table);
    try testing.expectEqual(@as(u32, 2), d4.row);
    // tag=5 => invalid
    try testing.expectError(error.InvalidTag, decodeMemberRefParent(5));
}

test "decodeHasSemantics" {
    // tag=0 (Event), row=6 => raw = (6 << 1) | 0 = 12
    const d0 = try decodeHasSemantics(12);
    try testing.expectEqual(TableId.Event, d0.table);
    try testing.expectEqual(@as(u32, 6), d0.row);
    // tag=1 (Property), row=3 => raw = (3 << 1) | 1 = 7
    const d1 = try decodeHasSemantics(7);
    try testing.expectEqual(TableId.Property, d1.table);
    try testing.expectEqual(@as(u32, 3), d1.row);
}

test "decodeResolutionScope" {
    // tag=0 (Module), row=1 => raw = (1 << 2) | 0 = 4
    const d0 = try decodeResolutionScope(4);
    try testing.expectEqual(TableId.Module, d0.table);
    try testing.expectEqual(@as(u32, 1), d0.row);
    // tag=1 (ModuleRef), row=2 => raw = (2 << 2) | 1 = 9
    const d1 = try decodeResolutionScope(9);
    try testing.expectEqual(TableId.ModuleRef, d1.table);
    try testing.expectEqual(@as(u32, 2), d1.row);
    // tag=2 (AssemblyRef), row=5 => raw = (5 << 2) | 2 = 22
    const d2 = try decodeResolutionScope(22);
    try testing.expectEqual(TableId.AssemblyRef, d2.table);
    try testing.expectEqual(@as(u32, 5), d2.row);
    // tag=3 (TypeRef), row=4 => raw = (4 << 2) | 3 = 19
    const d3 = try decodeResolutionScope(19);
    try testing.expectEqual(TableId.TypeRef, d3.table);
    try testing.expectEqual(@as(u32, 4), d3.row);
}

test "decodeMemberForwarded" {
    // tag=0 (Field), row=8 => raw = (8 << 1) | 0 = 16
    const d0 = try decodeMemberForwarded(16);
    try testing.expectEqual(TableId.Field, d0.table);
    try testing.expectEqual(@as(u32, 8), d0.row);
    // tag=1 (MethodDef), row=4 => raw = (4 << 1) | 1 = 9
    const d1 = try decodeMemberForwarded(9);
    try testing.expectEqual(TableId.MethodDef, d1.table);
    try testing.expectEqual(@as(u32, 4), d1.row);
}

test "decodeMethodDefOrRef" {
    // tag=0 (MethodDef), row=10 => raw = (10 << 1) | 0 = 20
    const d0 = try decodeMethodDefOrRef(20);
    try testing.expectEqual(TableId.MethodDef, d0.table);
    try testing.expectEqual(@as(u32, 10), d0.row);
    // tag=1 (MemberRef), row=7 => raw = (7 << 1) | 1 = 15
    const d1 = try decodeMethodDefOrRef(15);
    try testing.expectEqual(TableId.MemberRef, d1.table);
    try testing.expectEqual(@as(u32, 7), d1.row);
}

test "decodeTypeOrMethodDef" {
    // tag=0 (TypeDef), row=12 => raw = (12 << 1) | 0 = 24
    const d0 = try decodeTypeOrMethodDef(24);
    try testing.expectEqual(TableId.TypeDef, d0.table);
    try testing.expectEqual(@as(u32, 12), d0.row);
    // tag=1 (MethodDef), row=9 => raw = (9 << 1) | 1 = 19
    const d1 = try decodeTypeOrMethodDef(19);
    try testing.expectEqual(TableId.MethodDef, d1.table);
    try testing.expectEqual(@as(u32, 9), d1.row);
}

test "decodeHasFieldMarshal" {
    // tag=0 (Field), row=3 => raw = (3 << 1) | 0 = 6
    const d0 = try decodeHasFieldMarshal(6);
    try testing.expectEqual(TableId.Field, d0.table);
    try testing.expectEqual(@as(u32, 3), d0.row);
    // tag=1 (Param), row=5 => raw = (5 << 1) | 1 = 11
    const d1 = try decodeHasFieldMarshal(11);
    try testing.expectEqual(TableId.Param, d1.table);
    try testing.expectEqual(@as(u32, 5), d1.row);
}

test "decodeHasDeclSecurity" {
    // tag=0 (TypeDef), row=2 => raw = (2 << 2) | 0 = 8
    const d0 = try decodeHasDeclSecurity(8);
    try testing.expectEqual(TableId.TypeDef, d0.table);
    try testing.expectEqual(@as(u32, 2), d0.row);
    // tag=2 (Assembly), row=1 => raw = (1 << 2) | 2 = 6
    const d2 = try decodeHasDeclSecurity(6);
    try testing.expectEqual(TableId.Assembly, d2.table);
    try testing.expectEqual(@as(u32, 1), d2.row);
    // tag=3 => invalid
    try testing.expectError(error.InvalidTag, decodeHasDeclSecurity(3));
}

test "decodeImplementation" {
    // tag=0 (File), row=2 => raw = (2 << 2) | 0 = 8
    const d0 = try decodeImplementation(8);
    try testing.expectEqual(TableId.File, d0.table);
    try testing.expectEqual(@as(u32, 2), d0.row);
    // tag=1 (AssemblyRef), row=5 => raw = (5 << 2) | 1 = 21
    const d1 = try decodeImplementation(21);
    try testing.expectEqual(TableId.AssemblyRef, d1.table);
    try testing.expectEqual(@as(u32, 5), d1.row);
    // tag=2 (ExportedType), row=7 => raw = (7 << 2) | 2 = 30
    const d2 = try decodeImplementation(30);
    try testing.expectEqual(TableId.ExportedType, d2.table);
    try testing.expectEqual(@as(u32, 7), d2.row);
    // tag=3 => invalid
    try testing.expectError(error.InvalidTag, decodeImplementation(3));
}

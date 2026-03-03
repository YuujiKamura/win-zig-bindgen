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

test "decode TypeDefOrRef" {
    const x = try decodeTypeDefOrRef((123 << 2) | 1);
    try std.testing.expectEqual(TableId.TypeRef, x.table);
    try std.testing.expectEqual(@as(u32, 123), x.row);
}

test "coded index width grows to 4 bytes" {
    var rows = std.mem.zeroes([64]u32);
    rows[@intFromEnum(TableId.TypeDef)] = 100_000;
    const size = codedIndexSize(rows, 2, &.{ .TypeDef, .TypeRef, .TypeSpec });
    try std.testing.expectEqual(@as(u8, 4), size);
}

test "decode TypeDefOrRef invalid tag returns error" {
    try std.testing.expectError(error.InvalidTag, decodeTypeDefOrRef((1 << 2) | 3));
}

test "coded index width stays 2 bytes at threshold" {
    var rows = std.mem.zeroes([64]u32);
    // For tag_bits=2, max small rows = (1 << 14) - 1.
    rows[@intFromEnum(TableId.TypeDef)] = (1 << 14) - 1;
    const size = codedIndexSize(rows, 2, &.{ .TypeDef, .TypeRef, .TypeSpec });
    try std.testing.expectEqual(@as(u8, 2), size);
}

test "coded index width becomes 4 bytes above threshold" {
    var rows = std.mem.zeroes([64]u32);
    rows[@intFromEnum(TableId.TypeRef)] = (1 << 14);
    const size = codedIndexSize(rows, 2, &.{ .TypeDef, .TypeRef, .TypeSpec });
    try std.testing.expectEqual(@as(u8, 4), size);
}

test "decode HasCustomAttribute maps methoddef tag" {
    const x = try decodeHasCustomAttribute((77 << 5) | 0);
    try std.testing.expectEqual(TableId.MethodDef, x.table);
    try std.testing.expectEqual(@as(u32, 77), x.row);
}

test "decode HasCustomAttribute maps methodspec tag" {
    const x = try decodeHasCustomAttribute((9 << 5) | 21);
    try std.testing.expectEqual(TableId.MethodSpec, x.table);
    try std.testing.expectEqual(@as(u32, 9), x.row);
}

test "decode HasCustomAttribute invalid tag returns error" {
    try std.testing.expectError(error.InvalidTag, decodeHasCustomAttribute((1 << 5) | 31));
}

test "decode CustomAttributeType maps methoddef and memberref" {
    const m = try decodeCustomAttributeType((42 << 3) | 2);
    try std.testing.expectEqual(TableId.MethodDef, m.table);
    try std.testing.expectEqual(@as(u32, 42), m.row);

    const r = try decodeCustomAttributeType((24 << 3) | 3);
    try std.testing.expectEqual(TableId.MemberRef, r.table);
    try std.testing.expectEqual(@as(u32, 24), r.row);
}

test "decode CustomAttributeType invalid tag returns error" {
    try std.testing.expectError(error.InvalidTag, decodeCustomAttributeType((2 << 3) | 1));
}

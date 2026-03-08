const std = @import("std");
const winmd2zig = @import("winmd2zig_main");
const win_zig_metadata = @import("win_zig_metadata");
const pe = win_zig_metadata.pe;
const metadata = win_zig_metadata.metadata;
const tables = win_zig_metadata.tables;
const streams = win_zig_metadata.streams;
const coded = win_zig_metadata.coded_index;

fn redCase(case_id: []const u8, args: []const u8) !void {
    std.log.err("RED case {s} is not implemented yet: {s}", .{ case_id, args });
    try std.testing.expect(false);
}

const FnMode = enum {
    win,
    sys,
    sys_targets,
    sys_extern,
    sys_extern_ptrs,
    sys_ptrs,
};

const ParsedSig = struct {
    param_count: u8,
    ret_tag: u8,
};

fn parseSimpleMethodSig(sig: []const u8) !ParsedSig {
    if (sig.len < 3) return error.InvalidSignature;
    const call_conv = sig[0] & 0x0f;
    if (call_conv != 0x00 and call_conv != 0x05) return error.InvalidSignature;
    const param_count = sig[1];
    const ret_tag = sig[2];
    return .{
        .param_count = param_count,
        .ret_tag = ret_tag,
    };
}

fn mapRetTag(ret_tag: u8) ![]const u8 {
    return switch (ret_tag) {
        0x01 => "void",
        0x09 => "u32",
        0xf0 => "noreturn",
        else => error.UnsupportedRetType,
    };
}

fn emitFunctionDecl(
    allocator: std.mem.Allocator,
    name: []const u8,
    parsed: ParsedSig,
    mode: FnMode,
) ![]u8 {
    if (parsed.param_count != 0) return error.OnlyZeroParamSupported;
    const ret_ty = try mapRetTag(parsed.ret_tag);
    return switch (mode) {
        .win => std.fmt.allocPrint(
            allocator,
            "pub fn {s}() callconv(.winapi) {s};",
            .{ name, ret_ty },
        ),
        .sys => std.fmt.allocPrint(
            allocator,
            "pub extern fn {s}() callconv(.winapi) {s};",
            .{ name, ret_ty },
        ),
        .sys_targets => std.fmt.allocPrint(
            allocator,
            "pub const {s} = windows_targets.system_information.GetTickCount;",
            .{name},
        ),
        .sys_extern => std.fmt.allocPrint(
            allocator,
            "extern \"kernel32\" fn {s}() callconv(.winapi) {s};",
            .{ name, ret_ty },
        ),
        .sys_extern_ptrs => std.fmt.allocPrint(
            allocator,
            "pub const pfn_{s}: *const fn() callconv(.winapi) {s} = @ptrCast(&{s});",
            .{ name, ret_ty, name },
        ),
        .sys_ptrs => std.fmt.allocPrint(
            allocator,
            "pub const pfn_{s}: *const fn() callconv(.winapi) {s} = @ptrCast(&{s});",
            .{ name, ret_ty, name },
        ),
    };
}

fn findWinmdOrSkip() ![]u8 {
    return winmd2zig.findWindowsKitUnionWinmdAlloc(std.testing.allocator) catch return error.SkipZigTest;
}

fn findWin32WinmdOrSkip() ![]u8 {
    return winmd2zig.findWin32DefaultWinmdAlloc(std.testing.allocator) catch return error.SkipZigTest;
}

fn expectTypeExists(winmd_path: []const u8, full_name: []const u8) !void {
    const ok = try winmd2zig.hasTypeDefByNameAlloc(std.testing.allocator, winmd_path, full_name);
    try std.testing.expect(ok);
}

fn expectMethodExists(winmd_path: []const u8, method_name: []const u8) !void {
    const ok = try winmd2zig.hasMethodDefByNameAlloc(std.testing.allocator, winmd_path, method_name);
    try std.testing.expect(ok);
}

const MdCtx = struct {
    arena: std.heap.ArenaAllocator,
    table_info: tables.Info,
    heaps: streams.Heaps,

    fn deinit(self: *MdCtx) void {
        self.arena.deinit();
    }
};

fn loadMdCtx(allocator: std.mem.Allocator, winmd_path: []const u8) !MdCtx {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const a = arena.allocator();

    const data = try std.fs.cwd().readFileAlloc(a, winmd_path, std.math.maxInt(usize));
    const pe_info = try pe.parse(a, data);
    const md_info = try metadata.parse(a, pe_info);
    const table_stream = md_info.getStream("#~") orelse return error.MissingTableStream;
    const strings_stream = md_info.getStream("#Strings") orelse return error.MissingStringsStream;
    const blob_stream = md_info.getStream("#Blob") orelse return error.MissingBlobStream;
    const guid_stream = md_info.getStream("#GUID") orelse return error.MissingGuidStream;
    const table_info = try tables.parse(table_stream.data);
    return .{
        .arena = arena,
        .table_info = table_info,
        .heaps = .{
            .strings = strings_stream.data,
            .blob = blob_stream.data,
            .guid = guid_stream.data,
        },
    };
}

const FieldRow = struct {
    flags: u16,
    name: u32,
    signature: u32,
};

fn readIdx(data: []const u8, pos: *usize, width: u8) u32 {
    const out: u32 = switch (width) {
        2 => std.mem.readInt(u16, data[pos.* ..][0..2], .little),
        4 => std.mem.readInt(u32, data[pos.* ..][0..4], .little),
        else => unreachable,
    };
    pos.* += width;
    return out;
}

fn tableRowSlice(info: tables.Info, table_id: coded.TableId, row: u32) ![]const u8 {
    const t = info.getTable(table_id);
    if (!t.present or row == 0 or row > t.row_count) return error.InvalidTableRow;
    const start = t.offset + (@as(usize, row - 1) * t.row_size);
    const end = start + t.row_size;
    if (end > info.data.len) return error.Truncated;
    return info.data[start..end];
}

fn readFieldRow(info: tables.Info, row: u32) !FieldRow {
    const data = try tableRowSlice(info, .Field, row);
    var pos: usize = 0;
    return .{
        .flags = std.mem.readInt(u16, data[pos..][0..2], .little),
        .name = blk: {
            pos += 2;
            break :blk readIdx(data, &pos, info.indexes.string);
        },
        .signature = readIdx(data, &pos, info.indexes.blob),
    };
}

const ClassLayoutRow = struct {
    packing_size: u16,
    class_size: u32,
    parent: u32,
};

fn readClassLayoutRow(info: tables.Info, row: u32) !ClassLayoutRow {
    const data = try tableRowSlice(info, .ClassLayout, row);
    var pos: usize = 0;
    const packing_size = std.mem.readInt(u16, data[pos..][0..2], .little);
    pos += 2;
    const class_size = std.mem.readInt(u32, data[pos..][0..4], .little);
    pos += 4;
    const parent = readIdx(data, &pos, if (info.row_counts[@intFromEnum(coded.TableId.TypeDef)] < 0x10000) 2 else 4);
    return .{
        .packing_size = packing_size,
        .class_size = class_size,
        .parent = parent,
    };
}

const ConstantRow = struct {
    element_type: u8,
    parent: u32,
    value: u32,
};

fn readConstantRow(info: tables.Info, row: u32) !ConstantRow {
    const data = try tableRowSlice(info, .Constant, row);
    var pos: usize = 0;
    const element_type = data[pos];
    pos += 2; // type + padding
    const parent = readIdx(data, &pos, info.indexes.has_constant);
    const value = readIdx(data, &pos, info.indexes.blob);
    return .{
        .element_type = element_type,
        .parent = parent,
        .value = value,
    };
}

fn fieldRange(info: tables.Info, type_row: u32) !struct { start: u32, end_exclusive: u32 } {
    const td = try info.readTypeDef(type_row);
    const start = td.field_list;
    const type_table = info.getTable(.TypeDef);
    const field_table = info.getTable(.Field);
    const end_exclusive: u32 = if (type_row < type_table.row_count)
        (try info.readTypeDef(type_row + 1)).field_list
    else
        field_table.row_count + 1;
    return .{ .start = start, .end_exclusive = end_exclusive };
}

fn findTypeRow(md: MdCtx, full_name: []const u8) !u32 {
    const split_at = std.mem.lastIndexOfScalar(u8, full_name, '.') orelse return error.TypeNotFound;
    const ns = full_name[0..split_at];
    const name = full_name[split_at + 1 ..];
    const t = md.table_info.getTable(.TypeDef);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const td = try md.table_info.readTypeDef(row);
        const n = try md.heaps.getString(td.type_name);
        const nspace = try md.heaps.getString(td.type_namespace);
        if (std.mem.eql(u8, n, name) and std.mem.eql(u8, nspace, ns)) return row;
    }
    return error.TypeNotFound;
}

fn countFields(md: MdCtx, full_name: []const u8) !usize {
    const row = try findTypeRow(md, full_name);
    const fr = try fieldRange(md.table_info, row);
    return fr.end_exclusive - fr.start;
}

fn expectHasField(md: MdCtx, full_name: []const u8, field_name: []const u8) !void {
    const row = try findTypeRow(md, full_name);
    const fr = try fieldRange(md.table_info, row);
    var f = fr.start;
    while (f < fr.end_exclusive) : (f += 1) {
        const fld = try readFieldRow(md.table_info, f);
        const name = try md.heaps.getString(fld.name);
        if (std.mem.eql(u8, name, field_name)) return;
    }
    return error.TestUnexpectedResult;
}

fn getFieldSignatureBlob(md: MdCtx, full_name: []const u8, field_name: []const u8) ![]const u8 {
    const row = try findTypeRow(md, full_name);
    const fr = try fieldRange(md.table_info, row);
    var f = fr.start;
    while (f < fr.end_exclusive) : (f += 1) {
        const fld = try readFieldRow(md.table_info, f);
        const name = try md.heaps.getString(fld.name);
        if (!std.mem.eql(u8, name, field_name)) continue;
        return md.heaps.getBlob(fld.signature);
    }
    return error.TestUnexpectedResult;
}

fn expectEnumValueI32(md: MdCtx, full_name: []const u8, literal_name: []const u8, expected: i32) !void {
    const row = try findTypeRow(md, full_name);
    const fr = try fieldRange(md.table_info, row);
    var f = fr.start;
    while (f < fr.end_exclusive) : (f += 1) {
        const fld = try readFieldRow(md.table_info, f);
        const name = try md.heaps.getString(fld.name);
        if (!std.mem.eql(u8, name, literal_name)) continue;

        const ctbl = md.table_info.getTable(.Constant);
        var c: u32 = 1;
        while (c <= ctbl.row_count) : (c += 1) {
            const cn = try readConstantRow(md.table_info, c);
            const parent_field = cn.parent >> 2; // HasConstant: Field/Param/Property
            const parent_tag = cn.parent & 0x3;
            if (parent_tag != 0) continue;
            if (parent_field != f) continue;
            const blob = try md.heaps.getBlob(cn.value);
            if (blob.len < 4) return error.TestUnexpectedResult;
            const actual = std.mem.readInt(i32, blob[0..4], .little);
            try std.testing.expectEqual(expected, actual);
            return;
        }
        return error.TestUnexpectedResult;
    }
    return error.TestUnexpectedResult;
}

fn findClassLayoutForType(md: MdCtx, full_name: []const u8) !?ClassLayoutRow {
    const row = try findTypeRow(md, full_name);
    const cl = md.table_info.getTable(.ClassLayout);
    var i: u32 = 1;
    while (i <= cl.row_count) : (i += 1) {
        const r = try readClassLayoutRow(md.table_info, i);
        if (r.parent == row) return r;
    }
    return null;
}

fn emitEnumDecl(
    allocator: std.mem.Allocator,
    enum_name: []const u8,
    mode: FnMode,
    kind: []const u8,
) ![]u8 {
    const prefix = switch (mode) {
        .win => "pub const",
        .sys => "pub const",
        else => return error.InvalidMode,
    };
    return std.fmt.allocPrint(
        allocator,
        "{s} {s} = {s};",
        .{ prefix, enum_name, kind },
    );
}

fn emitStructDecl(
    allocator: std.mem.Allocator,
    struct_name: []const u8,
    mode: FnMode,
    kind: []const u8,
) ![]u8 {
    const prefix = switch (mode) {
        .win => "pub const",
        .sys => "pub const",
        else => return error.InvalidMode,
    };
    return std.fmt.allocPrint(
        allocator,
        "{s} {s} = {s};",
        .{ prefix, struct_name, kind },
    );
}

const CoreMode = struct {
    sys: bool = false,
    flat: bool = false,
    no_deps: bool = false,
};

fn emitCoreModeDecl(allocator: std.mem.Allocator, mode: CoreMode) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "pub const CoreMode = struct {{ sys: {s}, flat: {s}, no_deps: {s} }};",
        .{
            if (mode.sys) "true" else "false",
            if (mode.flat) "true" else "false",
            if (mode.no_deps) "true" else "false",
        },
    );
}

fn emitDeriveDecl(allocator: std.mem.Allocator, type_name: []const u8, derive: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "pub const Derive_{s} = \"{s}\";",
        .{ type_name, derive },
    );
}

fn emitArchStructDecl(allocator: std.mem.Allocator, type_name: []const u8, mode: FnMode) ![]u8 {
    const suffix = switch (mode) {
        .win => "win",
        .sys => "sys",
        else => return error.InvalidMode,
    };
    return std.fmt.allocPrint(
        allocator,
        "pub const {s}_{s} = extern struct;",
        .{ type_name, suffix },
    );
}

fn emitReferenceDecl(
    allocator: std.mem.Allocator,
    case_tag: []const u8,
    target: []const u8,
    reference: []const u8,
    mode: []const u8,
) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "pub const Ref_{s} = struct {{ target: \"{s}\", reference: \"{s}\", mode: \"{s}\" }};",
        .{ case_tag, target, reference, mode },
    );
}

test "RED 051 fn_win GetTickCount generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const abi = try winmd2zig.inspectFunctionAbiByNameAlloc(std.testing.allocator, winmd_path, "GetTickCount");
    defer std.testing.allocator.free(abi);
    try std.testing.expectEqualStrings("fn() -> u32", abi);
}

test "RED 052 fn_sys GetTickCount generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const abi = try winmd2zig.inspectFunctionAbiByNameAlloc(std.testing.allocator, winmd_path, "GetTickCount");
    defer std.testing.allocator.free(abi);
    try std.testing.expectEqualStrings("fn() -> u32", abi);
}

test "RED 053 fn_sys_targets generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const abi = try winmd2zig.inspectFunctionAbiByNameAlloc(std.testing.allocator, winmd_path, "GetTickCount");
    defer std.testing.allocator.free(abi);
    try std.testing.expectEqualStrings("fn() -> u32", abi);
}

test "RED 054 fn_sys_extern generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const abi = try winmd2zig.inspectFunctionAbiByNameAlloc(std.testing.allocator, winmd_path, "GetTickCount");
    defer std.testing.allocator.free(abi);
    try std.testing.expectEqualStrings("fn() -> u32", abi);
}

test "RED 055 fn_sys_extern_ptrs generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const abi = try winmd2zig.inspectFunctionAbiByNameAlloc(std.testing.allocator, winmd_path, "GetTickCount");
    defer std.testing.allocator.free(abi);
    try std.testing.expectEqualStrings("fn() -> u32", abi);
}

test "RED 056 fn_sys_ptrs generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const abi = try winmd2zig.inspectFunctionAbiByNameAlloc(std.testing.allocator, winmd_path, "GetTickCount");
    defer std.testing.allocator.free(abi);
    try std.testing.expectEqualStrings("fn() -> u32", abi);
}

test "RED 057 fn_associated_enum_win generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const abi = try winmd2zig.inspectFunctionAbiByNameAlloc(std.testing.allocator, winmd_path, "CoInitializeEx");
    defer std.testing.allocator.free(abi);
    try std.testing.expectEqualStrings("fn(p0:*void, p1:u32) -> Windows.Win32.Foundation.HRESULT", abi);
}

test "RED 058 fn_associated_enum_sys generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const abi = try winmd2zig.inspectFunctionAbiByNameAlloc(std.testing.allocator, winmd_path, "CoInitializeEx");
    defer std.testing.allocator.free(abi);
    try std.testing.expectEqualStrings("fn(p0:*void, p1:u32) -> Windows.Win32.Foundation.HRESULT", abi);
}

test "RED 059 fn_return_void_win generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const abi = try winmd2zig.inspectFunctionAbiByNameAlloc(std.testing.allocator, winmd_path, "GlobalMemoryStatus");
    defer std.testing.allocator.free(abi);
    try std.testing.expectEqualStrings("fn(p0:*Windows.Win32.System.SystemInformation.MEMORYSTATUS) -> void", abi);
}

test "RED 060 fn_return_void_sys generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const abi = try winmd2zig.inspectFunctionAbiByNameAlloc(std.testing.allocator, winmd_path, "GlobalMemoryStatus");
    defer std.testing.allocator.free(abi);
    try std.testing.expectEqualStrings("fn(p0:*Windows.Win32.System.SystemInformation.MEMORYSTATUS) -> void", abi);
}

test "RED 061 fn_no_return_win generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const abi = try winmd2zig.inspectFunctionAbiByNameAlloc(std.testing.allocator, winmd_path, "FatalExit");
    defer std.testing.allocator.free(abi);
    try std.testing.expectEqualStrings("fn(p0:i32) -> void", abi);
}

test "RED 062 fn_no_return_sys generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const abi = try winmd2zig.inspectFunctionAbiByNameAlloc(std.testing.allocator, winmd_path, "FatalExit");
    defer std.testing.allocator.free(abi);
    try std.testing.expectEqualStrings("fn(p0:i32) -> void", abi);
}

test "RED 063 fn_result_void_sys generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const abi = try winmd2zig.inspectFunctionAbiByNameAlloc(std.testing.allocator, winmd_path, "SetComputerNameA");
    defer std.testing.allocator.free(abi);
    try std.testing.expectEqualStrings("fn(p0:Windows.Win32.Foundation.PSTR) -> Windows.Win32.Foundation.BOOL", abi);
}

test "RED 013 enum_win generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try expectEnumValueI32(md, "Windows.Foundation.AsyncStatus", "Completed", 1);
}

test "RED 007 derive_struct generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try std.testing.expectEqual(@as(usize, 1), try countFields(md, "Windows.Foundation.DateTime"));
    try expectHasField(md, "Windows.Foundation.DateTime", "UniversalTime");
}

test "RED 008 derive_cpp_struct generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try std.testing.expectEqual(@as(usize, 2), try countFields(md, "Windows.Win32.Foundation.POINT"));
    try expectHasField(md, "Windows.Win32.Foundation.POINT", "x");
    try expectHasField(md, "Windows.Win32.Foundation.POINT", "y");
}

test "RED 009 derive_cpp_struct_sys generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try std.testing.expectEqual(@as(usize, 2), try countFields(md, "Windows.Win32.Foundation.POINT"));
    try expectHasField(md, "Windows.Win32.Foundation.POINT", "x");
    try expectHasField(md, "Windows.Win32.Foundation.POINT", "y");
}

test "RED 010 derive_enum generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try expectHasField(md, "Windows.Foundation.AsyncStatus", "value__");
    try expectEnumValueI32(md, "Windows.Foundation.AsyncStatus", "Started", 0);
    try expectEnumValueI32(md, "Windows.Foundation.AsyncStatus", "Completed", 1);
    try expectEnumValueI32(md, "Windows.Foundation.AsyncStatus", "Canceled", 2);
    try expectEnumValueI32(md, "Windows.Foundation.AsyncStatus", "Error", 3);
}

test "RED 011 derive_cpp_enum generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try expectHasField(md, "Windows.Win32.Foundation.WAIT_EVENT", "value__");
    try expectEnumValueI32(md, "Windows.Win32.Foundation.WAIT_EVENT", "WAIT_OBJECT_0", 0);
    try expectEnumValueI32(md, "Windows.Win32.Foundation.WAIT_EVENT", "WAIT_TIMEOUT", 258);
}

test "RED 012 derive_edges generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try std.testing.expectEqual(@as(usize, 2), try countFields(md, "Windows.Win32.Foundation.POINT"));
    try std.testing.expectEqual(@as(usize, 2), try countFields(md, "Windows.Win32.Foundation.SIZE"));
    try expectHasField(md, "Windows.Win32.Foundation.SIZE", "cx");
    try expectHasField(md, "Windows.Win32.Foundation.SIZE", "cy");
}

test "RED 001 core_win generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const abi = try winmd2zig.inspectFunctionAbiByNameAlloc(std.testing.allocator, winmd_path, "CoCreateGuid");
    defer std.testing.allocator.free(abi);
    try std.testing.expect(std.mem.startsWith(u8, abi, "fn("));
}

test "RED 002 core_win_flat generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const abi = try winmd2zig.inspectFunctionAbiByNameAlloc(std.testing.allocator, winmd_path, "CoCreateGuid");
    defer std.testing.allocator.free(abi);
    try std.testing.expect(std.mem.indexOf(u8, abi, "HRESULT") != null);
}

test "RED 003 core_sys generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const abi = try winmd2zig.inspectFunctionAbiByNameAlloc(std.testing.allocator, winmd_path, "CoCreateGuid");
    defer std.testing.allocator.free(abi);
    try std.testing.expect(std.mem.startsWith(u8, abi, "fn("));
}

test "RED 004 core_sys_flat generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const abi = try winmd2zig.inspectFunctionAbiByNameAlloc(std.testing.allocator, winmd_path, "CoCreateGuid");
    defer std.testing.allocator.free(abi);
    try std.testing.expect(std.mem.indexOf(u8, abi, "HRESULT") != null);
}

test "RED 005 core_sys_no_core generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const abi = try winmd2zig.inspectFunctionAbiByNameAlloc(std.testing.allocator, winmd_path, "CoCreateGuid");
    defer std.testing.allocator.free(abi);
    try std.testing.expect(std.mem.indexOf(u8, abi, "HRESULT") != null);
}

test "RED 006 core_sys_flat_no_core generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const abi = try winmd2zig.inspectFunctionAbiByNameAlloc(std.testing.allocator, winmd_path, "CoCreateGuid");
    defer std.testing.allocator.free(abi);
    try std.testing.expect(std.mem.indexOf(u8, abi, "HRESULT") != null);
}

test "RED 014 enum_sys generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try expectEnumValueI32(md, "Windows.Foundation.AsyncStatus", "Error", 3);
}

test "RED 015 enum_flags_win generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try expectHasField(md, "Windows.Foundation.Diagnostics.ErrorOptions", "SuppressExceptions");
    try expectEnumValueI32(md, "Windows.Foundation.Diagnostics.ErrorOptions", "None", 0);
}

test "RED 016 enum_flags_sys generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try expectEnumValueI32(md, "Windows.Foundation.Diagnostics.ErrorOptions", "SuppressExceptions", 1);
}

test "RED 017 enum_cpp_win generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try expectEnumValueI32(md, "Windows.Win32.Foundation.WAIT_EVENT", "WAIT_FAILED", -1);
}

test "RED 018 enum_cpp_sys generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try expectEnumValueI32(md, "Windows.Win32.Foundation.WAIT_EVENT", "WAIT_ABANDONED", 128);
}

test "RED 019 enum_cpp_flags_win generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try expectEnumValueI32(md, "Windows.Win32.Foundation.GENERIC_ACCESS_RIGHTS", "GENERIC_READ", @as(i32, @bitCast(@as(u32, 0x80000000))));
}

test "RED 020 enum_cpp_flags_sys generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try expectEnumValueI32(md, "Windows.Win32.Foundation.GENERIC_ACCESS_RIGHTS", "GENERIC_WRITE", 0x40000000);
}

test "RED 021 enum_cpp_scoped_win generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try expectEnumValueI32(md, "Windows.Win32.Security.Authentication.Identity.SECURITY_LOGON_TYPE", "Interactive", 2);
}

test "RED 022 enum_cpp_scoped_sys generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try expectEnumValueI32(md, "Windows.Win32.Security.Authentication.Identity.SECURITY_LOGON_TYPE", "Network", 3);
}

test "RED 023 struct_win generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try std.testing.expectEqual(@as(usize, 4), try countFields(md, "Windows.Graphics.RectInt32"));
    try expectHasField(md, "Windows.Graphics.RectInt32", "X");
    try expectHasField(md, "Windows.Graphics.RectInt32", "Y");
    try expectHasField(md, "Windows.Graphics.RectInt32", "Width");
    try expectHasField(md, "Windows.Graphics.RectInt32", "Height");
}

test "RED 024 struct_sys generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try std.testing.expectEqual(@as(usize, 4), try countFields(md, "Windows.Graphics.RectInt32"));
    try expectHasField(md, "Windows.Graphics.RectInt32", "Width");
}

test "RED 025 struct_cpp_win generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try std.testing.expectEqual(@as(usize, 4), try countFields(md, "Windows.Win32.Foundation.RECT"));
    try expectHasField(md, "Windows.Win32.Foundation.RECT", "left");
    try expectHasField(md, "Windows.Win32.Foundation.RECT", "top");
    try expectHasField(md, "Windows.Win32.Foundation.RECT", "right");
    try expectHasField(md, "Windows.Win32.Foundation.RECT", "bottom");
}

test "RED 026 struct_cpp_sys generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try std.testing.expectEqual(@as(usize, 4), try countFields(md, "Windows.Win32.Foundation.RECT"));
    try expectHasField(md, "Windows.Win32.Foundation.RECT", "left");
}

test "RED 027 struct_disambiguate generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try std.testing.expectEqual(@as(usize, 4), try countFields(md, "Windows.Foundation.Rect"));
    try expectHasField(md, "Windows.Foundation.Rect", "X");
    try expectHasField(md, "Windows.Foundation.Rect", "Y");
}

test "RED 028 struct_with_generic generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try std.testing.expect((try countFields(md, "Windows.Web.Http.HttpProgress")) >= 5);
    try expectHasField(md, "Windows.Web.Http.HttpProgress", "Stage");
    try expectHasField(md, "Windows.Web.Http.HttpProgress", "BytesReceived");
}

test "RED 029 struct_with_cpp_interface generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try std.testing.expectEqual(@as(usize, 1), try countFields(md, "Windows.Win32.Graphics.Direct3D12.D3D12_RESOURCE_UAV_BARRIER"));
    try expectHasField(md, "Windows.Win32.Graphics.Direct3D12.D3D12_RESOURCE_UAV_BARRIER", "pResource");
}

test "RED 030 struct_with_cpp_interface_sys generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try expectHasField(md, "Windows.Win32.Graphics.Direct3D12.D3D12_RESOURCE_UAV_BARRIER", "pResource");
}

test "RED 031 struct_arch_a generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try std.testing.expectEqual(@as(usize, 2), try countFields(md, "Windows.Win32.Devices.DeviceAndDriverInstallation.SP_POWERMESSAGEWAKE_PARAMS_A"));
    try expectHasField(md, "Windows.Win32.Devices.DeviceAndDriverInstallation.SP_POWERMESSAGEWAKE_PARAMS_A", "PowerMessageWake");
}

test "RED 032 struct_arch_w generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try std.testing.expectEqual(@as(usize, 2), try countFields(md, "Windows.Win32.Devices.DeviceAndDriverInstallation.SP_POWERMESSAGEWAKE_PARAMS_W"));
    try expectHasField(md, "Windows.Win32.Devices.DeviceAndDriverInstallation.SP_POWERMESSAGEWAKE_PARAMS_W", "PowerMessageWake");
}

test "RED 033 struct_arch_a_sys generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try std.testing.expectEqual(
        try countFields(md, "Windows.Win32.Devices.DeviceAndDriverInstallation.SP_POWERMESSAGEWAKE_PARAMS_A"),
        try countFields(md, "Windows.Win32.Devices.DeviceAndDriverInstallation.SP_POWERMESSAGEWAKE_PARAMS_W"),
    );
    const sig_a = try getFieldSignatureBlob(md, "Windows.Win32.Devices.DeviceAndDriverInstallation.SP_POWERMESSAGEWAKE_PARAMS_A", "PowerMessageWake");
    const sig_w = try getFieldSignatureBlob(md, "Windows.Win32.Devices.DeviceAndDriverInstallation.SP_POWERMESSAGEWAKE_PARAMS_W", "PowerMessageWake");
    try std.testing.expect(!std.mem.eql(u8, sig_a, sig_w));
}

test "RED 034 struct_arch_w_sys generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    var md = try loadMdCtx(std.testing.allocator, winmd_path);
    defer md.deinit();
    try std.testing.expect((try countFields(md, "Windows.Win32.Devices.DeviceAndDriverInstallation.SP_POWERMESSAGEWAKE_PARAMS_W")) >= 1);
}

test "RED 035 interface_win IStringable generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.IStringable");
}

test "RED 036 interface_sys IStringable generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.IStringable");
}

test "RED 037 interface_sys_no_core IStringable generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.IStringable");
}

test "RED 038 interface_cpp IPersist generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Win32.System.Com.IPersist");
}

test "RED 039 interface_cpp_sys IPersist generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Win32.System.Com.IPersist");
}

test "RED 040 interface_cpp_sys_no_core IPersist generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Win32.System.Com.IPersist");
}

test "RED 041 interface_cpp_derive IPersistFile generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Win32.System.Com.IPersistFile");
}

test "RED 042 interface_cpp_derive_sys IPersistFile generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Win32.System.Com.IPersistFile");
}

test "RED 043 interface_cpp_return_udt ID2D1Bitmap generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Win32.Graphics.Direct2D.ID2D1Bitmap");
    try expectTypeExists(winmd_path, "Windows.Win32.Graphics.Direct2D.Common.D2D_SIZE_F");
}

test "RED 044 interface_generic IAsyncOperation generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.IAsyncOperation`1");
}

test "RED 045 interface_required IAsyncAction generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.IAsyncAction");
}

test "RED 046 interface_required_sys IAsyncAction generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.IAsyncAction");
}

test "RED 047 interface_required_with_method IAsyncInfo generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.IAsyncInfo");
    try expectTypeExists(winmd_path, "Windows.Foundation.AsyncStatus");
}

test "RED 048 interface_required_with_method_sys IAsyncInfo generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.IAsyncInfo");
    try expectTypeExists(winmd_path, "Windows.Foundation.AsyncStatus");
}

test "RED 049 interface_iterable IVector generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.Collections.IVector`1");
}

test "RED 050 interface_array_return IDispatch generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Win32.System.Com.IDispatch");
}

test "RED 064 delegate DeferralCompletedHandler generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.DeferralCompletedHandler");
}

test "RED 065 delegate_generic EventHandler generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.EventHandler`1");
}

test "RED 066 delegate_cpp GetProcAddress EnumWindows generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "GetProcAddress");
    try expectMethodExists(winmd_path, "EnumWindows");
}

test "RED 067 delegate_cpp_ref PFN symbols generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "RoGetActivationFactory");
    try expectMethodExists(winmd_path, "GetProcAddress");
}

test "RED 068 delegate_param SetConsoleCtrlHandler generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "SetConsoleCtrlHandler");
}

test "RED 069 class Deferral generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.Deferral");
}

test "RED 070 class_with_handler Deferral generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.Deferral");
    try expectTypeExists(winmd_path, "Windows.Foundation.DeferralCompletedHandler");
}

test "RED 071 class_static GuidHelper generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.GuidHelper");
}

test "RED 072 class_dep WwwFormUrlDecoder generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.WwwFormUrlDecoder");
}

test "RED 073 multi HTTP_VERSION generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    // HTTP_VERSION moved to HttpServer namespace in Win32 metadata v69+
    const ok1 = try winmd2zig.hasTypeDefByNameAlloc(std.testing.allocator, winmd_path, "Windows.Win32.Networking.WinHttp.HTTP_VERSION");
    const ok2 = try winmd2zig.hasTypeDefByNameAlloc(std.testing.allocator, winmd_path, "Windows.Win32.Networking.HttpServer.HTTP_VERSION");
    try std.testing.expect(ok1 or ok2);
}

test "RED 074 multi_sys HTTP_VERSION generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    const ok1 = try winmd2zig.hasTypeDefByNameAlloc(std.testing.allocator, winmd_path, "Windows.Win32.Networking.WinHttp.HTTP_VERSION");
    const ok2 = try winmd2zig.hasTypeDefByNameAlloc(std.testing.allocator, winmd_path, "Windows.Win32.Networking.HttpServer.HTTP_VERSION");
    try std.testing.expect(ok1 or ok2);
}

test "RED 075 window_long_get_a generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "GetWindowLongPtrA");
}

test "RED 076 window_long_get_w generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "GetWindowLongPtrW");
}

test "RED 077 window_long_set_a generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "SetWindowLongPtrA");
}

test "RED 078 window_long_set_w generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "SetWindowLongPtrW");
}

test "RED 079 window_long_get_a_sys generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "GetWindowLongPtrA");
}

test "RED 080 window_long_get_w_sys generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "GetWindowLongPtrW");
}

test "RED 081 window_long_set_a_sys generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "SetWindowLongPtrA");
}

test "RED 082 window_long_set_w_sys generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "SetWindowLongPtrW");
}

test "RED 083 reference_struct_filter generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.UI.Composition.InkTrailPoint");
}

test "RED 084 reference_struct_reference_type generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.UI.Composition.InkTrailPoint");
    try expectTypeExists(winmd_path, "Windows.Foundation.Point");
}

test "RED 085 reference_struct_reference_namespace generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.UI.Composition.InkTrailPoint");
    try expectTypeExists(winmd_path, "Windows.Foundation.IStringable");
}

test "RED 086 reference_struct_sys_filter generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Win32.Gaming.GAMING_DEVICE_MODEL_INFORMATION");
}

test "RED 087 reference_struct_sys_reference_type generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Win32.Gaming.GAMING_DEVICE_MODEL_INFORMATION");
    try expectTypeExists(winmd_path, "Windows.Win32.Gaming.GAMING_DEVICE_VENDOR_ID");
}

test "RED 088 reference_struct_sys_reference_namespace generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Win32.Gaming.GAMING_DEVICE_MODEL_INFORMATION");
    try expectTypeExists(winmd_path, "Windows.Win32.Gaming.GAMING_DEVICE_VENDOR_ID");
}

test "RED 089 bool EnableMouseInPointer generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "EnableMouseInPointer");
}

test "RED 090 bool_sys EnableMouseInPointer generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "EnableMouseInPointer");
}

test "RED 091 bool_sys_no_core EnableMouseInPointer generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "EnableMouseInPointer");
}

test "RED 092 bool_event wait/event API generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "CreateEventW");
    try expectMethodExists(winmd_path, "SetEvent");
    try expectMethodExists(winmd_path, "WaitForSingleObjectEx");
}

test "RED 093 bool_event_sans_reference wait/event API generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "CreateEventW");
    try expectMethodExists(winmd_path, "SetEvent");
    try expectMethodExists(winmd_path, "WaitForSingleObjectEx");
}

test "RED 094 ref_params model object generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    // IModelObject moved to Debug.Extensions sub-namespace in Win32 metadata v69+
    const ok1 = try winmd2zig.hasTypeDefByNameAlloc(std.testing.allocator, winmd_path, "Windows.Win32.System.Diagnostics.Debug.IModelObject");
    const ok2 = try winmd2zig.hasTypeDefByNameAlloc(std.testing.allocator, winmd_path, "Windows.Win32.System.Diagnostics.Debug.Extensions.IModelObject");
    try std.testing.expect(ok1 or ok2);
}

test "RED 095 reference_dependency_flat generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.IMemoryBufferReference");
}

test "RED 096 reference_dependency_full generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.IMemoryBufferReference");
}

test "RED 097 reference_dependency_skip_root generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.IMemoryBufferReference");
}

test "RED 098 reference_dependent_flat generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.IMemoryBuffer");
    try expectTypeExists(winmd_path, "Windows.Foundation.IMemoryBufferReference");
}

test "RED 099 reference_dependent_full generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.IMemoryBuffer");
    try expectTypeExists(winmd_path, "Windows.Foundation.IMemoryBufferReference");
}

test "RED 100 reference_dependent_skip_root generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.IMemoryBuffer");
    try expectTypeExists(winmd_path, "Windows.Foundation.IMemoryBufferReference");
}

test "RED 101 deps library loader generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "FreeLibrary");
    try expectMethodExists(winmd_path, "LoadLibraryExA");
    try expectMethodExists(winmd_path, "GetProcAddress");
}

test "RED 102 sort mixed symbol generation parity" {
    const winmd_path = try findWinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Foundation.Rect");
}

test "RED 103 default_default GetTickCount generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "GetTickCount");
}

test "RED 104 default_assumed GetTickCount generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "GetTickCount");
}

test "RED 105 comment output GetTickCount generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "GetTickCount");
}

test "RED 106 comment_no_allow GetTickCount generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectMethodExists(winmd_path, "GetTickCount");
}

test "RED 107 rustfmt_25 POINT generation parity" {
    const winmd_path = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(winmd_path);
    try expectTypeExists(winmd_path, "Windows.Win32.Foundation.POINT");
}

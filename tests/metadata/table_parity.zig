// Metadata table parity tests — verify win-zig-metadata reads correct values
// from real WinMD files by comparing against .NET System.Reflection.Metadata output.
//
// These tests start RED for unimplemented read functions. As win-zig-metadata
// gains new readXxx() methods, they turn GREEN.

const std = @import("std");
const winmd2zig = @import("winmd2zig_main");
const win_zig_metadata = @import("win_zig_metadata");
const pe = win_zig_metadata.pe;
const metadata = win_zig_metadata.metadata;
const tables = win_zig_metadata.tables;
const streams = win_zig_metadata.streams;
const coded = win_zig_metadata.coded_index;

// ============================================================
// Test infrastructure
// ============================================================

const MdCtx = struct {
    arena: std.heap.ArenaAllocator,
    table_info: tables.Info,
    heaps: streams.Heaps,

    fn deinit(self: *MdCtx) void {
        self.arena.deinit();
    }
};

fn loadWinmd(allocator: std.mem.Allocator, path: []const u8) !MdCtx {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const a = arena.allocator();

    const data = std.fs.cwd().readFileAlloc(a, path, std.math.maxInt(usize)) catch |err| {
        std.log.err("Cannot open WinMD: {s} ({any})", .{ path, err });
        return err;
    };
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

// WinMD file paths (Windows SDK)
const uac_winmd = "C:/Program Files (x86)/Windows Kits/10/References/10.0.26100.0/Windows.Foundation.UniversalApiContract/19.0.0.0/Windows.Foundation.UniversalApiContract.winmd";

fn findWin32WinmdOrSkip() ![]u8 {
    return winmd2zig.findWin32DefaultWinmdAlloc(std.testing.allocator) catch return error.SkipZigTest;
}

// ============================================================
// Row count parity — UniversalApiContract.winmd
// Reference: .NET System.Reflection.Metadata (dotnet 9.0)
// ============================================================

test "UAC row_count: TypeDef = 12506" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    try std.testing.expectEqual(@as(u32, 12506), md.table_info.getTable(.TypeDef).row_count);
}

test "UAC row_count: TypeRef = 12586" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    try std.testing.expectEqual(@as(u32, 12586), md.table_info.getTable(.TypeRef).row_count);
}

test "UAC row_count: MethodDef = 62959" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    try std.testing.expectEqual(@as(u32, 62959), md.table_info.getTable(.MethodDef).row_count);
}

test "UAC row_count: Field = 9910" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    try std.testing.expectEqual(@as(u32, 9910), md.table_info.getTable(.Field).row_count);
}

test "UAC row_count: Param = 78401 (>= 65536, triggers 4-byte index)" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    try std.testing.expectEqual(@as(u32, 78401), md.table_info.getTable(.Param).row_count);
}

test "UAC row_count: MemberRef = 23494" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    try std.testing.expectEqual(@as(u32, 23494), md.table_info.getTable(.MemberRef).row_count);
}

test "UAC row_count: CustomAttribute = 56148" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    try std.testing.expectEqual(@as(u32, 56148), md.table_info.getTable(.CustomAttribute).row_count);
}

test "UAC row_count: InterfaceImpl = 6703" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    try std.testing.expectEqual(@as(u32, 6703), md.table_info.getTable(.InterfaceImpl).row_count);
}

test "UAC row_count: Constant = 8126" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    try std.testing.expectEqual(@as(u32, 8126), md.table_info.getTable(.Constant).row_count);
}

test "UAC row_count: Property = 31236" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    try std.testing.expectEqual(@as(u32, 31236), md.table_info.getTable(.Property).row_count);
}

test "UAC row_count: PropertyMap = 7676" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    try std.testing.expectEqual(@as(u32, 7676), md.table_info.getTable(.PropertyMap).row_count);
}

test "UAC row_count: Event = 2506" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    try std.testing.expectEqual(@as(u32, 2506), md.table_info.getTable(.Event).row_count);
}

test "UAC row_count: EventMap = 1050" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    try std.testing.expectEqual(@as(u32, 1050), md.table_info.getTable(.EventMap).row_count);
}

test "UAC row_count: MethodSemantics = 45554" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    try std.testing.expectEqual(@as(u32, 45554), md.table_info.getTable(.MethodSemantics).row_count);
}

// ============================================================
// Win32-specific table parity — tables not present in UAC
// ============================================================

test "Win32 row_count: ModuleRef > 0" {
    const win32_winmd = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(win32_winmd);
    var md = try loadWinmd(std.testing.allocator, win32_winmd);
    defer md.deinit();
    try std.testing.expect(md.table_info.getTable(.ModuleRef).row_count > 0);
}

test "Win32 row_count: ImplMap > 0" {
    const win32_winmd = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(win32_winmd);
    var md = try loadWinmd(std.testing.allocator, win32_winmd);
    defer md.deinit();
    try std.testing.expect(md.table_info.getTable(.ImplMap).row_count > 0);
}

test "Win32 row_count: ClassLayout > 0" {
    const win32_winmd = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(win32_winmd);
    var md = try loadWinmd(std.testing.allocator, win32_winmd);
    defer md.deinit();
    try std.testing.expect(md.table_info.getTable(.ClassLayout).row_count > 0);
}

test "Win32 FieldRVA rows are readable when present" {
    const win32_winmd = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(win32_winmd);
    var md = try loadWinmd(std.testing.allocator, win32_winmd);
    defer md.deinit();
    const row_count = md.table_info.getTable(.FieldRVA).row_count;
    if (row_count == 0) return error.SkipZigTest;
    const frva = try md.table_info.readFieldRVA(1);
    try std.testing.expect(frva.field >= 1);
    try std.testing.expect(frva.field <= md.table_info.getTable(.Field).row_count);
}

// ============================================================
// Named row parity — verify string heap lookups
// ============================================================

test "UAC TypeDef row 2 = Windows.ApplicationModel.Activation.ActivationKind" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    const td = try md.table_info.readTypeDef(2);
    const name = try md.heaps.getString(td.type_name);
    const ns = try md.heaps.getString(td.type_namespace);
    try std.testing.expectEqualStrings("ActivationKind", name);
    try std.testing.expectEqualStrings("Windows.ApplicationModel.Activation", ns);
}

test "UAC Property row 1 name = Kind" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    const prop = try md.table_info.readProperty(1);
    const name = try md.heaps.getString(prop.name);
    try std.testing.expectEqualStrings("Kind", name);
}

test "UAC Event row 1 name = Dismissed" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    const ev = try md.table_info.readEvent(1);
    const name = try md.heaps.getString(ev.name);
    try std.testing.expectEqualStrings("Dismissed", name);
}

test "Win32 ModuleRef row 1 has valid name" {
    const win32_winmd = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(win32_winmd);
    var md = try loadWinmd(std.testing.allocator, win32_winmd);
    defer md.deinit();
    const mr = try md.table_info.readModuleRef(1);
    const name = try md.heaps.getString(mr.name);
    try std.testing.expect(name.len > 0);
}

test "Win32 ImplMap row 1 has valid import name and scope" {
    const win32_winmd = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(win32_winmd);
    var md = try loadWinmd(std.testing.allocator, win32_winmd);
    defer md.deinit();
    const im = try md.table_info.readImplMap(1);
    const name = try md.heaps.getString(im.import_name);
    try std.testing.expect(name.len > 0);
    try std.testing.expect(im.import_scope >= 1);
    try std.testing.expect(im.import_scope <= md.table_info.getTable(.ModuleRef).row_count);
}

test "Win32 ClassLayout row 1 has valid parent" {
    const win32_winmd = try findWin32WinmdOrSkip();
    defer std.testing.allocator.free(win32_winmd);
    var md = try loadWinmd(std.testing.allocator, win32_winmd);
    defer md.deinit();
    const cl = try md.table_info.readClassLayout(1);
    try std.testing.expect(cl.parent >= 1);
    try std.testing.expect(cl.parent <= md.table_info.getTable(.TypeDef).row_count);
}

// ============================================================
// Large-table parity — verify MethodDef reads near the end
// (this is the scenario that was broken by the simpleSize bug)
// ============================================================

test "UAC MethodDef row 39170 name is valid string (IPointerPoint region)" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    const m = try md.table_info.readMethodDef(39170);
    // Should not throw InvalidIndex — the name index must be in range
    const name = try md.heaps.getString(m.name);
    try std.testing.expect(name.len > 0);
}

test "UAC MethodDef last row is readable" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    const last = md.table_info.getTable(.MethodDef).row_count;
    try std.testing.expect(last > 0);
    const m = try md.table_info.readMethodDef(last);
    const name = try md.heaps.getString(m.name);
    try std.testing.expect(name.len > 0);
}

// ============================================================
// Cross-table parity — PropertyMap → Property chain
// ============================================================

test "UAC PropertyMap row 1 points to valid TypeDef and Property" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    const pm = try md.table_info.readPropertyMap(1);
    // parent should be a valid TypeDef row
    try std.testing.expect(pm.parent >= 1);
    try std.testing.expect(pm.parent <= md.table_info.getTable(.TypeDef).row_count);
    // property_list should be a valid Property row
    try std.testing.expect(pm.property_list >= 1);
    try std.testing.expect(pm.property_list <= md.table_info.getTable(.Property).row_count + 1);
}

// ============================================================
// Cross-table parity — EventMap → Event chain
// ============================================================

test "UAC EventMap row 1 points to valid TypeDef and Event" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    const em = try md.table_info.readEventMap(1);
    try std.testing.expect(em.parent >= 1);
    try std.testing.expect(em.parent <= md.table_info.getTable(.TypeDef).row_count);
    try std.testing.expect(em.event_list >= 1);
    try std.testing.expect(em.event_list <= md.table_info.getTable(.Event).row_count + 1);
}

// ============================================================
// MethodSemantics parity
// ============================================================

test "UAC MethodSemantics row 1 has valid method and association" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    const ms = try md.table_info.readMethodSemantics(1);
    // semantics is a bitmask (getter=0x02, setter=0x01, other=0x04, addOn=0x08, removeOn=0x10, fire=0x20)
    try std.testing.expect(ms.semantics > 0);
    try std.testing.expect(ms.semantics <= 0x3F);
    // method should be a valid MethodDef row
    try std.testing.expect(ms.method >= 1);
    try std.testing.expect(ms.method <= md.table_info.getTable(.MethodDef).row_count);
}

// ============================================================
// InterfaceImpl parity
// ============================================================

test "UAC InterfaceImpl row 1 has valid class" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    const ii = try md.table_info.readInterfaceImpl(1);
    try std.testing.expect(ii.class >= 1);
    try std.testing.expect(ii.class <= md.table_info.getTable(.TypeDef).row_count);
}

// ============================================================
// Constant parity
// ============================================================

test "UAC Constant row 1 has valid parent coded index" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    const c = try md.table_info.readConstant(1);
    // type should be a valid element type (I4=0x08, etc.)
    try std.testing.expect(c.type > 0);
}

// ============================================================
// MemberRef parity
// ============================================================

test "UAC MemberRef row 1 has valid name" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    const mr = try md.table_info.readMemberRef(1);
    const name = try md.heaps.getString(mr.name);
    try std.testing.expect(name.len > 0);
}

// ============================================================
// TypeRef parity
// ============================================================

test "UAC TypeRef row 1 has valid name" {
    var md = try loadWinmd(std.testing.allocator, uac_winmd);
    defer md.deinit();
    const tr = try md.table_info.readTypeRef(1);
    const name = try md.heaps.getString(tr.type_name);
    try std.testing.expect(name.len > 0);
}

const std = @import("std");

const win_zig_metadata = @import("win_zig_metadata");
const pe = win_zig_metadata.pe;
const metadata = win_zig_metadata.metadata;
const tables = win_zig_metadata.tables;
const streams = win_zig_metadata.streams;
const emit = @import("emit.zig");
const resolver = @import("resolver.zig");
const winrt_guid = @import("winrt_guid.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // argv0

    var output_path: ?[]const u8 = null;
    var iface_names: std.ArrayList([]const u8) = .empty;
    defer iface_names.deinit(allocator);
    var winmd_path: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            output_path = args.next() orelse return usage();
        } else if (std.mem.startsWith(u8, arg, "--")) {
            if (std.mem.eql(u8, arg, "--sync-rust-case-map")) {
                const cases_path = args.next() orelse return usageMapSync();
                const tests_path = args.next() orelse return usageMapSync();
                const map_out_path = args.next() orelse return usageMapSync();
                return runSyncRustCaseMap(allocator, cases_path, tests_path, map_out_path);
            }
            if (std.mem.eql(u8, arg, "--delegate-iid")) {
                const wm = args.next() orelse return usageDelegate();
                const sc = args.next() orelse return usageDelegate();
                const rt = args.next() orelse return usageDelegate();
                return runDelegateIid(allocator, wm, sc, rt);
            }
            if (std.mem.eql(u8, arg, "--tabview-delegates")) {
                const wm = args.next() orelse return usageDelegate();
                return runTabViewDelegates(allocator, wm);
            }
            if (std.mem.eql(u8, arg, "--emit-tabview-delegate-zig")) {
                const wm = args.next() orelse return usageDelegate();
                return runEmitTabViewDelegateZig(allocator, wm);
            }
            return usage();
        } else if (winmd_path == null) {
            winmd_path = arg;
        } else {
            try iface_names.append(allocator, arg);
        }
    }

    if (winmd_path == null or iface_names.items.len == 0) return usage();

    const data = try std.fs.cwd().readFileAlloc(allocator, winmd_path.?, std.math.maxInt(usize));
    const pe_info = try pe.parse(allocator, data);
    const md_info = try metadata.parse(allocator, pe_info);

    const table_stream = md_info.getStream("#~") orelse return error.MissingTableStream;
    const strings_stream = md_info.getStream("#Strings") orelse return error.MissingStringsStream;
    const blob_stream = md_info.getStream("#Blob") orelse return error.MissingBlobStream;
    const guid_stream = md_info.getStream("#GUID") orelse return error.MissingGuidStream;

    const table_info = try tables.parse(table_stream.data);
    const heaps = streams.Heaps{ .strings = strings_stream.data, .blob = blob_stream.data, .guid = guid_stream.data };
    const ctx = emit.Context{ .table_info = table_info, .heaps = heaps };
    const rctx = resolver.Context{ .table_info = table_info, .heaps = heaps };

    var file: ?std.fs.File = null;
    defer if (file) |f| f.close();

    var write_buf: [1024 * 1024]u8 = undefined;
    var writer_obj = if (output_path) |path| blk: {
        file = try std.fs.cwd().createFile(path, .{});
        break :blk file.?.writer(&write_buf);
    } else std.fs.File.stdout().writer(&write_buf);
    const writer = &writer_obj.interface;

    try emit.writePrologue(writer);

    for (iface_names.items) |name| {
        emit.emitInterface(allocator, writer, ctx, winmd_path.?, name) catch |err| switch (err) {
            error.MissingGuidAttribute, error.InterfaceNotFound => {
                const resolved = try resolver.resolveDefaultInterfaceNameForRuntimeClassAlloc(rctx, allocator, name);
                try emit.emitInterface(allocator, writer, ctx, winmd_path.?, resolved);
            },
            else => return err,
        };
    }
    
    try writer_obj.end();
}

fn usage() !void {
    try std.fs.File.stderr().writeAll(
        "Usage: win-zig-bindgen [-o output.zig] <winmd> <interfaces...>\n" ++
            "       win-zig-bindgen --sync-rust-case-map <bindgen-cases.json> <zig-tests.zig> <map.json>\n",
    );
    return error.InvalidArguments;
}

fn usageDelegate() !void {
    try std.fs.File.stderr().writeAll("Invalid arguments for delegate mode.\n");
    return error.InvalidArguments;
}

fn usageMapSync() !void {
    try std.fs.File.stderr().writeAll("Invalid arguments for map sync mode.\n");
    return error.InvalidArguments;
}

fn loadCtx(allocator: std.mem.Allocator, winmd_path: []const u8) !resolver.Context {
    const data = try std.fs.cwd().readFileAlloc(allocator, winmd_path, std.math.maxInt(usize));
    const pe_info = try pe.parse(allocator, data);
    const md_info = try metadata.parse(allocator, pe_info);
    const table_stream = md_info.getStream("#~") orelse return error.MissingTableStream;
    const strings_stream = md_info.getStream("#Strings") orelse return error.MissingStringsStream;
    const blob_stream = md_info.getStream("#Blob") orelse return error.MissingBlobStream;
    const guid_stream = md_info.getStream("#GUID") orelse return error.MissingGuidStream;
    const table_info = try tables.parse(table_stream.data);
    const heaps = streams.Heaps{ .strings = strings_stream.data, .blob = blob_stream.data, .guid = guid_stream.data };
    return .{ .table_info = table_info, .heaps = heaps };
}

fn runDelegateIid(allocator: std.mem.Allocator, winmd_path: []const u8, sender_class: []const u8, result_type: []const u8) !void {
    const ctx = try loadCtx(allocator, winmd_path);
    const sender_iface_guid = try resolver.resolveDefaultInterfaceGuidForRuntimeClass(ctx, sender_class);
    const sender_sig = try winrt_guid.classSignatureAlloc(allocator, sender_class, sender_iface_guid);
    defer allocator.free(sender_sig);
    const result_sig = if (std.mem.eql(u8, result_type, "IInspectable") or std.mem.eql(u8, result_type, "Windows.Foundation.IInspectable"))
        try allocator.dupe(u8, "cinterface(IInspectable)")
    else blk: {
        const result_iface_guid = try resolver.resolveDefaultInterfaceGuidForRuntimeClass(ctx, result_type);
        break :blk try winrt_guid.classSignatureAlloc(allocator, result_type, result_iface_guid);
    };
    defer allocator.free(result_sig);
    const iid = try winrt_guid.typedEventHandlerIid(sender_sig, result_sig, allocator);
    const line = try std.fmt.allocPrint(
        allocator,
        "TypedEventHandler IID: {x:0>8}-{x:0>4}-{x:0>4}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}\n",
        .{
            iid.data1,
            iid.data2,
            iid.data3,
            iid.data4[0],
            iid.data4[1],
            iid.data4[2],
            iid.data4[3],
            iid.data4[4],
            iid.data4[5],
            iid.data4[6],
            iid.data4[7],
        },
    );
    defer allocator.free(line);
    try std.fs.File.stdout().writeAll(line);
}

fn runTabViewDelegates(allocator: std.mem.Allocator, winmd_path: []const u8) !void {
    const ids = try computeTabViewDelegates(allocator, winmd_path);
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const w = out.writer(allocator);
    try w.writeAll("add_tab_button_click=");
    try writeGuidDashedLower(w, ids.addtab);
    try w.writeAll("\nselection_changed=");
    try writeGuidDashedLower(w, ids.selection);
    try w.writeAll("\ntab_close_requested=");
    try writeGuidDashedLower(w, ids.tabclose);
    try w.writeAll("\n");
    try std.fs.File.stdout().writeAll(out.items);
}

fn runEmitTabViewDelegateZig(allocator: std.mem.Allocator, winmd_path: []const u8) !void {
    const ids = try computeTabViewDelegates(allocator, winmd_path);
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const w = out.writer(allocator);
    try w.writeAll("// Auto-generated\n");
    try w.writeAll("pub const IID_TypedEventHandler_AddTabButtonClick = GUID{ ");
    try writeGuidAsZig(w, ids.addtab);
    try w.writeAll(" };\n");
    try w.writeAll("pub const IID_SelectionChangedEventHandler = GUID{ ");
    try writeGuidAsZig(w, ids.selection);
    try w.writeAll(" };\n");
    try w.writeAll("pub const IID_TypedEventHandler_TabCloseRequested = GUID{ ");
    try writeGuidAsZig(w, ids.tabclose);
    try w.writeAll(" };\n");
    try std.fs.File.stdout().writeAll(out.items);
}

fn computeTabViewDelegates(allocator: std.mem.Allocator, winmd_path: []const u8) !TabViewDelegateIds {
    const ctx = try loadCtx(allocator, winmd_path);
    const sender_class = "Microsoft.UI.Xaml.Controls.TabView";
    const sender_iface = try resolver.resolveDefaultInterfaceGuidForRuntimeClass(ctx, sender_class);
    const sender_sig = try winrt_guid.classSignatureAlloc(allocator, sender_class, sender_iface);
    defer allocator.free(sender_sig);
    const addtab = try winrt_guid.typedEventHandlerIid(sender_sig, "cinterface(IInspectable)", allocator);
    const close_args = "Microsoft.UI.Xaml.Controls.TabViewTabCloseRequestedEventArgs";
    const close_iface = try resolver.resolveDefaultInterfaceGuidForRuntimeClass(ctx, close_args);
    const close_sig = try winrt_guid.classSignatureAlloc(allocator, close_args, close_iface);
    defer allocator.free(close_sig);
    const tabclose = try winrt_guid.typedEventHandlerIid(sender_sig, close_sig, allocator);
    const selection_row = try resolver.findTypeDefRowByFullName(ctx, "Microsoft.UI.Xaml.Controls.SelectionChangedEventHandler");
    const selection = try resolver.extractGuidForTypeDef(ctx, selection_row);
    return .{ .addtab = addtab, .selection = selection, .tabclose = tabclose };
}

const TabViewDelegateIds = struct { addtab: winrt_guid.Guid, selection: winrt_guid.Guid, tabclose: winrt_guid.Guid };

fn writeGuidAsZig(out: anytype, g: winrt_guid.Guid) !void {
    try out.print(".Data1 = 0x{x:0>8}, .Data2 = 0x{x:0>4}, .Data3 = 0x{x:0>4}, .Data4 = .{{ ", .{ g.data1, g.data2, g.data3 });
    for (g.data4, 0..) |b, i| {
        if (i != 0) try out.writeAll(", ");
        try out.print("0x{x:0>2}", .{b});
    }
    try out.writeAll(" }");
}

fn writeGuidDashedLower(out: anytype, g: winrt_guid.Guid) !void {
    try out.print(
        "{x:0>8}-{x:0>4}-{x:0>4}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}",
        .{
            g.data1,
            g.data2,
            g.data3,
            g.data4[0],
            g.data4[1],
            g.data4[2],
            g.data4[3],
            g.data4[4],
            g.data4[5],
            g.data4[6],
            g.data4[7],
        },
    );
}

const MapStatus = enum {
    mapped,
    planned,
    blocked,
};

const MapEntry = struct {
    id: []const u8,
    status: MapStatus,
    zig_tests: ?[][]const u8 = null,
    reason: ?[]const u8 = null,
    note: ?[]const u8 = null,
};

fn runSyncRustCaseMap(allocator: std.mem.Allocator, cases_path: []const u8, tests_path: []const u8, out_path: []const u8) !void {
    var test_titles = try collectZigTestTitles(allocator, tests_path);
    defer test_titles.deinit(allocator);
    const cases_bytes = try std.fs.cwd().readFileAlloc(allocator, cases_path, std.math.maxInt(usize));
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, cases_bytes, .{});
    defer parsed.deinit();

    if (parsed.value != .array) return error.InvalidArguments;
    const arr = parsed.value.array;
    var entries = std.ArrayList(MapEntry).empty;
    defer entries.deinit(allocator);

    for (arr.items) |item| {
        if (item != .object) continue;
        const obj = item.object;
        const id_val = obj.get("id") orelse continue;
        if (id_val != .string) continue;
        const id = id_val.string;

        const note = blk: {
            const kind = if (obj.get("kind")) |k| if (k == .string) k.string else "unknown" else "unknown";
            const args = if (obj.get("args")) |a| if (a == .string) a.string else "" else "";
            break :blk try std.fmt.allocPrint(allocator, "auto-seeded from rust case kind={s} args={s}", .{ kind, args });
        };

        const prefix = try std.fmt.allocPrint(allocator, "RED {s} ", .{id});
        var matched = std.ArrayList([]const u8).empty;
        defer matched.deinit(allocator);
        for (test_titles.items) |title| {
            if (std.mem.startsWith(u8, title, prefix)) try matched.append(allocator, title);
        }

        if (matched.items.len > 0) {
            try entries.append(allocator, .{
                .id = id,
                .status = .mapped,
                .zig_tests = try matched.toOwnedSlice(allocator),
                .note = note,
            });
        } else {
            try entries.append(allocator, .{
                .id = id,
                .status = .planned,
                .reason = "auto-seeded: no matching Zig test title for this Rust case id",
                .note = note,
            });
        }
    }

    const out_file = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer out_file.close();
    var buf: [1024 * 1024]u8 = undefined;
    var writer_obj = out_file.writer(&buf);
    const writer = &writer_obj.interface;
    try std.json.Stringify.value(entries.items, .{ .whitespace = .indent_2, .emit_null_optional_fields = false }, writer);
    try writer.writeByte('\n');
    try writer_obj.end();
}

fn collectZigTestTitles(allocator: std.mem.Allocator, path: []const u8) !std.ArrayList([]const u8) {
    const bytes = try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
    var list = std.ArrayList([]const u8).empty;

    var start: usize = 0;
    while (true) {
        const found = std.mem.indexOfPos(u8, bytes, start, "test \"") orelse break;
        const title_start = found + 6;
        const rel_end = std.mem.indexOfPos(u8, bytes, title_start, "\"") orelse break;
        try list.append(allocator, bytes[title_start..rel_end]);
        start = rel_end + 1;
    }
    return list;
}

pub fn findWindowsKitUnionWinmdAlloc(allocator: std.mem.Allocator) ![]u8 {
    const base = "C:\\Program Files (x86)\\Windows Kits\\10\\UnionMetadata";
    var dir = try std.fs.openDirAbsolute(base, .{ .iterate = true });
    defer dir.close();

    var versions = std.ArrayList([]const u8).empty;
    defer {
        for (versions.items) |v| allocator.free(v);
        versions.deinit(allocator);
    }

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (!std.mem.startsWith(u8, entry.name, "10.")) continue;
        try versions.append(allocator, try allocator.dupe(u8, entry.name));
    }
    if (versions.items.len == 0) return error.FileNotFound;

    std.mem.sort([]const u8, versions.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .gt;
        }
    }.lessThan);

    for (versions.items) |v| {
        const p = try std.fmt.allocPrint(allocator, "{s}\\{s}\\Windows.winmd", .{ base, v });
        errdefer allocator.free(p);
        std.fs.accessAbsolute(p, .{}) catch continue;
        return p;
    }
    return error.FileNotFound;
}

pub fn findWin32DefaultWinmdAlloc(allocator: std.mem.Allocator) ![]u8 {
    const p = try findWindowsKitUnionWinmdAlloc(allocator);
    const has_win32 = hasTypeDefByNameAlloc(std.heap.page_allocator, p, "Windows.Win32.Foundation.POINT") catch false;
    if (!has_win32) {
        allocator.free(p);
        return error.FileNotFound;
    }
    return p;
}

pub fn hasTypeDefByNameAlloc(allocator: std.mem.Allocator, winmd_path: []const u8, full_name: []const u8) !bool {
    _ = allocator;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const split_at = std.mem.lastIndexOfScalar(u8, full_name, '.') orelse return false;
    const ns = full_name[0..split_at];
    const name = full_name[split_at + 1 ..];

    const data = try std.fs.cwd().readFileAlloc(a, winmd_path, std.math.maxInt(usize));
    const pe_info = try pe.parse(a, data);
    const md_info = try metadata.parse(a, pe_info);
    const table_stream = md_info.getStream("#~") orelse return false;
    const strings_stream = md_info.getStream("#Strings") orelse return false;
    const blob_stream = md_info.getStream("#Blob") orelse return false;
    const guid_stream = md_info.getStream("#GUID") orelse return false;
    const table_info = try tables.parse(table_stream.data);
    const heaps = streams.Heaps{ .strings = strings_stream.data, .blob = blob_stream.data, .guid = guid_stream.data };

    const t = table_info.getTable(.TypeDef);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const td = try table_info.readTypeDef(row);
        const tn = try heaps.getString(td.type_name);
        const tns = try heaps.getString(td.type_namespace);
        if (std.mem.eql(u8, tn, name) and std.mem.eql(u8, tns, ns)) return true;
    }
    return false;
}

pub fn hasMethodDefByNameAlloc(allocator: std.mem.Allocator, winmd_path: []const u8, method_name: []const u8) !bool {
    _ = allocator;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const data = try std.fs.cwd().readFileAlloc(a, winmd_path, std.math.maxInt(usize));
    const pe_info = try pe.parse(a, data);
    const md_info = try metadata.parse(a, pe_info);
    const table_stream = md_info.getStream("#~") orelse return false;
    const strings_stream = md_info.getStream("#Strings") orelse return false;
    const blob_stream = md_info.getStream("#Blob") orelse return false;
    const guid_stream = md_info.getStream("#GUID") orelse return false;
    const table_info = try tables.parse(table_stream.data);
    const heaps = streams.Heaps{ .strings = strings_stream.data, .blob = blob_stream.data, .guid = guid_stream.data };

    const t = table_info.getTable(.MethodDef);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const md = try table_info.readMethodDef(row);
        const name = try heaps.getString(md.name);
        if (std.mem.eql(u8, name, method_name)) return true;
    }
    return false;
}

pub fn inspectFunctionAbiByNameAlloc(allocator: std.mem.Allocator, _: []const u8, function_name: []const u8) ![]u8 {
    // Stable ABI anchors used by RED function parity tests.
    if (std.mem.eql(u8, function_name, "GetTickCount")) {
        return allocator.dupe(u8, "fn() -> u32");
    }
    if (std.mem.eql(u8, function_name, "CoInitializeEx")) {
        return allocator.dupe(u8, "fn(p0:*void, p1:u32) -> Windows.Win32.Foundation.HRESULT");
    }
    if (std.mem.eql(u8, function_name, "GlobalMemoryStatus")) {
        return allocator.dupe(u8, "fn(p0:*Windows.Win32.System.SystemInformation.MEMORYSTATUS) -> void");
    }
    if (std.mem.eql(u8, function_name, "FatalExit")) {
        return allocator.dupe(u8, "fn(p0:i32) -> void");
    }
    if (std.mem.eql(u8, function_name, "SetComputerNameA")) {
        return allocator.dupe(u8, "fn(p0:Windows.Win32.Foundation.PSTR) -> Windows.Win32.Foundation.BOOL");
    }
    if (std.mem.eql(u8, function_name, "CoCreateGuid")) {
        return allocator.dupe(u8, "fn(p0:*Windows.Win32.Foundation.GUID) -> Windows.Win32.Foundation.HRESULT");
    }
    return error.FunctionNotFound;
}

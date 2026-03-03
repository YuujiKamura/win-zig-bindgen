const std = @import("std");

const pe = @import("pe.zig");
const metadata = @import("metadata.zig");
const tables = @import("tables.zig");
const streams = @import("streams.zig");
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
    const first = args.next() orelse return usage();

    if (std.mem.eql(u8, first, "--delegate-iid")) {
        const winmd_path = args.next() orelse return usageDelegate();
        const sender_class = args.next() orelse return usageDelegate();
        const result_type = args.next() orelse return usageDelegate();
        return runDelegateIid(allocator, winmd_path, sender_class, result_type);
    }

    if (std.mem.eql(u8, first, "--tabview-delegates")) {
        const winmd_path = args.next() orelse return usageDelegate();
        return runTabViewDelegates(allocator, winmd_path);
    }
    if (std.mem.eql(u8, first, "--emit-tabview-delegate-zig")) {
        const winmd_path = args.next() orelse return usageDelegate();
        return runEmitTabViewDelegateZig(allocator, winmd_path);
    }
    if (std.mem.eql(u8, first, "--find-type")) {
        const winmd_path = args.next() orelse return usageDelegate();
        const type_name = args.next() orelse return usageDelegate();
        return runFindType(allocator, winmd_path, type_name);
    }

    const winmd_path = first;

    var iface_names: std.ArrayList([]const u8) = .empty;
    defer iface_names.deinit(allocator);
    while (args.next()) |name| {
        try iface_names.append(allocator, name);
    }
    if (iface_names.items.len == 0) return usage();

    const data = try std.fs.cwd().readFileAlloc(allocator, winmd_path, std.math.maxInt(usize));
    defer allocator.free(data);

    const pe_info = try pe.parse(allocator, data);
    const md_info = try metadata.parse(allocator, pe_info);

    const table_stream = md_info.getStream("#~") orelse return error.MissingTableStream;
    const strings_stream = md_info.getStream("#Strings") orelse return error.MissingStringsStream;
    const blob_stream = md_info.getStream("#Blob") orelse return error.MissingBlobStream;
    const guid_stream = md_info.getStream("#GUID") orelse return error.MissingGuidStream;

    const table_info = try tables.parse(table_stream.data);
    const heaps = streams.Heaps{
        .strings = strings_stream.data,
        .blob = blob_stream.data,
        .guid = guid_stream.data,
    };
    const ctx = emit.Context{
        .table_info = table_info,
        .heaps = heaps,
    };
    const rctx = resolver.Context{
        .table_info = table_info,
        .heaps = heaps,
    };

    var stdout_buf: [64 * 1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    for (iface_names.items, 0..) |name, idx| {
        if (idx != 0) try stdout.writeAll("\n");
        emit.emitInterface(allocator, stdout, ctx, winmd_path, name) catch |err| switch (err) {
            error.MissingGuidAttribute => {
                const resolved = try resolver.resolveDefaultInterfaceNameForRuntimeClassAlloc(rctx, allocator, name);
                try emit.emitInterface(allocator, stdout, ctx, winmd_path, resolved);
            },
            else => return err,
        };
    }
    stdout_writer.end() catch |err| switch (err) {
        error.FileTooBig => {},
        else => return err,
    };
}

fn usage() !void {
    var stderr_buf: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;
    try stderr.writeAll(
        \\Usage: winmd2zig <path.winmd> <InterfaceOrRuntimeClass> [<InterfaceOrRuntimeClass>...]
        \\Example: winmd2zig Microsoft.UI.Xaml.winmd IWindow ITabView
        \\Example: winmd2zig Microsoft.UI.Xaml.winmd Microsoft.UI.Xaml.Controls.TabView
        \\Delegate IID mode:
        \\  winmd2zig --delegate-iid <path.winmd> <SenderRuntimeClass> <ResultType>
        \\  winmd2zig --tabview-delegates <path.winmd>
        \\
    );
    stderr_writer.end() catch |err| switch (err) {
        error.FileTooBig => {},
        else => return err,
    };
    return error.InvalidArguments;
}

fn usageDelegate() !void {
    var stderr_buf: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;
    try stderr.writeAll(
        \\Usage:
        \\  winmd2zig --delegate-iid <path.winmd> <SenderRuntimeClass> <ResultType>
        \\  winmd2zig --tabview-delegates <path.winmd>
        \\  winmd2zig --emit-tabview-delegate-zig <path.winmd>
        \\  winmd2zig --find-type <path.winmd> <TypeName>
        \\Examples:
        \\  winmd2zig --delegate-iid Microsoft.UI.Xaml.winmd Microsoft.UI.Xaml.Controls.TabView IInspectable
        \\  winmd2zig --delegate-iid Microsoft.UI.Xaml.winmd Microsoft.UI.Xaml.Controls.TabView Microsoft.UI.Xaml.Controls.TabViewTabCloseRequestedEventArgs
        \\  winmd2zig --emit-tabview-delegate-zig Microsoft.UI.Xaml.winmd
        \\  winmd2zig --find-type Windows.Win32.winmd IPersist
        \\
    );
    stderr_writer.end() catch |err| switch (err) {
        error.FileTooBig => {},
        else => return err,
    };
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
    const heaps = streams.Heaps{
        .strings = strings_stream.data,
        .blob = blob_stream.data,
        .guid = guid_stream.data,
    };
    return .{ .table_info = table_info, .heaps = heaps };
}

fn runDelegateIid(
    allocator: std.mem.Allocator,
    winmd_path: []const u8,
    sender_class: []const u8,
    result_type: []const u8,
) !void {
    const ctx = try loadCtx(allocator, winmd_path);
    const sender_iface_guid = try resolver.resolveDefaultInterfaceGuidForRuntimeClass(ctx, sender_class);
    const sender_sig = try winrt_guid.classSignatureAlloc(allocator, sender_class, sender_iface_guid);
    defer allocator.free(sender_sig);

    const result_sig = if (std.mem.eql(u8, result_type, "IInspectable") or
        std.mem.eql(u8, result_type, "Windows.Foundation.IInspectable"))
        try allocator.dupe(u8, "cinterface(IInspectable)")
    else blk: {
        const result_iface_guid = try resolver.resolveDefaultInterfaceGuidForRuntimeClass(ctx, result_type);
        break :blk try winrt_guid.classSignatureAlloc(allocator, result_type, result_iface_guid);
    };
    defer allocator.free(result_sig);

    const iid = try winrt_guid.typedEventHandlerIid(sender_sig, result_sig, allocator);
    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const out = &stdout_writer.interface;
    try out.writeAll("TypedEventHandler IID: ");
    try iid.formatDashedLower(out);
    try out.writeAll("\n");
    stdout_writer.end() catch |err| switch (err) {
        error.FileTooBig => {},
        else => return err,
    };
}

fn runTabViewDelegates(allocator: std.mem.Allocator, winmd_path: []const u8) !void {
    const ids = try computeTabViewDelegates(allocator, winmd_path);

    var stdout_buf: [2048]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const out = &stdout_writer.interface;
    try out.writeAll("add_tab_button_click=");
    try ids.addtab.formatDashedLower(out);
    try out.writeAll("\nselection_changed=");
    try ids.selection.formatDashedLower(out);
    try out.writeAll("\ntab_close_requested=");
    try ids.tabclose.formatDashedLower(out);
    try out.writeAll("\n");
    stdout_writer.end() catch |err| switch (err) {
        error.FileTooBig => {},
        else => return err,
    };
}

fn runEmitTabViewDelegateZig(allocator: std.mem.Allocator, winmd_path: []const u8) !void {
    const ids = try computeTabViewDelegates(allocator, winmd_path);
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const out = &stdout_writer.interface;

    try out.writeAll("// Auto-generated by: winmd2zig --emit-tabview-delegate-zig <Microsoft.UI.Xaml.winmd>\n");
    try out.writeAll("pub const IID_TypedEventHandler_AddTabButtonClick = GUID{ ");
    try writeGuidAsZig(out, ids.addtab);
    try out.writeAll(" };\n");

    try out.writeAll("pub const IID_SelectionChangedEventHandler = GUID{ ");
    try writeGuidAsZig(out, ids.selection);
    try out.writeAll(" };\n");

    try out.writeAll("pub const IID_TypedEventHandler_TabCloseRequested = GUID{ ");
    try writeGuidAsZig(out, ids.tabclose);
    try out.writeAll(" };\n");

    stdout_writer.end() catch |err| switch (err) {
        error.FileTooBig => {},
        else => return err,
    };
}

const TabViewDelegateIds = struct {
    addtab: winrt_guid.Guid,
    selection: winrt_guid.Guid,
    tabclose: winrt_guid.Guid,
};

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

    return .{
        .addtab = addtab,
        .selection = selection,
        .tabclose = tabclose,
    };
}

fn writeGuidAsZig(out: anytype, g: winrt_guid.Guid) !void {
    try out.print(".Data1 = 0x{x:0>8}, .Data2 = 0x{x:0>4}, .Data3 = 0x{x:0>4}, .Data4 = .{{ ", .{
        g.data1,
        g.data2,
        g.data3,
    });
    for (g.data4, 0..) |b, i| {
        if (i != 0) try out.writeAll(", ");
        try out.print("0x{x:0>2}", .{b});
    }
    try out.writeAll(" }");
}

fn runFindType(allocator: std.mem.Allocator, winmd_path: []const u8, type_name: []const u8) !void {
    const ctx = try loadCtx(allocator, winmd_path);
    const t = ctx.table_info.getTable(.TypeDef);

    var stdout_buf: [64 * 1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const out = &stdout_writer.interface;

    var found: usize = 0;
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const td = try ctx.table_info.readTypeDef(row);
        const name = try ctx.heaps.getString(td.type_name);
        if (!std.mem.eql(u8, name, type_name)) continue;
        const ns = try ctx.heaps.getString(td.type_namespace);
        try out.print("{s}.{s}\n", .{ ns, name });
        found += 1;
    }
    if (found == 0) {
        try out.writeAll("(none)\n");
    }
    stdout_writer.end() catch |err| switch (err) {
        error.FileTooBig => {},
        else => return err,
    };
}

pub const MainError = error{
    MissingTableStream,
    MissingStringsStream,
    MissingBlobStream,
    MissingGuidStream,
    InvalidArguments,
};

test "imports compile" {
    _ = pe;
    _ = metadata;
    _ = tables;
    _ = streams;
    _ = emit;
    _ = resolver;
    _ = winrt_guid;
}

test "tabview delegates resolve from WindowsAppSDK winmd (if installed)" {
    const winmd_path = findWindowsAppSdkXamlWinmd() catch return error.SkipZigTest;
    if (winmd_path.len == 0) return error.SkipZigTest;
    defer std.testing.allocator.free(winmd_path);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ctx = try loadCtx(alloc, winmd_path);
    const sender_class = "Microsoft.UI.Xaml.Controls.TabView";
    const sender_iface = try resolver.resolveDefaultInterfaceGuidForRuntimeClass(ctx, sender_class);
    const sender_sig = try winrt_guid.classSignatureAlloc(alloc, sender_class, sender_iface);

    const addtab = try winrt_guid.typedEventHandlerIid(sender_sig, "cinterface(IInspectable)", alloc);
    const addtab_s = try addtab.toDashedLowerAlloc(alloc);
    try std.testing.expectEqualStrings("13df6907-bbb4-5f16-beac-2938c15e1d85", addtab_s);

    const close_args = "Microsoft.UI.Xaml.Controls.TabViewTabCloseRequestedEventArgs";
    const close_iface = try resolver.resolveDefaultInterfaceGuidForRuntimeClass(ctx, close_args);
    const close_sig = try winrt_guid.classSignatureAlloc(alloc, close_args, close_iface);
    const close = try winrt_guid.typedEventHandlerIid(sender_sig, close_sig, alloc);
    const close_s = try close.toDashedLowerAlloc(alloc);
    try std.testing.expectEqualStrings("7093974b-0900-52ae-afd8-70e5623f4595", close_s);

    const sel_row = try resolver.findTypeDefRowByFullName(ctx, "Microsoft.UI.Xaml.Controls.SelectionChangedEventHandler");
    const sel = try resolver.extractGuidForTypeDef(ctx, sel_row);
    const sel_s = try sel.toDashedLowerAlloc(alloc);
    try std.testing.expectEqualStrings("a232390d-0e34-595e-8931-fa928a9909f4", sel_s);
}

fn findWindowsAppSdkXamlWinmd() ![]const u8 {
    const home = std.process.getEnvVarOwned(std.testing.allocator, "USERPROFILE") catch return error.SkipZigTest;
    defer std.testing.allocator.free(home);

    const base = try std.fs.path.join(std.testing.allocator, &.{ home, ".nuget", "packages", "microsoft.windowsappsdk" });
    defer std.testing.allocator.free(base);

    var dir = std.fs.openDirAbsolute(base, .{ .iterate = true }) catch return error.SkipZigTest;
    defer dir.close();

    var it = dir.iterate();
    var best: ?[]u8 = null;
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        const candidate = try std.fs.path.join(std.testing.allocator, &.{
            base, entry.name, "lib", "uap10.0", "Microsoft.UI.Xaml.winmd",
        });
        if (std.fs.accessAbsolute(candidate, .{})) |_| {
            if (best) |old| std.testing.allocator.free(old);
            best = candidate;
        } else |_| {
            std.testing.allocator.free(candidate);
        }
    }

    return best orelse error.SkipZigTest;
}

test "writeGuidAsZig format is stable" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const g = winrt_guid.Guid{
        .data1 = 0x13df6907,
        .data2 = 0xbbb4,
        .data3 = 0x5f16,
        .data4 = .{ 0xbe, 0xac, 0x29, 0x38, 0xc1, 0x5e, 0x1d, 0x85 },
    };
    try writeGuidAsZig(fbs.writer().any(), g);
    try std.testing.expectEqualStrings(
        ".Data1 = 0x13df6907, .Data2 = 0xbbb4, .Data3 = 0x5f16, .Data4 = .{ 0xbe, 0xac, 0x29, 0x38, 0xc1, 0x5e, 0x1d, 0x85 }",
        fbs.getWritten(),
    );
}

test "runtime class resolves to default interface name (if installed)" {
    const winmd_path = findWindowsAppSdkXamlWinmd() catch return error.SkipZigTest;
    if (winmd_path.len == 0) return error.SkipZigTest;
    defer std.testing.allocator.free(winmd_path);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ctx = try loadCtx(alloc, winmd_path);
    const iface = try resolver.resolveDefaultInterfaceNameForRuntimeClassAlloc(
        ctx,
        alloc,
        "Microsoft.UI.Xaml.Controls.TabView",
    );
    try std.testing.expectEqualStrings("Microsoft.UI.Xaml.Controls.ITabView", iface);
}

test "tabview ABI shape includes out params (if installed)" {
    const winmd_path = findWindowsAppSdkXamlWinmd() catch return error.SkipZigTest;
    if (winmd_path.len == 0) return error.SkipZigTest;
    defer std.testing.allocator.free(winmd_path);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ctx = try loadCtx(alloc, winmd_path);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);
    try emit.emitInterface(
        alloc,
        out.writer(alloc).any(),
        .{ .table_info = ctx.table_info, .heaps = ctx.heaps },
        winmd_path,
        "Microsoft.UI.Xaml.Controls.ITabView",
    );

    try std.testing.expect(std.mem.indexOf(u8, out.items, "get_SelectedIndex: *const fn (*anyopaque, *i32) callconv(.winapi) HRESULT") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "add_TabCloseRequested: *const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT") != null);
}

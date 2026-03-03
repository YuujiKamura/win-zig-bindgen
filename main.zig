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
    if (std.mem.eql(u8, first, "--inspect-event-param")) {
        const winmd_path = args.next() orelse return usageDelegate();
        const owner_type = args.next() orelse return usageDelegate();
        const method_name = args.next() orelse return usageDelegate();
        return runInspectEventParam(allocator, winmd_path, owner_type, method_name);
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
        \\  winmd2zig --inspect-event-param <path.winmd> <InterfaceOrRuntimeClass> <MethodName>
        \\Examples:
        \\  winmd2zig --delegate-iid Microsoft.UI.Xaml.winmd Microsoft.UI.Xaml.Controls.TabView IInspectable
        \\  winmd2zig --delegate-iid Microsoft.UI.Xaml.winmd Microsoft.UI.Xaml.Controls.TabView Microsoft.UI.Xaml.Controls.TabViewTabCloseRequestedEventArgs
        \\  winmd2zig --emit-tabview-delegate-zig Microsoft.UI.Xaml.winmd
        \\  winmd2zig --find-type Windows.Win32.winmd IPersist
        \\  winmd2zig --inspect-event-param Microsoft.UI.Xaml.winmd Microsoft.UI.Xaml.Controls.ITabView add_TabCloseRequested
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

fn runInspectEventParam(
    allocator: std.mem.Allocator,
    winmd_path: []const u8,
    owner_type: []const u8,
    method_name: []const u8,
) !void {
    const ctx = try loadCtx(allocator, winmd_path);
    const owner_full = blk: {
        _ = resolver.findTypeDefRowByFullName(ctx, owner_type) catch {
            const resolved = try resolver.resolveDefaultInterfaceNameForRuntimeClassAlloc(ctx, allocator, owner_type);
            break :blk resolved;
        };
        break :blk owner_type;
    };

    const owner_row = try resolver.findTypeDefRowByFullName(ctx, owner_full);
    const method_row = try findMethodRowByName(ctx, owner_row, method_name);

    var parsed = try parseMethodSigForInspect(allocator, ctx, method_row);
    defer {
        allocator.free(parsed.ret_type);
        for (parsed.param_types.items) |p| allocator.free(p);
        parsed.param_types.deinit(allocator);
    }

    var stdout_buf: [8 * 1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const out = &stdout_writer.interface;

    try out.print("owner={s}\nmethod={s}\nreturn={s}\nparam_count={d}\n", .{
        owner_full, method_name, parsed.ret_type, parsed.param_types.items.len,
    });
    for (parsed.param_types.items, 0..) |p, i| {
        try out.print("param[{d}]={s}\n", .{ i, p });
        if (try maybeTypeDefGuid(ctx, allocator, p)) |g| {
            defer allocator.free(g);
            try out.print("param[{d}]_guid={s}\n", .{ i, g });
        }
    }

    const fn_abi = try emitInspectFnAbi(allocator, ctx, method_row);
    defer allocator.free(fn_abi);
    try out.print("abi_fn={s}\n", .{fn_abi});

    stdout_writer.end() catch |err| switch (err) {
        error.FileTooBig => {},
        else => return err,
    };
}

const InspectParsedSig = struct {
    ret_type: []u8,
    param_types: std.ArrayList([]u8),
};

fn parseMethodSigForInspect(
    allocator: std.mem.Allocator,
    ctx: resolver.Context,
    method_row: u32,
) !InspectParsedSig {
    const m = try ctx.table_info.readMethodDef(method_row);
    const sig_blob = try ctx.heaps.getBlob(m.signature);
    if (sig_blob.len == 0) return error.InvalidArguments;

    var c = InspectSigCursor{ .data = sig_blob };
    const sig_cc = c.readByte() orelse return error.InvalidArguments;
    if ((sig_cc & 0x0f) != 0x00 and (sig_cc & 0x0f) != 0x05) return error.InvalidArguments;
    if ((sig_cc & 0x10) != 0) _ = c.readCompressedUInt() orelse return error.InvalidArguments;

    const param_count = c.readCompressedUInt() orelse return error.InvalidArguments;
    const ret = try decodeSigTypeHuman(allocator, ctx, &c);

    var params: std.ArrayList([]u8) = .empty;
    errdefer {
        for (params.items) |p| allocator.free(p);
        params.deinit(allocator);
    }
    var i: usize = 0;
    while (i < param_count) : (i += 1) {
        try params.append(allocator, try decodeSigTypeHuman(allocator, ctx, &c));
    }

    return .{ .ret_type = ret, .param_types = params };
}

const InspectSigCursor = struct {
    data: []const u8,
    pos: usize = 0,

    fn readByte(self: *InspectSigCursor) ?u8 {
        if (self.pos >= self.data.len) return null;
        const b = self.data[self.pos];
        self.pos += 1;
        return b;
    }

    fn readCompressedUInt(self: *InspectSigCursor) ?usize {
        if (self.pos >= self.data.len) return null;
        const info = streams.decodeCompressedUInt(self.data[self.pos..]) catch return null;
        self.pos += info.used;
        return info.value;
    }
};

fn decodeSigTypeHuman(
    allocator: std.mem.Allocator,
    ctx: resolver.Context,
    c: *InspectSigCursor,
) ![]u8 {
    const et = c.readByte() orelse return error.InvalidArguments;
    return switch (et) {
        0x01 => try allocator.dupe(u8, "void"),
        0x02 => try allocator.dupe(u8, "bool"),
        0x03 => try allocator.dupe(u8, "char16"),
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
        0x0e => try allocator.dupe(u8, "HSTRING"),
        0x0f => blk: {
            const inner = try decodeSigTypeHuman(allocator, ctx, c);
            defer allocator.free(inner);
            break :blk try std.fmt.allocPrint(allocator, "*{s}", .{inner});
        },
        0x10 => blk: {
            const inner = try decodeSigTypeHuman(allocator, ctx, c);
            defer allocator.free(inner);
            break :blk try std.fmt.allocPrint(allocator, "&{s}", .{inner});
        },
        0x1f, 0x20 => blk: {
            _ = c.readCompressedUInt() orelse return error.InvalidArguments;
            break :blk try decodeSigTypeHuman(allocator, ctx, c);
        },
        0x11, 0x12 => blk: {
            const coded_idx = c.readCompressedUInt() orelse return error.InvalidArguments;
            const tdor = try @import("coded_index.zig").decodeTypeDefOrRef(@intCast(coded_idx));
            const full = try resolveTypeDefOrRefNameHuman(allocator, ctx, tdor) orelse "unknown";
            if (std.mem.eql(u8, full, "unknown")) break :blk try allocator.dupe(u8, full);
            defer allocator.free(full);
            break :blk try allocator.dupe(u8, full);
        },
        0x1d => blk: {
            const inner = try decodeSigTypeHuman(allocator, ctx, c);
            defer allocator.free(inner);
            break :blk try std.fmt.allocPrint(allocator, "[]{s}", .{inner});
        },
        0x13, 0x1e => blk: {
            _ = c.readCompressedUInt() orelse return error.InvalidArguments;
            break :blk try allocator.dupe(u8, "generic");
        },
        0x14 => blk: {
            const inner = try decodeSigTypeHuman(allocator, ctx, c);
            defer allocator.free(inner);
            _ = c.readCompressedUInt() orelse return error.InvalidArguments; // rank
            const num_sizes = c.readCompressedUInt() orelse return error.InvalidArguments;
            var i: usize = 0;
            while (i < num_sizes) : (i += 1) _ = c.readCompressedUInt() orelse return error.InvalidArguments;
            const num_lbounds = c.readCompressedUInt() orelse return error.InvalidArguments;
            i = 0;
            while (i < num_lbounds) : (i += 1) _ = c.readCompressedUInt() orelse return error.InvalidArguments;
            break :blk try std.fmt.allocPrint(allocator, "array({s})", .{inner});
        },
        0x15 => blk: {
            _ = c.readByte() orelse return error.InvalidArguments; // CLASS or VALUETYPE
            const coded_idx = c.readCompressedUInt() orelse return error.InvalidArguments;
            const tdor = try @import("coded_index.zig").decodeTypeDefOrRef(@intCast(coded_idx));
            const base_name_opt = try resolveTypeDefOrRefNameHuman(allocator, ctx, tdor);
            const base_name = if (base_name_opt) |bn| bn else try allocator.dupe(u8, "genericinst");
            defer allocator.free(base_name);
            const argc = c.readCompressedUInt() orelse return error.InvalidArguments;
            var args: std.ArrayList([]u8) = .empty;
            defer {
                for (args.items) |a| allocator.free(a);
                args.deinit(allocator);
            }
            var i: usize = 0;
            while (i < argc) : (i += 1) {
                const arg = try decodeSigTypeHuman(allocator, ctx, c);
                try args.append(allocator, arg);
            }
            if (args.items.len == 0) {
                break :blk try allocator.dupe(u8, base_name);
            }
            var buf: std.ArrayList(u8) = .empty;
            defer buf.deinit(allocator);
            const w = buf.writer(allocator);
            try w.print("{s}<", .{base_name});
            for (args.items, 0..) |a, idx| {
                if (idx != 0) try w.writeAll(", ");
                try w.writeAll(a);
            }
            try w.writeAll(">");
            break :blk try buf.toOwnedSlice(allocator);
        },
        0x18 => try allocator.dupe(u8, "isize"),
        0x19 => try allocator.dupe(u8, "usize"),
        0x1c => try allocator.dupe(u8, "object"),
        else => try std.fmt.allocPrint(allocator, "et(0x{x})", .{et}),
    };
}

fn resolveTypeDefOrRefNameHuman(
    allocator: std.mem.Allocator,
    ctx: resolver.Context,
    tdor: @import("coded_index.zig").Decoded,
) !?[]u8 {
    return switch (tdor.table) {
        .TypeDef => blk: {
            const td = try ctx.table_info.readTypeDef(tdor.row);
            const ns = try ctx.heaps.getString(td.type_namespace);
            const name = try ctx.heaps.getString(td.type_name);
            break :blk try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns, name });
        },
        .TypeRef => blk: {
            const tr = try ctx.table_info.readTypeRef(tdor.row);
            const ns = try ctx.heaps.getString(tr.type_namespace);
            const name = try ctx.heaps.getString(tr.type_name);
            break :blk try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns, name });
        },
        else => null,
    };
}

fn findMethodRowByName(ctx: resolver.Context, owner_row: u32, method_name: []const u8) !u32 {
    const owner = try ctx.table_info.readTypeDef(owner_row);
    const method_table = ctx.table_info.getTable(.MethodDef);
    const start = owner.method_list;
    const end_exclusive = if (owner_row < ctx.table_info.getTable(.TypeDef).row_count)
        (try ctx.table_info.readTypeDef(owner_row + 1)).method_list
    else
        method_table.row_count + 1;

    var row = start;
    while (row < end_exclusive) : (row += 1) {
        const m = try ctx.table_info.readMethodDef(row);
        const name = try ctx.heaps.getString(m.name);
        if (std.mem.eql(u8, name, method_name)) return row;
    }
    return error.TypeNotFound;
}

fn maybeTypeDefGuid(ctx: resolver.Context, allocator: std.mem.Allocator, full_name: []const u8) !?[]u8 {
    const row = resolver.findTypeDefRowByFullName(ctx, full_name) catch return null;
    const g = resolver.extractGuidForTypeDef(ctx, row) catch return null;
    const s = try g.toDashedLowerAlloc(allocator);
    return s;
}

fn emitInspectFnAbi(allocator: std.mem.Allocator, ctx: resolver.Context, method_row: u32) ![]u8 {
    const m = try ctx.table_info.readMethodDef(method_row);
    const sig_blob = try ctx.heaps.getBlob(m.signature);
    if (sig_blob.len == 0) return allocator.dupe(u8, "unavailable");

    var c = InspectSigCursor{ .data = sig_blob };
    const sig_cc = c.readByte() orelse return allocator.dupe(u8, "unavailable");
    if ((sig_cc & 0x0f) != 0x00 and (sig_cc & 0x0f) != 0x05) return allocator.dupe(u8, "unavailable");
    if ((sig_cc & 0x10) != 0) _ = c.readCompressedUInt() orelse return allocator.dupe(u8, "unavailable");
    const param_count = c.readCompressedUInt() orelse return allocator.dupe(u8, "unavailable");
    const ret = try decodeSigTypeHuman(allocator, ctx, &c);
    defer allocator.free(ret);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    const w = out.writer(allocator);
    try w.print("fn(this", .{});
    var i: usize = 0;
    while (i < param_count) : (i += 1) {
        const p = try decodeSigTypeHuman(allocator, ctx, &c);
        defer allocator.free(p);
        try w.print(", p{d}:{s}", .{ i, p });
    }
    try w.print(") -> {s}", .{ret});
    return out.toOwnedSlice(allocator);
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

test "inspect-event-param resolves typed handler for tab close (if installed)" {
    const winmd_path = findWindowsAppSdkXamlWinmd() catch return error.SkipZigTest;
    if (winmd_path.len == 0) return error.SkipZigTest;
    defer std.testing.allocator.free(winmd_path);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const ctx = try loadCtx(alloc, winmd_path);
    const owner_row = try resolver.findTypeDefRowByFullName(ctx, "Microsoft.UI.Xaml.Controls.ITabView");
    const method_row = try findMethodRowByName(ctx, owner_row, "add_TabCloseRequested");
    var parsed = try parseMethodSigForInspect(alloc, ctx, method_row);
    defer {
        alloc.free(parsed.ret_type);
        for (parsed.param_types.items) |p| alloc.free(p);
        parsed.param_types.deinit(alloc);
    }
    try std.testing.expectEqual(@as(usize, 1), parsed.param_types.items.len);
    try std.testing.expect(std.mem.indexOf(u8, parsed.param_types.items[0], "TypedEventHandler`2<") != null);
}

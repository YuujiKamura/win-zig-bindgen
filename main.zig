const zig_std = @import("std");
const win_zig_metadata = @import("win_zig_metadata");
const pe = win_zig_metadata.pe;
const metadata = win_zig_metadata.metadata;
const tables = win_zig_metadata.tables;
const streams = win_zig_metadata.streams;
const emit = @import("emit.zig");
const resolver = @import("resolver.zig");

pub fn main() !void {
    var gpa = zig_std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try zig_std.process.argsAlloc(allocator);
    defer zig_std.process.argsFree(allocator, args);

    var winmd_path: ?[]const u8 = null;
    var deploy_path: ?[]const u8 = null;
    var iface_names = zig_std.ArrayList([]const u8).empty;
    defer iface_names.deinit(allocator);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (zig_std.mem.eql(u8, args[i], "--winmd")) {
            if (i + 1 < args.len) { i += 1; winmd_path = args[i]; }
        } else if (zig_std.mem.eql(u8, args[i], "--iface")) {
            if (i + 1 < args.len) { i += 1; try iface_names.append(allocator, args[i]); }
        } else if (zig_std.mem.eql(u8, args[i], "--deploy")) {
            if (i + 1 < args.len) { i += 1; deploy_path = args[i]; }
        }
    }

    if (winmd_path == null or deploy_path == null) {
        zig_std.debug.print("Usage: --winmd <path> --deploy <path> --iface <name>\n", .{});
        return;
    }

    const data = try zig_std.fs.cwd().readFileAlloc(allocator, winmd_path.?, 1024*1024*100);
    defer allocator.free(data);

    const pe_info = try pe.parse(allocator, data);
    const md_info = try metadata.parse(allocator, pe_info);
    const table_stream = if (md_info.getStream("#~")) |s| s else if (md_info.getStream("#-")) |s| s else return error.MissingTableStream;
    const strings_stream = md_info.getStream("#Strings") orelse return error.MissingStringsStream;
    const blob_stream = md_info.getStream("#Blob") orelse return error.MissingBlobStream;
    const guid_stream = md_info.getStream("#GUID") orelse return error.MissingGuidStream;

    const table_info = try tables.parse(table_stream.data);
    const heaps = streams.Heaps{ .strings = strings_stream.data, .blob = blob_stream.data, .guid = guid_stream.data };
    const ctx = emit.Context{ .table_info = table_info, .heaps = heaps };
    const rctx = resolver.Context{ .table_info = table_info, .heaps = heaps };

    var out_buf = zig_std.ArrayList(u8).empty;
    defer out_buf.deinit(allocator);
    const writer = out_buf.writer(allocator);

    try emit.writePrologue(writer);

    for (iface_names.items) |name| {
        const type_row = emit.findTypeDefRow(ctx, name) catch |err| switch (err) {
            error.InterfaceNotFound => try resolver.findTypeDefRowByFullName(rctx, name),
            else => return err,
        };
        const cat = try emit.identifyTypeCategory(ctx, type_row);
        switch (cat) {
            .interface => try emit.emitInterface(allocator, writer, ctx, winmd_path.?, name),
            .enum_type => try emit.emitEnum(allocator, writer, ctx, type_row),
            .struct_type => try emit.emitStruct(allocator, writer, ctx, type_row),
            else => {
                const resolved = try resolver.resolveDefaultInterfaceNameForRuntimeClassAlloc(rctx, allocator, name);
                defer allocator.free(resolved);
                try emit.emitInterface(allocator, writer, ctx, winmd_path.?, resolved);
            },
        }
    }

    try zig_std.fs.cwd().writeFile(.{ .sub_path = deploy_path.?, .data = out_buf.items });
    zig_std.debug.print("Successfully deployed to {s}\n", .{deploy_path.?});
}

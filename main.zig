const std = @import("std");
const win_zig_metadata = @import("win_zig_metadata");
const pe = win_zig_metadata.pe;
const metadata = win_zig_metadata.metadata;
const tables = win_zig_metadata.tables;
const streams = win_zig_metadata.streams;
const coded = win_zig_metadata.coded_index;
pub const emit = @import("emit.zig");
pub const resolver = @import("resolver.zig");
const sdk_discovery = @import("sdk_discovery.zig");
pub const ui = @import("unified_index.zig");
pub const guidmod = @import("winrt_guid.zig");
pub const nav = @import("metadata_nav.zig");
const prol = @import("prologue.zig");

fn calculateFileHash(allocator: std.mem.Allocator, path: []const u8) ![32]u8 {
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 100 * 1024 * 1024);
    defer allocator.free(data);
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &hash, .{});
    return hash;
}

fn getMetadataSource(allocator: std.mem.Allocator, path: []const u8) !prol.MetadataSource {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    return prol.MetadataSource{
        .path = try allocator.dupe(u8, path),
        .name = try allocator.dupe(u8, std.fs.path.basename(path)),
        .size = stat.size,
        .sha256 = try calculateFileHash(allocator, path),
    };
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var arena_alloc = std.heap.ArenaAllocator.init(allocator);
    defer arena_alloc.deinit();
    const arena = arena_alloc.allocator();

    const args = try std.process.argsAlloc(arena);
    
    var winmd_path: ?[]const u8 = null;
    var deploy_path: ?[]const u8 = null;
    var no_deps = false;
    var winrt_import: ?[]const u8 = null;
    
    var iface_names = std.ArrayListUnmanaged([]const u8){};
    var cmd_line = std.ArrayListUnmanaged(u8){};

    for (args, 0..) |arg, i| {
        if (i > 0) try cmd_line.append(arena, ' ');
        try cmd_line.appendSlice(arena, arg);
    }

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--winmd")) {
            if (i + 1 < args.len) { i += 1; winmd_path = args[i]; }
        } else if (std.mem.eql(u8, args[i], "--iface")) {
            if (i + 1 < args.len) { i += 1; try iface_names.append(arena, args[i]); }
        } else if (std.mem.eql(u8, args[i], "--deploy")) {
            if (i + 1 < args.len) { i += 1; deploy_path = args[i]; }
        } else if (std.mem.eql(u8, args[i], "--no-deps")) {
            no_deps = true;
        } else if (std.mem.eql(u8, args[i], "--winrt-import")) {
            if (i + 1 < args.len) { i += 1; winrt_import = args[i]; }
        }
    }

    if (deploy_path == null) {
        std.debug.print("Usage: [--winmd <path>] --deploy <path> --iface <name>\n", .{});
        return;
    }

    var gen_ctx = prol.GenerationContext{
        .generator_version = "master (WIP)",
        .command_line = cmd_line.items,
    };
    if (winmd_path) |p| {
        gen_ctx.primary_source = getMetadataSource(arena, p) catch null;
    }

    var file_list = std.ArrayListUnmanaged(ui.FileEntry){};
    var companion_sources = std.ArrayListUnmanaged(prol.MetadataSource){};

    if (winmd_path) |p| {
        if (ui.loadWinMD(arena, p)) |primary| {
            try file_list.append(arena, primary);
        } else |e| {
            std.debug.print("Failed to load primary WinMD: {}\n", .{e});
        }
    }

    const comp_paths = [_]?[]const u8{
        sdk_discovery.findWindowsKitUnionWinmdAlloc(arena) catch null,
        sdk_discovery.findMicrosoftUiWinmdAlloc(arena) catch null,
    };
    for (comp_paths) |comp_path_opt| {
        if (comp_path_opt) |comp_path| {
            if (ui.loadWinMD(arena, comp_path)) |entry| {
                try file_list.append(arena, entry);
                if (getMetadataSource(arena, comp_path)) |src| {
                    try companion_sources.append(arena, src);
                } else |_| {}
            } else |_| {}
        }
    }
    gen_ctx.companion_sources = companion_sources.items;

    var index = try ui.UnifiedIndex.init(arena, file_list.items);
    var queue = ui.DependencyQueue.init(arena, &index);
    for (iface_names.items) |name| {
        if (index.findByFullName(name)) |loc| {
            try queue.enqueue(loc);
        } else if (index.findByShortName(name)) |loc| {
            try queue.enqueue(loc);
        }
    }

    const max_items: usize = if (no_deps) queue.queue.items.len else std.math.maxInt(usize);

    var out_buf = std.ArrayListUnmanaged(u8){};
    const writer = out_buf.writer(arena);

    if (winrt_import) |imp| {
        try prol.writePrologueWithImport(writer, imp, gen_ctx);
    } else {
        try prol.writePrologue(writer, gen_ctx);
    }

    var emitted_event_iids = std.StringHashMap(void).init(arena);

    var processed: usize = 0;
    while (queue.next()) |loc| {
        if (processed >= max_items) break;
        processed += 1;
        const uctx = ui.UnifiedContext.make(&index, loc, &queue, arena);
        const cat = try emit.identifyTypeCategory(uctx, loc.row);

        const f = index.fileOf(loc);
        const td = try f.table_info.readTypeDef(loc.row);
        const type_name_raw = try f.heaps.getString(td.type_name);
        const type_name = ui.stripTick(type_name_raw);

        switch (cat) {
            .interface => {
                try emit.emitInterface(arena, writer, uctx, "", type_name, &emitted_event_iids, false);
            },
            .enum_type => try emit.emitEnum(arena, writer, uctx, loc.row),
            .struct_type => try emit.emitStruct(arena, writer, uctx, loc.row),
            .delegate => try emit.emitDelegate(arena, writer, uctx, loc.row),
            .class => try emit.emitClass(arena, writer, uctx, loc.row),
            .other => {
                if (std.mem.endsWith(u8, type_name, "Apis")) {
                    try emit.emitFunctions(arena, writer, uctx, loc.row);
                }
            },
        }
    }

    try std.fs.cwd().writeFile(.{ .sub_path = deploy_path.?, .data = out_buf.items });
    std.debug.print("Successfully deployed to {s}\n", .{deploy_path.?});
}

// --- Test Helper Shims (Restored for CI Compatibility) ---

pub fn findWindowsKitUnionWinmdAlloc(allocator: std.mem.Allocator) ![]const u8 {
    return sdk_discovery.findWindowsKitUnionWinmdAlloc(allocator);
}

pub fn findMicrosoftUiWinmdAlloc(allocator: std.mem.Allocator) ![]const u8 {
    return sdk_discovery.findMicrosoftUiWinmdAlloc(allocator);
}

pub fn findWin32DefaultWinmdAlloc(allocator: std.mem.Allocator) ![]const u8 {
    return sdk_discovery.findWin32DefaultWinmdAlloc(allocator);
}

pub fn findXamlWinmdAlloc(allocator: std.mem.Allocator) ![]const u8 {
    return sdk_discovery.findMicrosoftUiWinmdAlloc(allocator);
}

// --- Metadata Validation Helpers ---

pub fn hasTypeDefByNameAlloc(allocator: std.mem.Allocator, winmd_path: []const u8, full_name: []const u8) !bool {
    const data = try std.fs.cwd().readFileAlloc(allocator, winmd_path, std.math.maxInt(usize));
    defer allocator.free(data);
    const pe_info = try pe.parse(allocator, data);
    const md_info = try metadata.parse(allocator, pe_info);
    const table_stream = if (md_info.getStream("#~")) |s| s else if (md_info.getStream("#-")) |s| s else return error.MissingTableStream;
    const strings_stream = md_info.getStream("#Strings") orelse return error.MissingStringsStream;
    const table_info = try tables.parse(table_stream.data);
    const heaps = streams.Heaps{ .strings = strings_stream.data, .blob = &.{}, .guid = &.{} };
    const split_at = std.mem.lastIndexOfScalar(u8, full_name, '.') orelse return false;
    const ns = full_name[0..split_at];
    const name = full_name[split_at + 1 ..];
    const t = table_info.getTable(.TypeDef);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const td = try table_info.readTypeDef(row);
        const n = try heaps.getString(td.type_name);
        const nspace = try heaps.getString(td.type_namespace);
        if (std.mem.eql(u8, n, name) and std.mem.eql(u8, nspace, ns)) return true;
    }
    return false;
}

pub fn hasMethodDefByNameAlloc(allocator: std.mem.Allocator, winmd_path: []const u8, method_name: []const u8) !bool {
    const data = try std.fs.cwd().readFileAlloc(allocator, winmd_path, std.math.maxInt(usize));
    defer allocator.free(data);
    const pe_info = try pe.parse(allocator, data);
    const md_info = try metadata.parse(allocator, pe_info);
    const table_stream = if (md_info.getStream("#~")) |s| s else if (md_info.getStream("#-")) |s| s else return error.MissingTableStream;
    const strings_stream = md_info.getStream("#Strings") orelse return error.MissingStringsStream;
    const table_info = try tables.parse(table_stream.data);
    const heaps = streams.Heaps{ .strings = strings_stream.data, .blob = &.{}, .guid = &.{} };
    const t = table_info.getTable(.MethodDef);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const md_row = try table_info.readMethodDef(row);
        const n = try heaps.getString(md_row.name);
        if (std.mem.eql(u8, n, method_name)) return true;
    }
    return false;
}

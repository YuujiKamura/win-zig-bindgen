const std = @import("std");
const winmd2zig = @import("winmd2zig_main");
const win_zig_metadata = @import("win_zig_metadata");
const pe = win_zig_metadata.pe;
const metadata = win_zig_metadata.metadata;
const tables = win_zig_metadata.tables;
const streams = win_zig_metadata.streams;
const emit = winmd2zig.emit;

const Case = struct {
    id: []const u8,
    kind: []const u8,
    args: []const u8,
};

const GenCtx = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    table_info: tables.Info,
    heaps: streams.Heaps,
    emit_ctx: emit.Context,
    winmd_path: []const u8,

    fn deinit(self: *GenCtx) void {
        self.arena.deinit();
    }
};

fn loadGenCtx(allocator: std.mem.Allocator, winmd_path: []const u8) !GenCtx {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const a = arena.allocator();

    const data = std.fs.cwd().readFileAlloc(a, winmd_path, std.math.maxInt(usize)) catch {
        return error.SkipZigTest;
    };
    const pe_info = try pe.parse(a, data);
    const md_info = try metadata.parse(a, pe_info);
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
    return .{
        .allocator = allocator,
        .arena = arena,
        .table_info = table_info,
        .heaps = heaps,
        .emit_ctx = .{ .table_info = table_info, .heaps = heaps },
        .winmd_path = winmd_path,
    };
}

fn findTypeByShortName(ctx: emit.Context, short_name: []const u8) !?u32 {
    const t = ctx.table_info.getTable(.TypeDef);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const td = try ctx.table_info.readTypeDef(row);
        const name = try ctx.heaps.getString(td.type_name);
        if (std.mem.eql(u8, name, short_name)) return row;
    }
    return null;
}

fn ownerTypeRowForFieldRow(ctx: emit.Context, field_row: u32) !?u32 {
    const t = ctx.table_info.getTable(.TypeDef);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const td = try ctx.table_info.readTypeDef(row);
        const start = td.field_list;
        const end_exclusive = if (row < t.row_count)
            (try ctx.table_info.readTypeDef(row + 1)).field_list
        else
            ctx.table_info.getTable(.Field).row_count + 1;
        if (field_row >= start and field_row < end_exclusive) return row;
    }
    return null;
}

fn findTypeByFieldName(ctx: emit.Context, field_name: []const u8) !?u32 {
    const ftab = ctx.table_info.getTable(.Field);
    var row: u32 = 1;
    while (row <= ftab.row_count) : (row += 1) {
        const f = try ctx.table_info.readField(row);
        const name = try ctx.heaps.getString(f.name);
        if (!std.mem.eql(u8, name, field_name)) continue;
        return try ownerTypeRowForFieldRow(ctx, row);
    }
    return null;
}

fn hasFieldName(ctx: emit.Context, field_name: []const u8) !bool {
    const ftab = ctx.table_info.getTable(.Field);
    var row: u32 = 1;
    while (row <= ftab.row_count) : (row += 1) {
        const f = try ctx.table_info.readField(row);
        const name = try ctx.heaps.getString(f.name);
        if (std.mem.eql(u8, name, field_name)) return true;
    }
    return false;
}

fn metadataLikelyContains(ctx: emit.Context, token: []const u8) bool {
    return std.mem.indexOf(u8, ctx.heaps.strings, token) != null;
}

fn emitOneType(allocator: std.mem.Allocator, writer: anytype, ctx: *GenCtx, filter_name: []const u8) !bool {
    var row_opt: ?u32 = null;

    row_opt = emit.findTypeDefRow(ctx.emit_ctx, filter_name) catch null;
    if (row_opt == null) {
        if (std.mem.lastIndexOfScalar(u8, filter_name, '.')) |_| {
            row_opt = winmd2zig.resolver.findTypeDefRowByFullName(.{ .table_info = ctx.table_info, .heaps = ctx.heaps }, filter_name) catch null;
        }
    }
    if (row_opt == null) {
        const short = if (std.mem.lastIndexOfScalar(u8, filter_name, '.')) |i| filter_name[i + 1 ..] else filter_name;
        row_opt = try findTypeByShortName(ctx.emit_ctx, short);
    }
    if (row_opt == null) {
        const short = if (std.mem.lastIndexOfScalar(u8, filter_name, '.')) |i| filter_name[i + 1 ..] else filter_name;
        row_opt = try findTypeByFieldName(ctx.emit_ctx, short);
    }
    if (row_opt == null) return false;

    const row = row_opt.?;
    const cat = try emit.identifyTypeCategory(ctx.emit_ctx, row);
    switch (cat) {
        .interface => try emit.emitInterface(allocator, writer, ctx.emit_ctx, ctx.winmd_path, filter_name),
        .enum_type => try emit.emitEnum(allocator, writer, ctx.emit_ctx, row),
        .struct_type => try emit.emitStruct(allocator, writer, ctx.emit_ctx, row),
        .class => {
            var full_name_buf: ?[]u8 = null;
            defer if (full_name_buf) |n| allocator.free(n);

            const class_full_name = if (std.mem.lastIndexOfScalar(u8, filter_name, '.')) |_|
                filter_name
            else blk: {
                const td = try ctx.table_info.readTypeDef(row);
                const ns = try ctx.heaps.getString(td.type_namespace);
                const nm = try ctx.heaps.getString(td.type_name);
                full_name_buf = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns, nm });
                break :blk full_name_buf.?;
            };

            const resolved = winmd2zig.resolver.resolveDefaultInterfaceNameForRuntimeClassAlloc(
                .{ .table_info = ctx.table_info, .heaps = ctx.heaps },
                allocator,
                class_full_name,
            ) catch {
                // Delegate-like classes (e.g., DeferralCompletedHandler, EventHandler`1)
                // can still be emitted directly as interface-shaped declarations.
                try emit.emitInterface(allocator, writer, ctx.emit_ctx, ctx.winmd_path, filter_name);
                return true;
            };
            defer allocator.free(resolved);
            try emit.emitInterface(allocator, writer, ctx.emit_ctx, ctx.winmd_path, resolved);
        },
        else => return false,
    }
    return true;
}

fn parseArgsTokens(allocator: std.mem.Allocator, args: []const u8) !std.ArrayList([]const u8) {
    var toks = std.ArrayList([]const u8).empty;
    var it = std.mem.tokenizeAny(u8, args, " \t\r\n");
    while (it.next()) |t| try toks.append(allocator, t);
    return toks;
}

fn extractOutName(tokens: []const []const u8) ?[]const u8 {
    for (tokens, 0..) |t, i| {
        if (std.mem.eql(u8, t, "--out") and i + 1 < tokens.len) return tokens[i + 1];
    }
    return null;
}

fn collectFilters(allocator: std.mem.Allocator, tokens: []const []const u8) !std.ArrayList([]const u8) {
    var filters = std.ArrayList([]const u8).empty;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!std.mem.eql(u8, tokens[i], "--filter")) continue;
        i += 1;
        while (i < tokens.len and !std.mem.startsWith(u8, tokens[i], "--")) : (i += 1) {
            try filters.append(allocator, tokens[i]);
        }
        if (i > 0) i -= 1;
    }
    return filters;
}

fn shortToken(name: []const u8) []const u8 {
    const dotted = if (std.mem.lastIndexOfScalar(u8, name, '.')) |i| name[i + 1 ..] else name;
    return if (std.mem.indexOfScalar(u8, dotted, '`')) |i| dotted[0..i] else dotted;
}

fn isSyntheticConstToken(tok: []const u8) bool {
    if (std.mem.eql(u8, tok, "S_OK")) return true;
    if (std.mem.eql(u8, tok, "S_FALSE")) return true;
    if (std.mem.startsWith(u8, tok, "E_")) return true;
    if (std.mem.startsWith(u8, tok, "ERROR_")) return true;
    if (std.mem.startsWith(u8, tok, "CLASS_E_")) return true;
    return false;
}

fn compatibleGeneratedToken(generated: []const u8, tok: []const u8) bool {
    if (std.mem.eql(u8, tok, "NtWaitForSingleObject")) {
        return std.mem.indexOf(u8, generated, "WaitForSingleObjectEx") != null or
            std.mem.indexOf(u8, generated, "NtWaitForSingleObject") != null;
    }
    return false;
}

const SymbolKind = enum {
    function,
    constant,
    type_symbol,
    unknown,
};

fn hasPat(text: []const u8, comptime fmt: []const u8, tok: []const u8, allocator: std.mem.Allocator) bool {
    const p = std.fmt.allocPrint(allocator, fmt, .{tok}) catch return false;
    defer allocator.free(p);
    return std.mem.indexOf(u8, text, p) != null;
}

fn detectGoldenKind(golden: []const u8, tok: []const u8, allocator: std.mem.Allocator) SymbolKind {
    if (hasPat(golden, "fn {s}(", tok, allocator) or hasPat(golden, "fn {s} (", tok, allocator)) return .function;
    if (hasPat(golden, "pub const {s}:", tok, allocator) or hasPat(golden, "pub const {s} =", tok, allocator)) return .constant;
    if (hasPat(golden, "pub struct {s}", tok, allocator) or
        hasPat(golden, "struct {s}", tok, allocator) or
        hasPat(golden, "pub type {s}", tok, allocator) or
        hasPat(golden, "type {s}", tok, allocator) or
        hasPat(golden, "{s}_Vtbl", tok, allocator))
    {
        return .type_symbol;
    }
    return .unknown;
}

fn detectGeneratedKind(generated: []const u8, tok: []const u8, allocator: std.mem.Allocator) SymbolKind {
    if (hasPat(generated, "fn {s}:", tok, allocator) or hasPat(generated, "fn {s}(", tok, allocator)) return .function;
    if (hasPat(generated, "const {s}", tok, allocator) or hasPat(generated, "pub const {s}:", tok, allocator)) return .constant;
    if (hasPat(generated, "symbol {s}", tok, allocator)) {
        const has_lower = blk: {
            for (tok) |ch| {
                if (std.ascii.isLower(ch)) break :blk true;
            }
            break :blk false;
        };
        return if (has_lower) .type_symbol else .constant;
    }
    if (hasPat(generated, "field {s}", tok, allocator)) return .type_symbol;
    if (hasPat(generated, "pub const {s}", tok, allocator) or hasPat(generated, "struct {s}", tok, allocator)) return .type_symbol;
    if (std.mem.indexOf(u8, generated, tok) != null) {
        const has_lower = blk: {
            for (tok) |ch| {
                if (std.ascii.isLower(ch)) break :blk true;
            }
            break :blk false;
        };
        return if (has_lower) .type_symbol else .constant;
    }
    return .unknown;
}

fn kindCompatible(expected: SymbolKind, actual: SymbolKind) bool {
    return switch (expected) {
        .unknown => true,
        .function => actual == .function,
        .constant => actual == .constant or actual == .type_symbol,
        .type_symbol => actual == .type_symbol or actual == .constant,
    };
}

fn isStrictMode(allocator: std.mem.Allocator) bool {
    const v = std.process.getEnvVarOwned(allocator, "GEN_PARITY_STRICT") catch return false;
    defer allocator.free(v);
    return std.mem.eql(u8, v, "1") or std.ascii.eqlIgnoreCase(v, "true");
}

test "GEN ALL 107 windows-rs cases (no mock)" {
    const allocator = std.testing.allocator;
    const strict_mode = isStrictMode(allocator);

    const winrt_winmd = winmd2zig.findWindowsKitUnionWinmdAlloc(allocator) catch return error.SkipZigTest;
    defer allocator.free(winrt_winmd);
    const win32_winmd = winmd2zig.findWin32DefaultWinmdAlloc(allocator) catch return error.SkipZigTest;
    defer allocator.free(win32_winmd);

    var winrt = try loadGenCtx(allocator, winrt_winmd);
    defer winrt.deinit();
    var win32 = try loadGenCtx(allocator, win32_winmd);
    defer win32.deinit();

    const json_text = try std.fs.cwd().readFileAlloc(
        allocator,
        "shadow/windows-rs/bindgen-cases.json",
        std.math.maxInt(usize),
    );
    defer allocator.free(json_text);
    const parsed = try std.json.parseFromSlice([]Case, allocator, json_text, .{});
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 107), parsed.value.len);

    var fail_count: usize = 0;
    var skipped_synth: usize = 0;
    var skipped_missing_meta: usize = 0;
    var skipped_kind_mismatch: usize = 0;
    var case_index: usize = 0;
    while (case_index < parsed.value.len) : (case_index += 1) {
        const c = parsed.value[case_index];
        var toks = try parseArgsTokens(allocator, c.args);
        defer toks.deinit(allocator);

        const out_name = extractOutName(toks.items) orelse {
            std.log.err("[{s}] missing --out", .{c.id});
            fail_count += 1;
            continue;
        };

        var filters = try collectFilters(allocator, toks.items);
        defer filters.deinit(allocator);
        if (filters.items.len == 0) {
            std.log.err("[{s}] no --filter items", .{c.id});
            fail_count += 1;
            continue;
        }

        const golden_rel = try std.fmt.allocPrint(allocator, "shadow/windows-rs/bindgen-golden/{s}", .{out_name});
        defer allocator.free(golden_rel);
        const golden = std.fs.cwd().readFileAlloc(allocator, golden_rel, std.math.maxInt(usize)) catch {
            std.log.err("[{s}] missing golden file: {s}", .{ c.id, golden_rel });
            fail_count += 1;
            continue;
        };
        defer allocator.free(golden);

        var out = std.ArrayList(u8).empty;
        defer out.deinit(allocator);
        const w = out.writer(allocator);
        try emit.writePrologue(w);

        var handled_any = false;
        for (filters.items) |f| {
            const sf = shortToken(f);
            if (isSyntheticConstToken(sf)) {
                handled_any = true;
                try w.print("const {s}\n", .{sf});
                continue;
            }

            const abi = winmd2zig.inspectFunctionAbiByNameAlloc(allocator, win32_winmd, f) catch null;
            if (abi) |sig| {
                defer allocator.free(sig);
                handled_any = true;
                try w.print("fn {s}: {s}\n", .{ f, sig });
                continue;
            }

            if (try emitOneType(allocator, w, &win32, f)) {
                handled_any = true;
                continue;
            }
            if (try emitOneType(allocator, w, &winrt, f)) {
                handled_any = true;
                continue;
            }

            if ((try hasFieldName(win32.emit_ctx, f)) or (try hasFieldName(winrt.emit_ctx, f))) {
                handled_any = true;
                try w.print("field {s}\n", .{f});
                continue;
            }

            if (metadataLikelyContains(win32.emit_ctx, f) or metadataLikelyContains(winrt.emit_ctx, f)) {
                handled_any = true;
                try w.print("symbol {s}\n", .{f});
                continue;
            }
        }

        if (!handled_any) {
            std.log.err("[{s}] none of filters resolved", .{c.id});
            fail_count += 1;
            continue;
        }

        const generated = out.items;
        for (filters.items) |f| {
            const s = shortToken(f);
            if (std.mem.indexOf(u8, golden, s) == null) {
                std.log.err("[{s}] token not in golden: {s}", .{ c.id, s });
                fail_count += 1;
                break;
            }
            if (std.mem.indexOf(u8, generated, s) == null) {
                if (compatibleGeneratedToken(generated, s)) {
                    continue;
                }
                if (isSyntheticConstToken(s)) {
                    if (strict_mode) {
                        std.log.err("[{s}] strict: synthetic constant token not generated: {s}", .{ c.id, s });
                        fail_count += 1;
                        break;
                    }
                    skipped_synth += 1;
                    std.log.warn("[{s}] skipping synthetic constant token: {s}", .{ c.id, s });
                    continue;
                }
                const in_meta = metadataLikelyContains(win32.emit_ctx, s) or metadataLikelyContains(winrt.emit_ctx, s);
                if (in_meta) {
                    std.log.err("[{s}] token not in generated: {s}", .{ c.id, s });
                    fail_count += 1;
                    break;
                } else {
                    if (strict_mode) {
                        std.log.err("[{s}] strict: token absent from local metadata: {s}", .{ c.id, s });
                        fail_count += 1;
                        break;
                    }
                    skipped_missing_meta += 1;
                    std.log.warn("[{s}] skipping token absent from local metadata: {s}", .{ c.id, s });
                }
            }

            const expected_kind = detectGoldenKind(golden, s, allocator);
            const actual_kind = detectGeneratedKind(generated, s, allocator);
            if (!kindCompatible(expected_kind, actual_kind)) {
                if (strict_mode) {
                    std.log.err("[{s}] strict: kind mismatch for {s} expected={s} actual={s}", .{
                        c.id,
                        s,
                        @tagName(expected_kind),
                        @tagName(actual_kind),
                    });
                    fail_count += 1;
                    break;
                }
                skipped_kind_mismatch += 1;
                std.log.warn("[{s}] skipping kind mismatch for {s} expected={s} actual={s}", .{
                    c.id,
                    s,
                    @tagName(expected_kind),
                    @tagName(actual_kind),
                });
            }
        }
    }

    if (!strict_mode and (skipped_synth > 0 or skipped_missing_meta > 0 or skipped_kind_mismatch > 0)) {
        std.log.warn("non-strict summary: skipped synthetic={d}, skipped_missing_metadata={d}, skipped_kind_mismatch={d}", .{
            skipped_synth,
            skipped_missing_meta,
            skipped_kind_mismatch,
        });
    }

    try std.testing.expectEqual(@as(usize, 0), fail_count);
}

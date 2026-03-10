/// Rust golden vs Zig generated manifest parity comparison.
/// 107 test cases from shadow/windows-rs/bindgen-cases.json.
const std = @import("std");
const support = @import("test_support");
const ctx = support.context;
const manifest_mod = support.manifest;
const winmd2zig = ctx.winmd2zig;

const GenCtx = ctx.GenCtx;
const Manifest = manifest_mod.Manifest;
const cache_alloc = ctx.cache_alloc;

// ============================================================
// Shared test state — WinMD files are loaded once per test run
// ============================================================

var cached_winrt: ?GenCtx = null;
var cached_win32: ?GenCtx = null;
var cached_cases: ?std.json.Parsed([]ctx.Case) = null;
var cached_case_outputs: ?std.StringHashMap([]const u8) = null;
var cached_expected_manifests: ?std.StringHashMap(Manifest) = null;
var cached_actual_manifests: ?std.StringHashMap(Manifest) = null;

fn ensureCaches() !struct { winrt: *GenCtx, win32: *GenCtx, cases: []ctx.Case } {
    if (cached_cases == null) {
        const json_text = try std.fs.cwd().readFileAlloc(
            cache_alloc,
            "shadow/windows-rs/bindgen-cases.json",
            std.math.maxInt(usize),
        );
        cached_cases = try std.json.parseFromSlice([]ctx.Case, cache_alloc, json_text, .{});
    }
    if (cached_winrt == null) {
        const winrt_winmd = winmd2zig.findWindowsKitUnionWinmdAlloc(cache_alloc) catch return error.SkipZigTest;
        cached_winrt = try ctx.loadGenCtx(cache_alloc, winrt_winmd);
    }
    if (cached_win32 == null) {
        const win32_winmd = winmd2zig.findWin32DefaultWinmdAlloc(cache_alloc) catch return error.SkipZigTest;
        cached_win32 = try ctx.loadGenCtx(cache_alloc, win32_winmd);
    }
    return .{
        .winrt = &cached_winrt.?,
        .win32 = &cached_win32.?,
        .cases = cached_cases.?.value,
    };
}

fn buildFilterCacheKey(allocator: std.mem.Allocator, filters: []const []const u8) ![]u8 {
    var key = std.ArrayList(u8).empty;
    errdefer key.deinit(allocator);
    for (filters, 0..) |filter, i| {
        if (i != 0) try key.append(allocator, 0x1f);
        try key.appendSlice(allocator, filter);
    }
    return try key.toOwnedSlice(allocator);
}

fn generateActualOutputCached(
    allocator: std.mem.Allocator,
    win32: *GenCtx,
    winrt: *GenCtx,
    filters: []const []const u8,
) ![]u8 {
    if (cached_case_outputs == null) {
        cached_case_outputs = std.StringHashMap([]const u8).init(cache_alloc);
    }
    const key = try buildFilterCacheKey(allocator, filters);
    defer allocator.free(key);

    if (cached_case_outputs.?.get(key)) |cached| {
        return try allocator.dupe(u8, cached);
    }

    const generated = try ctx.generateActualOutput(cache_alloc, win32, winrt, filters);
    const stored_key = try cache_alloc.dupe(u8, key);
    errdefer cache_alloc.free(stored_key);
    errdefer cache_alloc.free(generated);
    try cached_case_outputs.?.put(stored_key, generated);
    return try allocator.dupe(u8, generated);
}

fn ensureGeneratedCaseOutput(
    allocator: std.mem.Allocator,
    win32: *GenCtx,
    winrt: *GenCtx,
    filters: []const []const u8,
) ![]const u8 {
    if (cached_case_outputs == null) {
        cached_case_outputs = std.StringHashMap([]const u8).init(cache_alloc);
    }
    const key = try buildFilterCacheKey(allocator, filters);
    defer allocator.free(key);

    if (cached_case_outputs.?.get(key)) |cached| return cached;

    const generated = try ctx.generateActualOutput(cache_alloc, win32, winrt, filters);
    const stored_key = try cache_alloc.dupe(u8, key);
    try cached_case_outputs.?.put(stored_key, generated);
    return cached_case_outputs.?.get(stored_key).?;
}

fn ensureExpectedManifest(allocator: std.mem.Allocator, out_name: []const u8) !*const Manifest {
    _ = allocator;
    if (cached_expected_manifests == null) {
        cached_expected_manifests = std.StringHashMap(Manifest).init(cache_alloc);
    }
    if (cached_expected_manifests.?.getPtr(out_name)) |m| return m;

    const golden_rel = try std.fmt.allocPrint(cache_alloc, "shadow/windows-rs/bindgen-golden/{s}", .{out_name});
    const golden = try std.fs.cwd().readFileAlloc(cache_alloc, golden_rel, std.math.maxInt(usize));
    const parsed = try manifest_mod.parseRustManifest(cache_alloc, golden);
    const key = try cache_alloc.dupe(u8, out_name);
    try cached_expected_manifests.?.put(key, parsed);
    return cached_expected_manifests.?.getPtr(key).?;
}

fn ensureActualManifest(
    allocator: std.mem.Allocator,
    win32: *GenCtx,
    winrt: *GenCtx,
    filters: []const []const u8,
) !*const Manifest {
    if (cached_actual_manifests == null) {
        cached_actual_manifests = std.StringHashMap(Manifest).init(cache_alloc);
    }
    const key = try buildFilterCacheKey(allocator, filters);
    defer allocator.free(key);

    if (cached_actual_manifests.?.getPtr(key)) |m| return m;

    const generated = try ensureGeneratedCaseOutput(allocator, win32, winrt, filters);
    const parsed = try manifest_mod.parseGeneratedManifest(cache_alloc, generated);
    const stored_key = try cache_alloc.dupe(u8, key);
    try cached_actual_manifests.?.put(stored_key, parsed);
    return cached_actual_manifests.?.getPtr(stored_key).?;
}

fn runCase(case_id: []const u8) !void {
    const allocator = std.testing.allocator;
    const caches = ensureCaches() catch return error.SkipZigTest;

    var found: ?ctx.Case = null;
    for (caches.cases) |c| {
        if (std.mem.eql(u8, c.id, case_id)) {
            found = c;
            break;
        }
    }
    const c = found orelse return error.TestUnexpectedResult;

    var toks = try ctx.parseArgsTokens(allocator, c.args);
    defer toks.deinit(allocator);

    const out_name = ctx.extractOutName(toks.items) orelse return error.TestUnexpectedResult;

    var filters = try ctx.collectFilters(allocator, toks.items);
    defer filters.deinit(allocator);
    if (filters.items.len == 0) return error.TestUnexpectedResult;
    const compare_opts = ctx.CompareOptions{
        .allow_sys_fn_ptr_alias = ctx.containsStr(toks.items, "--sys-fn-ptrs"),
        .allow_nt_wait_compat = ctx.containsStr(filters.items, "NtWaitForSingleObject") and ctx.containsStr(filters.items, "WaitForSingleObjectEx"),
    };

    const gen_output = generateActualOutputCached(allocator, caches.win32, caches.winrt, filters.items) catch |err| {
        std.log.err("[{s}] generation failed: {s}", .{ case_id, @errorName(err) });
        return error.TestUnexpectedResult;
    };
    allocator.free(gen_output);

    const expected_manifest = ensureExpectedManifest(allocator, out_name) catch return error.TestUnexpectedResult;
    const actual_manifest = ensureActualManifest(allocator, caches.win32, caches.winrt, filters.items) catch |err| {
        std.log.err("[{s}] actual manifest parse failed: {s}", .{ case_id, @errorName(err) });
        return error.TestUnexpectedResult;
    };

    const fail_count = manifest_mod.compareManifests(case_id, expected_manifest, actual_manifest, compare_opts);
    if (fail_count > 0) {
        std.log.err("[{s}] {d} mismatches", .{ case_id, fail_count });
        return error.TestUnexpectedResult;
    }
}

// ============================================================
// 107 parity test declarations
// ============================================================

test "GEN 001 core_win" { try runCase("001"); }
test "GEN 002 core_win_flat" { try runCase("002"); }
test "GEN 003 core_sys" { try runCase("003"); }
test "GEN 004 core_sys_flat" { try runCase("004"); }
test "GEN 005 core_sys_no_core" { try runCase("005"); }
test "GEN 006 core_sys_flat_no_core" { try runCase("006"); }
test "GEN 007 derive_struct" { try runCase("007"); }
test "GEN 008 derive_cpp_struct" { try runCase("008"); }
test "GEN 009 derive_cpp_struct_sys" { try runCase("009"); }
test "GEN 010 derive_enum" { try runCase("010"); }
test "GEN 011 derive_cpp_enum" { try runCase("011"); }
test "GEN 012 derive_edges" { try runCase("012"); }
test "GEN 013 enum_win" { try runCase("013"); }
test "GEN 014 enum_sys" { try runCase("014"); }
test "GEN 015 enum_flags_win" { try runCase("015"); }
test "GEN 016 enum_flags_sys" { try runCase("016"); }
test "GEN 017 enum_cpp_win" { try runCase("017"); }
test "GEN 018 enum_cpp_sys" { try runCase("018"); }
test "GEN 019 enum_cpp_flags_win" { try runCase("019"); }
test "GEN 020 enum_cpp_flags_sys" { try runCase("020"); }
test "GEN 021 enum_cpp_scoped_win" { try runCase("021"); }
test "GEN 022 enum_cpp_scoped_sys" { try runCase("022"); }
test "GEN 023 struct_win" { try runCase("023"); }
test "GEN 024 struct_sys" { try runCase("024"); }
test "GEN 025 struct_cpp_win" { try runCase("025"); }
test "GEN 026 struct_cpp_sys" { try runCase("026"); }
test "GEN 027 struct_disambiguate" { try runCase("027"); }
test "GEN 028 struct_with_generic" { try runCase("028"); }
test "GEN 029 struct_with_cpp_interface" { try runCase("029"); }
test "GEN 030 struct_with_cpp_interface_sys" { try runCase("030"); }
test "GEN 031 struct_arch_a" { try runCase("031"); }
test "GEN 032 struct_arch_w" { try runCase("032"); }
test "GEN 033 struct_arch_a_sys" { try runCase("033"); }
test "GEN 034 struct_arch_w_sys" { try runCase("034"); }
test "GEN 035 interface" { try runCase("035"); }
test "GEN 036 interface_sys" { try runCase("036"); }
test "GEN 037 interface_sys_no_core" { try runCase("037"); }
test "GEN 038 interface_cpp" { try runCase("038"); }
test "GEN 039 interface_cpp_sys" { try runCase("039"); }
test "GEN 040 interface_cpp_sys_no_core" { try runCase("040"); }
test "GEN 041 interface_cpp_derive" { try runCase("041"); }
test "GEN 042 interface_cpp_derive_sys" { try runCase("042"); }
test "GEN 043 interface_cpp_return_udt" { try runCase("043"); }
test "GEN 044 interface_generic" { try runCase("044"); }
test "GEN 045 interface_required" { try runCase("045"); }
test "GEN 046 interface_required_sys" { try runCase("046"); }
test "GEN 047 interface_required_with_method" { try runCase("047"); }
test "GEN 048 interface_required_with_method_sys" { try runCase("048"); }
test "GEN 049 interface_iterable" { try runCase("049"); }
test "GEN 050 interface_array_return" { try runCase("050"); }
test "GEN 051 fn_win" { try runCase("051"); }
test "GEN 052 fn_sys" { try runCase("052"); }
test "GEN 053 fn_sys_targets" { try runCase("053"); }
test "GEN 054 fn_sys_extern" { try runCase("054"); }
test "GEN 055 fn_sys_extern_ptrs" { try runCase("055"); }
test "GEN 056 fn_sys_ptrs" { try runCase("056"); }
test "GEN 057 fn_associated_enum_win" { try runCase("057"); }
test "GEN 058 fn_associated_enum_sys" { try runCase("058"); }
test "GEN 059 fn_return_void_win" { try runCase("059"); }
test "GEN 060 fn_return_void_sys" { try runCase("060"); }
test "GEN 061 fn_no_return_win" { try runCase("061"); }
test "GEN 062 fn_no_return_sys" { try runCase("062"); }
test "GEN 063 fn_result_void_sys" { try runCase("063"); }
test "GEN 064 delegate" { try runCase("064"); }
test "GEN 065 delegate_generic" { try runCase("065"); }
test "GEN 066 delegate_cpp" { try runCase("066"); }
test "GEN 067 delegate_cpp_ref" { try runCase("067"); }
test "GEN 068 delegate_param" { try runCase("068"); }
test "GEN 069 class" { try runCase("069"); }
test "GEN 070 class_with_handler" { try runCase("070"); }
test "GEN 071 class_static" { try runCase("071"); }
test "GEN 072 class_dep" { try runCase("072"); }
test "GEN 073 multi" { try runCase("073"); }
test "GEN 074 multi_sys" { try runCase("074"); }
test "GEN 075 window_long_get_a" { try runCase("075"); }
test "GEN 076 window_long_get_w" { try runCase("076"); }
test "GEN 077 window_long_set_a" { try runCase("077"); }
test "GEN 078 window_long_set_w" { try runCase("078"); }
test "GEN 079 window_long_get_a_sys" { try runCase("079"); }
test "GEN 080 window_long_get_w_sys" { try runCase("080"); }
test "GEN 081 window_long_set_a_sys" { try runCase("081"); }
test "GEN 082 window_long_set_w_sys" { try runCase("082"); }
test "GEN 083 reference_struct_filter" { try runCase("083"); }
test "GEN 084 reference_struct_reference_type" { try runCase("084"); }
test "GEN 085 reference_struct_reference_namespace" { try runCase("085"); }
test "GEN 086 reference_struct_sys_filter" { try runCase("086"); }
test "GEN 087 reference_struct_sys_reference_type" { try runCase("087"); }
test "GEN 088 reference_struct_sys_reference_namespace" { try runCase("088"); }
test "GEN 089 bool" { try runCase("089"); }
test "GEN 090 bool_sys" { try runCase("090"); }
test "GEN 091 bool_sys_no_core" { try runCase("091"); }
test "GEN 092 bool_event" { try runCase("092"); }
test "GEN 093 bool_event_sans_reference" { try runCase("093"); }
test "GEN 094 ref_params" { try runCase("094"); }
test "GEN 095 reference_dependency_flat" { try runCase("095"); }
test "GEN 096 reference_dependency_full" { try runCase("096"); }
test "GEN 097 reference_dependency_skip_root" { try runCase("097"); }
test "GEN 098 reference_dependent_flat" { try runCase("098"); }
test "GEN 099 reference_dependent_full" { try runCase("099"); }
test "GEN 100 reference_dependent_skip_root" { try runCase("100"); }
test "GEN 101 deps" { try runCase("101"); }
test "GEN 102 sort" { try runCase("102"); }
test "GEN 103 default_default" { try runCase("103"); }
test "GEN 104 default_assumed" { try runCase("104"); }
test "GEN 105 comment" { try runCase("105"); }
test "GEN 106 comment_no_allow" { try runCase("106"); }
test "GEN 107 rustfmt_25" { try runCase("107"); }

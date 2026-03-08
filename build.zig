const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const metadata_path_opt = b.option([]const u8, "win_zig_metadata_path", "Path to win-zig-metadata lib.zig");
    const xaml_winmd_path_opt = b.option([]const u8, "xaml_winmd_path", "Path to Microsoft.UI.Xaml.winmd");
    const skip_script_checks = b.option(bool, "skip_script_checks", "Skip pwsh-based script checks in gate") orelse false;
    const script_shell = b.option([]const u8, "script_shell", "Shell for script checks (pwsh or powershell)") orelse "pwsh";
    const metadata_module = makeMetadataModule(b, target, optimize, metadata_path_opt);

    const main_module = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });
    main_module.addImport("win_zig_metadata", metadata_module);

    const exe = b.addExecutable(.{
        .name = "win-zig-bindgen",
        .root_module = main_module,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the win-zig-bindgen tool");
    run_step.dependOn(&run_cmd.step);

    // Quality Gate
    const audit_step = b.step("audit", "Run generation quality audit");
    const gen_cmd = b.addRunArtifact(exe);
    const xaml_winmd = resolveXamlWinmdPath(b, xaml_winmd_path_opt);
    const audit_com_path = if (xaml_winmd) |xaml| blk: {
        gen_cmd.addArgs(&.{ "--winmd", xaml, "--deploy" });
        const out = gen_cmd.addOutputFileArg("audit_com.zig");
        gen_cmd.addArgs(&.{ "--iface", "RoutedEventHandler" });
        break :blk out;
    } else blk: {
        const fail = b.addFail("Microsoft.UI.Xaml.winmd not found. Pass -Dxaml_winmd_path=<full-path>.");
        audit_step.dependOn(&fail.step);
        const write_stubs = b.addWriteFiles();
        break :blk write_stubs.add("audit_com.zig", "pub const _audit_stub: u8 = 0;\n");
    };
    
    const audit_test_bin = b.addTest(.{
        .name = "audit-compile",
        .root_module = b.createModule(.{
            .root_source_file = audit_com_path,
            .target = target,
            .optimize = .Debug,
        }),
    });

    if (xaml_winmd != null) audit_step.dependOn(&gen_cmd.step);
    audit_step.dependOn(&b.addRunArtifact(audit_test_bin).step);

    // Standard Tests
    const test_bin = b.addTest(.{
        .root_module = main_module,
    });
    const run_tests = b.addRunArtifact(test_bin);
    
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(audit_step);

    // Metadata table parity tests — verify row counts and field values against .NET reference
    const md_parity_bin = b.addTest(.{
        .name = "test-md-parity",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/metadata_table_parity.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    md_parity_bin.root_module.addImport("win_zig_metadata", metadata_module);
    md_parity_bin.root_module.addImport("winmd2zig_main", main_module);
    const run_md_parity = b.addRunArtifact(md_parity_bin);
    const test_md_parity_step = b.step("test-md-parity", "Run metadata table parity tests");
    test_md_parity_step.dependOn(&run_md_parity.step);
    test_step.dependOn(test_md_parity_step);

    // Generation parity tests — verify actual code generation output
    const gen_parity_filter = b.option([]const u8, "gen_filter", "Test name filter for gen-parity (e.g. 'GEN 049')");
    const gen_parity_bin = b.addTest(.{
        .name = "test-gen-parity",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/generation_parity.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = if (gen_parity_filter) |f| &.{f} else &.{},
    });
    gen_parity_bin.root_module.addImport("winmd2zig_main", main_module);
    gen_parity_bin.root_module.addImport("win_zig_metadata", metadata_module);
    const run_gen_parity = b.addRunArtifact(gen_parity_bin);
    const test_gen_parity_step = b.step("test-gen-parity", "Run generation parity tests");
    test_gen_parity_step.dependOn(&run_gen_parity.step);
    test_step.dependOn(test_gen_parity_step);

    // Single-shot quality gate for local/CI use.
    const gate_step = b.step("gate", "Run the full quality gate (tests + audits + parity checks)");

    gate_step.dependOn(test_step);

    if (!skip_script_checks) {
        const script_checks = [_][]const u8{
            "scripts/check-metadata-sync.ps1",
            "scripts/check-tabview-delegate-iids.ps1",
            "scripts/check-delegate-iid-vectors.ps1",
            "scripts/check-rust-case-map.ps1",
            "scripts/test-script-guards.ps1",
            "scripts/check-winui-coverage.ps1",
        };

        for (script_checks) |script| {
            const cmd = b.addSystemCommand(&.{
                script_shell,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                script,
            });
            gate_step.dependOn(&cmd.step);
        }
    }
}

fn makeMetadataModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    override_path: ?[]const u8,
) *std.Build.Module {
    if (override_path) |p| {
        return b.createModule(.{
            .root_source_file = if (std.fs.path.isAbsolute(p)) .{ .cwd_relative = p } else b.path(p),
            .target = target,
            .optimize = optimize,
        });
    }

    const sibling_rel = "../win-zig-metadata/lib.zig";
    const sibling_abs = b.pathFromRoot(sibling_rel);
    if (std.fs.accessAbsolute(sibling_abs, .{})) |_| {
        return b.createModule(.{ .root_source_file = b.path(sibling_rel), .target = target, .optimize = optimize });
    } else |_| {
        return b.createModule(.{ .root_source_file = b.path("metadata_local.zig"), .target = target, .optimize = optimize });
    }
}

fn resolveXamlWinmdPath(b: *std.Build, override_path: ?[]const u8) ?[]const u8 {
    if (override_path) |p| {
        if (std.fs.accessAbsolute(p, .{})) |_| return p else |_| {
            std.log.warn("xaml_winmd_path does not exist: {s}", .{p});
            return null;
        }
    }

    const nuget_packages = std.process.getEnvVarOwned(b.allocator, "NUGET_PACKAGES") catch null;
    const user_profile = std.process.getEnvVarOwned(b.allocator, "USERPROFILE") catch null;
    const base = if (nuget_packages) |np|
        std.fs.path.join(b.allocator, &.{ np, "microsoft.windowsappsdk" }) catch return null
    else if (user_profile) |up|
        std.fs.path.join(b.allocator, &.{ up, ".nuget", "packages", "microsoft.windowsappsdk" }) catch return null
    else
        return null;

    if (std.fs.accessAbsolute(base, .{})) |_| {} else |_| {
        std.log.warn("windowsappsdk package base not found: {s}", .{base});
        return null;
    }

    var dir = std.fs.openDirAbsolute(base, .{ .iterate = true }) catch return null;
    defer dir.close();

    var versions = std.ArrayList([]const u8).empty;
    defer {
        for (versions.items) |v| b.allocator.free(v);
        versions.deinit(b.allocator);
    }

    var it = dir.iterate();
    while (it.next() catch null) |entry| {
        if (entry.kind != .directory) continue;
        const name = b.allocator.dupe(u8, entry.name) catch continue;
        versions.append(b.allocator, name) catch continue;
    }
    if (versions.items.len == 0) return null;

    std.mem.sort([]const u8, versions.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b2: []const u8) bool {
            return compareVersionDesc(a, b2);
        }
    }.lessThan);

    for (versions.items) |v| {
        const p = std.fs.path.join(b.allocator, &.{ base, v, "lib", "uap10.0", "Microsoft.UI.Xaml.winmd" }) catch continue;
        if (std.fs.accessAbsolute(p, .{})) |_| return p else |_| {}
    }

    return null;
}

fn compareVersionDesc(a: []const u8, b: []const u8) bool {
    const va = parseVersion(a);
    const vb = parseVersion(b);
    if (va.valid and vb.valid) {
        var i: usize = 0;
        while (i < va.count or i < vb.count) : (i += 1) {
            const av: u64 = if (i < va.count) va.parts[i] else 0;
            const bv: u64 = if (i < vb.count) vb.parts[i] else 0;
            if (av == bv) continue;
            return av > bv;
        }
        return false;
    }
    if (va.valid != vb.valid) return va.valid;
    return std.mem.order(u8, a, b) == .gt;
}

const ParsedVersion = struct {
    valid: bool,
    parts: [8]u64 = .{0} ** 8,
    count: usize = 0,
};

fn parseVersion(v: []const u8) ParsedVersion {
    var out: ParsedVersion = .{ .valid = true };
    var it = std.mem.splitScalar(u8, v, '.');
    while (it.next()) |seg| {
        if (seg.len == 0 or out.count >= out.parts.len) return .{ .valid = false };
        for (seg) |ch| {
            if (ch < '0' or ch > '9') return .{ .valid = false };
        }
        out.parts[out.count] = std.fmt.parseInt(u64, seg, 10) catch return .{ .valid = false };
        out.count += 1;
    }
    return out;
}

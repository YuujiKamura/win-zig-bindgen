const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const metadata_module = makeMetadataModule(b, target, optimize);

    const exe = b.addExecutable(.{
        .name = "win-zig-bindgen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("win_zig_metadata", metadata_module);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the win-zig-bindgen tool");
    run_step.dependOn(&run_cmd.step);

    // Quality Gate
    const audit_step = b.step("audit", "Run generation quality audit");
    const write_stubs = b.addWriteFiles();
    const winrt_stub = write_stubs.add("winrt.zig", 
        \\pub const GUID = struct { Data1: u32, Data2: u16, Data3: u16, Data4: [8]u8 };
        \\pub const HRESULT = i32;
        \\pub const HSTRING = *anyopaque;
        \\pub const WinRTError = anyerror;
        \\pub fn hrCheck(_: i32) anyerror!void {}
    );
    const os_stub = write_stubs.add("os.zig", 
        \\pub const HWND = *anyopaque;
    );

    const gen_cmd = b.addRunArtifact(exe);
    const xaml_winmd = "C:\\Users\\yuuji\\.nuget\\packages\\microsoft.windowsappsdk\\1.4.230822000\\lib\\uap10.0\\Microsoft.UI.Xaml.winmd";
    gen_cmd.addArgs(&.{ "-o" });
    const audit_com_path = gen_cmd.addOutputFileArg("audit_com.zig");
    gen_cmd.addArgs(&.{ xaml_winmd, "ITabView", "IUIElement", "ITextBox" });
    
    const audit_test_bin = b.addTest(.{
        .name = "audit-compile",
        .root_module = b.createModule(.{
            .root_source_file = audit_com_path,
            .target = target,
            .optimize = .Debug,
        }),
    });
    audit_test_bin.root_module.addImport("winrt.zig", b.createModule(.{ .root_source_file = winrt_stub }));
    audit_test_bin.root_module.addImport("os.zig", b.createModule(.{ .root_source_file = os_stub }));

    audit_step.dependOn(&gen_cmd.step);
    audit_step.dependOn(&b.addRunArtifact(audit_test_bin).step);

    // Standard Tests
    const test_bin = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_bin.root_module.addImport("win_zig_metadata", metadata_module);
    const run_tests = b.addRunArtifact(test_bin);
    
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(audit_step);

    const winmd2zig_main_module = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });
    winmd2zig_main_module.addImport("win_zig_metadata", metadata_module);

    const red_test_bin = b.addTest(.{
        .name = "test-red",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/red_function_generation.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    red_test_bin.root_module.addImport("winmd2zig_main", winmd2zig_main_module);
    red_test_bin.root_module.addImport("win_zig_metadata", metadata_module);
    const run_red_tests = b.addRunArtifact(red_test_bin);
    const test_red_step = b.step("test-red", "Run RED parity tests");
    test_red_step.dependOn(&run_red_tests.step);
    test_step.dependOn(test_red_step);

    // Single-shot quality gate for local/CI use.
    const gate_step = b.step("gate", "Run the full quality gate (tests + audits + parity checks)");

    // First step: regenerate Rust parity case map from Rust corpus + Zig test corpus.
    const sync_map_cmd = b.addRunArtifact(exe);
    sync_map_cmd.addArgs(&.{
        "--sync-rust-case-map",
        "shadow/windows-rs/bindgen-cases.json",
        "tests/red_function_generation.zig",
        "docs/rust-parity-case-map.json",
    });

    test_step.dependOn(&sync_map_cmd.step);
    gate_step.dependOn(test_step);

    const script_checks = [_][]const u8{
        "scripts/check-metadata-sync.ps1",
        "scripts/check-tabview-delegate-iids.ps1",
        "scripts/check-delegate-iid-vectors.ps1",
        "scripts/check-rust-case-map.ps1",
        "scripts/test-script-guards.ps1",
    };

    for (script_checks) |script| {
        const cmd = b.addSystemCommand(&.{
            "pwsh",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            script,
        });
        cmd.step.dependOn(&sync_map_cmd.step);
        gate_step.dependOn(&cmd.step);
    }
}

fn makeMetadataModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const sibling_rel = "../win-zig-metadata/lib.zig";
    const sibling_abs = b.pathFromRoot(sibling_rel);
    if (std.fs.accessAbsolute(sibling_abs, .{})) |_| {
        return b.createModule(.{ .root_source_file = b.path(sibling_rel), .target = target, .optimize = optimize });
    } else |_| {
        return b.createModule(.{ .root_source_file = b.path("metadata_local.zig"), .target = target, .optimize = optimize });
    }
}

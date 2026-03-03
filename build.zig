const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const metadata_module = makeMetadataModule(b, target, optimize);

    const exe = b.addExecutable(.{
        .name = "winmd2zig",
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

    const run_step = b.step("run", "Run winmd2zig");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.root_module.addImport("win_zig_metadata", metadata_module);
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run winmd2zig tests");
    test_step.dependOn(&run_tests.step);
}

fn makeMetadataModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const opt_path = b.option([]const u8, "win_zig_metadata_path", "Path to win-zig-metadata lib.zig");
    if (opt_path) |p| {
        return b.createModule(.{
            .root_source_file = .{ .cwd_relative = p },
            .target = target,
            .optimize = optimize,
        });
    }

    const sibling_rel = "../win-zig-metadata/lib.zig";
    const sibling_abs = b.pathFromRoot(sibling_rel);
    if (std.fs.accessAbsolute(sibling_abs, .{})) |_| {
        return b.createModule(.{
            .root_source_file = b.path(sibling_rel),
            .target = target,
            .optimize = optimize,
        });
    } else |_| {
        return b.createModule(.{
            .root_source_file = b.path("metadata_local.zig"),
            .target = target,
            .optimize = optimize,
        });
    }
}

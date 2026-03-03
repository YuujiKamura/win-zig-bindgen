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
    const sibling = "..\\win-zig-metadata\\lib.zig";
    if (std.fs.cwd().access(sibling, .{})) |_| {
        return b.createModule(.{
            .root_source_file = b.path(sibling),
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

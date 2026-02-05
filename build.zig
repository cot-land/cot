const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Compiler executable
    const exe = b.addExecutable(.{
        .name = "cot",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    // Run: zig build run -- <args>
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the compiler").dependOn(&run_cmd.step);

    // Test: zig build test
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_tests = b.addRunArtifact(tests);
    if (b.args) |args| run_tests.addArgs(args);
    b.step("test", "Run unit tests").dependOn(&run_tests.step);

    // Native E2E tests: zig build test-native
    // Filters to only run "native:" prefixed tests.
    const native_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"native:"},
    });
    const run_native = b.addRunArtifact(native_tests);
    b.step("test-native", "Run native AOT E2E tests (slow)").dependOn(&run_native.step);
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Module
    const mod = b.addModule("uuidz", .{
        .root_source_file = b.path("src/uuidz.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Library
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "uuidz",
        .root_module = mod,
    });

    // Example
    const example = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "uuidz", .module = mod },
            },
        }),
        // https://github.com/ziglang/zig/issues/24181
        .use_llvm = true,
    });

    const run_example = b.addRunArtifact(example);
    const example_step = b.step("example", "Run usage example");
    example_step.dependOn(&run_example.step);

    // Benchmark
    const benchmark = b.addExecutable(.{
        .name = "benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmark.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "uuidz", .module = mod },
            },
        }),
        // https://github.com/ziglang/zig/issues/24181
        .use_llvm = true,
    });

    if (b.lazyDependency("uuid_zig", .{})) |uuid_zig| {
        benchmark.root_module.addImport("uuid_zig", uuid_zig.module("uuid"));
    }

    const run_benchmark = b.addRunArtifact(benchmark);
    const bench_step = b.step("bench", "Run ClockSequence performance benchmark");
    bench_step.dependOn(&run_benchmark.step);

    // Test
    const tests = b.addTest(.{
        .root_module = mod,
        // https://github.com/ziglang/zig/issues/24181
        .use_llvm = true,
    });
    b.installArtifact(tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&tests.step);

    // Docs
    const docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Install docs into zig-out/docs");
    docs_step.dependOn(&docs.step);
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Library
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "uuidz",
        .root_module = mod,
    });
    b.installArtifact(lib);

    // Example
    const example = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("example.zig"),
        .target = target,
        .optimize = optimize,
    });
    example.root_module.addImport("uuidz", mod);
    b.installArtifact(example);

    const run_example = b.addRunArtifact(example);
    const example_step = b.step("example", "Run usage example");
    example_step.dependOn(&run_example.step);

    // Benchmark
    const benchmark = b.addExecutable(.{
        .name = "benchmark",
        .root_source_file = b.path("benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    benchmark.root_module.addImport("uuidz", mod);
    b.installArtifact(benchmark);

    const run_benchmark = b.addRunArtifact(benchmark);
    const bench_step = b.step("bench", "Run ClockSequence performance benchmark");
    bench_step.dependOn(&run_benchmark.step);

    // Test
    const tests = b.addTest(.{
        .root_module = mod,
    });
    const test_artifact = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&test_artifact.step);

    // Docs
    const docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Install docs into zig-out/docs");
    docs_step.dependOn(&docs.step);
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "uuidz",
        .root_module = mod,
    });

    b.installArtifact(lib);

    // Example executable
    const example = b.addExecutable(.{
        .name = "usage",
        .root_source_file = b.path("examples/usage.zig"),
        .target = target,
        .optimize = optimize,
    });
    example.root_module.addImport("uuidz", mod);
    b.installArtifact(example);

    const run_example = b.addRunArtifact(example);
    const example_step = b.step("example", "Run usage example");
    example_step.dependOn(&run_example.step);

    const tests = b.addTest(.{
        .root_module = mod,
    });

    const test_artifact = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run unit tests");

    test_step.dependOn(&test_artifact.step);
}

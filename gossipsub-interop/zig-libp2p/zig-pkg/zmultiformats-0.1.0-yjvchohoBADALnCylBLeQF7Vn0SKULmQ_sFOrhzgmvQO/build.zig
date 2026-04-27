const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the module
    const root_module = b.addModule("multiformats-zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create the library
    const lib = b.addLibrary(.{
        .name = "multiformats-zig",
        .root_module = root_module,
        .linkage = .static,
    });

    b.installArtifact(lib);

    setupBenchmarks(b, target, optimize);

    // Test setup
    const lib_unit_tests = b.addTest(.{
        .root_module = root_module,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}

fn setupBenchmarks(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const bench_step = b.step("bench", "Build And Run Benchmarks");
    const bench_name = "multibase_bench";
    const period_option = b.option([]const u8, "period", "Period of the benchmark") orelse "10";
    const times_option = b.option([]const u8, "times", "times of the benchmark") orelse "10000";
    const method_option = b.option([]const u8, "method", "method of Base action") orelse "encode";
    const code_option = b.option([]const u8, "code", "code of the Base type") orelse "";

    const bench_module = b.createModule(.{
        .root_source_file = b.path(b.fmt("src/{s}.zig", .{bench_name})),
        .target = target,
        .optimize = optimize,
    });

    const benchmark = b.addExecutable(.{
        .name = bench_name,
        .root_module = bench_module,
    });
    const run_benchmark = b.addRunArtifact(benchmark);
    run_benchmark.addArgs(&.{ "--period", period_option });
    run_benchmark.addArgs(&.{ "--times", times_option });
    run_benchmark.addArgs(&.{ "--method", method_option });
    run_benchmark.addArgs(&.{ "--code", code_option });
    bench_step.dependOn(&run_benchmark.step);
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const multiformats_dep = b.dependency("zmultiformats", .{
        .target = target,
        .optimize = optimize,
    });
    const multiformats_module = multiformats_dep.module("multiformats-zig");

    const peerid_dep = b.dependency("peer_id", .{
        .target = target,
        .optimize = optimize,
    });
    const peerid_module = peerid_dep.module("peer-id");

    const multiaddr_module = b.addModule("multiaddr", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    multiaddr_module.addImport("multiformats", multiformats_module);
    multiaddr_module.addImport("peer-id", peerid_module);

    const lib = b.addLibrary(.{
        .name = "multiaddr",
        .root_module = multiaddr_module,
        .linkage = .static,
    });

    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = multiaddr_module,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}

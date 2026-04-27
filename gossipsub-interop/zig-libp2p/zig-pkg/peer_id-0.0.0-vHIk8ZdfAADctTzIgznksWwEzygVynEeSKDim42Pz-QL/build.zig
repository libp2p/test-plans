const std = @import("std");
const ProtoGenStep = @import("gremlin").ProtoGenStep;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const gremlin_dep = b.dependency("gremlin", .{
        .target = target,
        .optimize = optimize,
    });
    const gremlin_module = gremlin_dep.module("gremlin");

    const protobuf = ProtoGenStep.create(
        b,
        .{
            .proto_sources = b.path("src"),
            .target = b.path("src"),
        },
    );

    const peer_id_module = b.addModule("peer-id", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    peer_id_module.addImport("gremlin", gremlin_module);

    const multiformats_dep = b.dependency("zmultiformats", .{
        .target = target,
        .optimize = optimize,
    });
    const multiformats_module = multiformats_dep.module("multiformats-zig");
    peer_id_module.addImport("multiformats", multiformats_module);

    const lib = b.addLibrary(.{
        .name = "peer-id",
        .root_module = peer_id_module,
        .linkage = .static,
    });
    lib.step.dependOn(&protobuf.step);

    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = peer_id_module,
    });

    lib_unit_tests.step.dependOn(&protobuf.step);
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&install_docs.step);
}

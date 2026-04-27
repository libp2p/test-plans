const std = @import("std");

/// NOTE: Due to a Zig 0.15 limitation, translate-c steps in transitive
/// path dependencies (boringssl/ssl.zig) do not execute in a standalone
/// project's local cache.
///
/// Build via the Makefile target instead:
///   make binaries
///
/// Which runs:
///   zig build --build-file ../../eth-p2p-z/build.zig --prefix zig-libp2p/zig-out
///   cp zig-libp2p/zig-out/bin/gossipsub-bin zig-libp2p/gossipsub-bin
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // eth-p2p-z as a path dependency (swap for a git URL when publishing)
    const libp2p_dep = b.dependency("libp2p", .{
        .target = target,
        .optimize = optimize,
    });
    const libp2p_module = libp2p_dep.module("zig-libp2p");

    // lsquic: C artifact needed for final linking
    const lsquic_dep = libp2p_dep.builder.dependency("lsquic", .{
        .target = target,
        .optimize = optimize,
    });
    const lsquic_artifact = lsquic_dep.artifact("lsquic");

    // peer_id: main.zig uses @import("peer_id") directly for PeerId + keys
    const multiaddr_dep = libp2p_dep.builder.dependency("multiaddr", .{
        .target = target,
        .optimize = optimize,
    });
    const peer_id_dep = multiaddr_dep.builder.dependency("peer_id", .{
        .target = target,
        .optimize = optimize,
    });
    const peer_id_module = peer_id_dep.module("peer-id");

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_module.addImport("zig-libp2p", libp2p_module);
    exe_module.addImport("peer_id", peer_id_module);

    const exe = b.addExecutable(.{
        .name = "gossipsub-bin",
        .root_module = exe_module,
    });
    exe.linkLibrary(lsquic_artifact);
    exe.linkSystemLibrary(switch (target.result.os.tag) {
        .windows => "zlib1",
        else => "z",
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run gossipsub-bin").dependOn(&run_cmd.step);
}

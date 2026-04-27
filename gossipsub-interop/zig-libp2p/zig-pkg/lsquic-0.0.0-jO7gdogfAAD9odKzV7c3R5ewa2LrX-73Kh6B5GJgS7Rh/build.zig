const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("lsquic", .{
        .target = target,
        .optimize = optimize,
    });
    const boringssl = b.dependency("boringssl", .{
        .target = target,
        .optimize = optimize,
    });
    const lshpack_dep = b.dependency("lshpack", .{
        .target = target,
        .optimize = optimize,
    });
    const lsqpack_dep = b.dependency("lsqpack", .{
        .target = target,
        .optimize = optimize,
    });

    const ssl = boringssl.artifact("ssl");
    const crypto = boringssl.artifact("crypto");

    const lib = b.addLibrary(.{
        .name = "lsquic",
        .linkage = .static,

        .root_module = b.createModule(
            .{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            },
        ),
    });

    var c_flags: std.ArrayList([]const u8) = .empty;

    c_flags.appendSlice(b.allocator, &.{
        "-DLSQUIC_DEBUG_NEXT_ADV_TICK=1",
        "-DLSQUIC_CONN_STATS=1",
        "-DLSQUIC_DEVEL=1",
        "-DLSQUIC_WEBTRANSPORT_SERVER_SUPPORT=1",
        // When using the Zig ReleaseSafe mode, it seems force to check for undefined behavior.
        // This is not the case with ReleaseSmall or ReleaseFast. So we must add this flag
        // to avoid the build failing with ReleaseSafe.
        "-fno-sanitize=undefined",
    }) catch @panic("OOM");

    if (optimize == .Debug) {
        c_flags.appendSlice(b.allocator, &.{ "-O0", "-g3" }) catch @panic("OOM");
    } else {
        c_flags.appendSlice(b.allocator, &.{ "-O3", "-g0" }) catch @panic("OOM");
    }

    if (target.result.os.tag == .windows) {
        // When we have a windows test environment, we can enable these flags.
        // lib.addIncludePath(upstream.path("wincompat"));
        // c_flags.appendSlice(&.{
        //     "/W4",                       "/WX",
        //     "-DWIN32_LEAN_AND_MEAN",     "-DNOMINMAX",
        //     "-D_CRT_SECURE_NO_WARNINGS", "/wd4100",
        //     "/wd4115",                   "/wd4116",
        //     "/wd4146",                   "/wd4132",
        //     "/wd4200",                   "/wd4204",
        //     "/wd4244",                   "/wd4245",
        //     "/wd4267",                   "/wd4214",
        //     "/wd4295",                   "/wd4324",
        //     "/wd4334",                   "/wd4456",
        //     "/wd4459",                   "/wd4706",
        //     "/wd4090",                   "/wd4305",
        // }) catch @panic("OOM");
    } else {
        c_flags.appendSlice(b.allocator, &.{
            // Lifted from lsquic's CMakeLists.txt
            // Source: https://github.com/litespeedtech/lsquic/blob/70486141724f85e97b08f510673e29f399bbae8f/CMakeLists.txt#L52-L53
            "-Wall",
            "-Wextra",
            "-Wno-unused-parameter",
            "-fno-omit-frame-pointer",
        }) catch @panic("OOM");
    }

    // --- Linking and Paths ---
    lib.linkLibC();
    lib.linkLibrary(ssl);
    lib.linkLibrary(crypto);

    if (target.result.os.tag == .windows) {
        // Uncomment these when we have a windows test environment.
        // lib.linkSystemLibrary("ws2_32");
    } else {
        lib.linkSystemLibrary("m");
        lib.linkSystemLibrary("pthread");
    }

    lib.addIncludePath(upstream.path("include"));
    lib.addIncludePath(lshpack_dep.path(""));
    lib.addIncludePath(lsqpack_dep.path(""));
    lib.addIncludePath(lshpack_dep.path("deps/xxhash"));

    lib.installHeadersDirectory(
        upstream.path("include"),
        "",
        .{ .include_extensions = &.{".h"} },
    );
    lib.installHeader(lsqpack_dep.path("lsqpack.h"), "lsqpack/lsqpack.h");
    lib.installHeader(lshpack_dep.path("lshpack.h"), "lshpack/lshpack.h");
    lib.installHeader(lshpack_dep.path("deps/xxhash/xxhash.h"), "xxhash.h");
    lib.root_module.addCMacro("XXH_HEADER_NAME", "\"xxhash.h\"");

    lib.addCSourceFiles(.{
        .root = upstream.path("src/liblsquic"),
        .files = lsquic_files,
        .flags = c_flags.items,
    });
    lib.addCSourceFile(.{ .file = lsqpack_dep.path("lsqpack.c"), .flags = c_flags.items });
    lib.addCSourceFile(.{ .file = lshpack_dep.path("lshpack.c"), .flags = c_flags.items });
    lib.addCSourceFile(.{ .file = lshpack_dep.path("deps/xxhash/xxhash.c"), .flags = c_flags.items });

    b.installArtifact(lib);

    const test_step = b.step("test", "Run unit tests");
    _ = test_step;
}

const lsquic_files: []const []const u8 = &.{
    "ls-sfparser.c",
    "lsquic_adaptive_cc.c",
    "lsquic_alarmset.c",
    "lsquic_arr.c",
    "lsquic_attq.c",
    "lsquic_bbr.c",
    "lsquic_bw_sampler.c",
    "lsquic_cfcw.c",
    "lsquic_chsk_stream.c",
    "lsquic_conn.c",
    "lsquic_crand.c",
    "lsquic_crt_compress.c",
    "lsquic_crypto.c",
    "lsquic_cubic.c",
    "lsquic_di_error.c",
    "lsquic_di_hash.c",
    "lsquic_di_nocopy.c",
    "lsquic_enc_sess_common.c",
    "lsquic_enc_sess_ietf.c",
    "lsquic_eng_hist.c",
    "lsquic_engine.c",
    "lsquic_ev_log.c",
    "lsquic_frab_list.c",
    "lsquic_frame_common.c",
    "lsquic_frame_reader.c",
    "lsquic_frame_writer.c",
    "lsquic_full_conn.c",
    "lsquic_full_conn_ietf.c",
    "lsquic_global.c",
    "lsquic_handshake.c",
    "lsquic_hash.c",
    "lsquic_hcsi_reader.c",
    "lsquic_hcso_writer.c",
    "lsquic_headers_stream.c",
    "lsquic_hkdf.c",
    "lsquic_hpi.c",
    "lsquic_hspack_valid.c",
    "lsquic_http.c",
    "lsquic_http1x_if.c",
    "lsquic_logger.c",
    "lsquic_malo.c",
    "lsquic_min_heap.c",
    "lsquic_mini_conn.c",
    "lsquic_mini_conn_ietf.c",
    "lsquic_minmax.c",
    "lsquic_mm.c",
    "lsquic_pacer.c",
    "lsquic_packet_common.c",
    "lsquic_packet_gquic.c",
    "lsquic_packet_in.c",
    "lsquic_packet_out.c",
    "lsquic_packet_resize.c",
    "lsquic_parse_Q046.c",
    "lsquic_parse_Q050.c",
    "lsquic_parse_common.c",
    "lsquic_parse_gquic_be.c",
    "lsquic_parse_gquic_common.c",
    "lsquic_parse_ietf_v1.c",
    "lsquic_parse_iquic_common.c",
    "lsquic_pr_queue.c",
    "lsquic_purga.c",
    "lsquic_qdec_hdl.c",
    "lsquic_qenc_hdl.c",
    "lsquic_qlog.c",
    "lsquic_qpack_exp.c",
    "lsquic_rechist.c",
    "lsquic_rtt.c",
    "lsquic_send_ctl.c",
    "lsquic_senhist.c",
    "lsquic_set.c",
    "lsquic_sfcw.c",
    "lsquic_shsk_stream.c",
    "lsquic_spi.c",
    "lsquic_stock_shi.c",
    "lsquic_str.c",
    "lsquic_stream.c",
    "lsquic_tokgen.c",
    "lsquic_trans_params.c",
    "lsquic_trechist.c",
    "lsquic_util.c",
    "lsquic_varint.c",
    "lsquic_version.c",
    "lsquic_xxhash.c",
};

pub const packages = struct {
    pub const @"../../../eth-p2p-z" = struct {
        pub const build_root = "/Users/mercynaps/zig/test-plans/gossipsub-interop/zig-libp2p/../../../eth-p2p-z";
        pub const build_zig = @import("../../../eth-p2p-z");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "libxev", "libxev-0.0.0-86vtc0IbEwBzMSXa-ZPZ8JpcV4Mw1SrsTuvtJmFAQ7Uu" },
            .{ "zmultiformats", "zmultiformats-0.1.0-yjvchohoBADALnCylBLeQF7Vn0SKULmQ_sFOrhzgmvQO" },
            .{ "gremlin", "gremlin-0.1.0-E2s91STHEQAvlGGPBw_vUYNiA_YkGanSINVKpc2oqJw1" },
            .{ "lsquic", "lsquic-0.0.0-jO7gdogfAAD9odKzV7c3R5ewa2LrX-73Kh6B5GJgS7Rh" },
            .{ "cache", "cache-0.0.0-winRwKaSAAAKIcUzY8IXwcbH050imeWPFMbPW_sCdPLF" },
            .{ "secp256k1", "secp256k1-0.0.3-vtxi58DhAABoPpDgG3wagaDXiHHIDezLOPE0BI4V0bDS" },
            .{ "multiaddr", "multiaddr-0.1.0-Cjayds-5AAArNw0ghMgquaRygVf7-kEWQJlQGjVpZzZ0" },
        };
    };
    pub const @"1220bb683a6df744e618f58a008eaae3eb62b70a78334cec676bd82b1b9e8e944eeb" = struct {
        pub const build_root = "/Users/mercynaps/.cache/zig/p/N-V-__8AAJ4DSwC7aDpt90TmGPWKAI6q4-titwp4M0zsZ2vY";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"N-V-__8AAALQZACNAeMe8qEYieQId_sO9YzLbIyJyVwryHz_" = struct {
        pub const build_root = "/Users/mercynaps/.cache/zig/p/N-V-__8AAALQZACNAeMe8qEYieQId_sO9YzLbIyJyVwryHz_";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"N-V-__8AAB0eQwD-0MdOEBmz7intriBReIsIDNlukNVoNu6o" = struct {
        pub const build_root = "/Users/mercynaps/.cache/zig/p/N-V-__8AAB0eQwD-0MdOEBmz7intriBReIsIDNlukNVoNu6o";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"N-V-__8AADGOTAg2qy2JMjVSleelXVWZhf9UTIjkuioQsv9-" = struct {
        pub const build_root = "/Users/mercynaps/.cache/zig/p/N-V-__8AADGOTAg2qy2JMjVSleelXVWZhf9UTIjkuioQsv9-";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"N-V-__8AAFo5VQCMGNos53oUbtdyzgRTdBedy52h5FsecO51" = struct {
        pub const build_root = "/Users/mercynaps/.cache/zig/p/N-V-__8AAFo5VQCMGNos53oUbtdyzgRTdBedy52h5FsecO51";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"N-V-__8AAKHvVgBsNJVDKKVAFfD0XLyv3NZA7q19Lkm6ozff" = struct {
        pub const build_root = "/Users/mercynaps/.cache/zig/p/N-V-__8AAKHvVgBsNJVDKKVAFfD0XLyv3NZA7q19Lkm6ozff";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"boringssl-0.1.0-VtJeWehMAAA4RNnwRnzEvKcS9rjsR1QVRw1uJrwXxmVK" = struct {
        pub const build_root = "/Users/mercynaps/.cache/zig/p/boringssl-0.1.0-VtJeWehMAAA4RNnwRnzEvKcS9rjsR1QVRw1uJrwXxmVK";
        pub const build_zig = @import("boringssl-0.1.0-VtJeWehMAAA4RNnwRnzEvKcS9rjsR1QVRw1uJrwXxmVK");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "ssl", "N-V-__8AADGOTAg2qy2JMjVSleelXVWZhf9UTIjkuioQsv9-" },
        };
    };
    pub const @"cache-0.0.0-winRwKaSAAAKIcUzY8IXwcbH050imeWPFMbPW_sCdPLF" = struct {
        pub const build_root = "/Users/mercynaps/.cache/zig/p/cache-0.0.0-winRwKaSAAAKIcUzY8IXwcbH050imeWPFMbPW_sCdPLF";
        pub const build_zig = @import("cache-0.0.0-winRwKaSAAAKIcUzY8IXwcbH050imeWPFMbPW_sCdPLF");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"gremlin-0.1.0-E2s91STHEQAvlGGPBw_vUYNiA_YkGanSINVKpc2oqJw1" = struct {
        pub const build_root = "/Users/mercynaps/.cache/zig/p/gremlin-0.1.0-E2s91STHEQAvlGGPBw_vUYNiA_YkGanSINVKpc2oqJw1";
        pub const build_zig = @import("gremlin-0.1.0-E2s91STHEQAvlGGPBw_vUYNiA_YkGanSINVKpc2oqJw1");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"gremlin-0.1.0-E2s91WkYEQCC1_KteI5rN9EU_tuyyZftimIOI4S4f8Fc" = struct {
        pub const build_root = "/Users/mercynaps/.cache/zig/p/gremlin-0.1.0-E2s91WkYEQCC1_KteI5rN9EU_tuyyZftimIOI4S4f8Fc";
        pub const build_zig = @import("gremlin-0.1.0-E2s91WkYEQCC1_KteI5rN9EU_tuyyZftimIOI4S4f8Fc");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"libxev-0.0.0-86vtc0IbEwBzMSXa-ZPZ8JpcV4Mw1SrsTuvtJmFAQ7Uu" = struct {
        pub const build_root = "/Users/mercynaps/.cache/zig/p/libxev-0.0.0-86vtc0IbEwBzMSXa-ZPZ8JpcV4Mw1SrsTuvtJmFAQ7Uu";
        pub const build_zig = @import("libxev-0.0.0-86vtc0IbEwBzMSXa-ZPZ8JpcV4Mw1SrsTuvtJmFAQ7Uu");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"lsquic-0.0.0-jO7gdogfAAD9odKzV7c3R5ewa2LrX-73Kh6B5GJgS7Rh" = struct {
        pub const build_root = "/Users/mercynaps/.cache/zig/p/lsquic-0.0.0-jO7gdogfAAD9odKzV7c3R5ewa2LrX-73Kh6B5GJgS7Rh";
        pub const build_zig = @import("lsquic-0.0.0-jO7gdogfAAD9odKzV7c3R5ewa2LrX-73Kh6B5GJgS7Rh");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "lsquic", "N-V-__8AAALQZACNAeMe8qEYieQId_sO9YzLbIyJyVwryHz_" },
            .{ "boringssl", "boringssl-0.1.0-VtJeWehMAAA4RNnwRnzEvKcS9rjsR1QVRw1uJrwXxmVK" },
            .{ "zlib", "zlib-1.3.1-1-ZZQ7ldENAAA7qJjUXP6E6xnRuV-jDL9dyoJFc_eb3zQ6" },
            .{ "lshpack", "N-V-__8AAFo5VQCMGNos53oUbtdyzgRTdBedy52h5FsecO51" },
            .{ "lsqpack", "N-V-__8AAKHvVgBsNJVDKKVAFfD0XLyv3NZA7q19Lkm6ozff" },
        };
    };
    pub const @"multiaddr-0.1.0-Cjayds-5AAArNw0ghMgquaRygVf7-kEWQJlQGjVpZzZ0" = struct {
        pub const build_root = "/Users/mercynaps/.cache/zig/p/multiaddr-0.1.0-Cjayds-5AAArNw0ghMgquaRygVf7-kEWQJlQGjVpZzZ0";
        pub const build_zig = @import("multiaddr-0.1.0-Cjayds-5AAArNw0ghMgquaRygVf7-kEWQJlQGjVpZzZ0");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "zmultiformats", "zmultiformats-0.1.0-yjvchohoBADALnCylBLeQF7Vn0SKULmQ_sFOrhzgmvQO" },
            .{ "peer_id", "peer_id-0.0.0-vHIk8ZdfAADctTzIgznksWwEzygVynEeSKDim42Pz-QL" },
        };
    };
    pub const @"peer_id-0.0.0-vHIk8ZdfAADctTzIgznksWwEzygVynEeSKDim42Pz-QL" = struct {
        pub const build_root = "/Users/mercynaps/.cache/zig/p/peer_id-0.0.0-vHIk8ZdfAADctTzIgznksWwEzygVynEeSKDim42Pz-QL";
        pub const build_zig = @import("peer_id-0.0.0-vHIk8ZdfAADctTzIgznksWwEzygVynEeSKDim42Pz-QL");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "zmultiformats", "zmultiformats-0.1.0-yjvchohoBADALnCylBLeQF7Vn0SKULmQ_sFOrhzgmvQO" },
            .{ "gremlin", "gremlin-0.1.0-E2s91WkYEQCC1_KteI5rN9EU_tuyyZftimIOI4S4f8Fc" },
        };
    };
    pub const @"secp256k1-0.0.3-vtxi58DhAABoPpDgG3wagaDXiHHIDezLOPE0BI4V0bDS" = struct {
        pub const build_root = "/Users/mercynaps/.cache/zig/p/secp256k1-0.0.3-vtxi58DhAABoPpDgG3wagaDXiHHIDezLOPE0BI4V0bDS";
        pub const build_zig = @import("secp256k1-0.0.3-vtxi58DhAABoPpDgG3wagaDXiHHIDezLOPE0BI4V0bDS");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "libsecp256k1", "1220bb683a6df744e618f58a008eaae3eb62b70a78334cec676bd82b1b9e8e944eeb" },
        };
    };
    pub const @"zlib-1.3.1-1-ZZQ7ldENAAA7qJjUXP6E6xnRuV-jDL9dyoJFc_eb3zQ6" = struct {
        pub const build_root = "/Users/mercynaps/.cache/zig/p/zlib-1.3.1-1-ZZQ7ldENAAA7qJjUXP6E6xnRuV-jDL9dyoJFc_eb3zQ6";
        pub const build_zig = @import("zlib-1.3.1-1-ZZQ7ldENAAA7qJjUXP6E6xnRuV-jDL9dyoJFc_eb3zQ6");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "zlib", "N-V-__8AAB0eQwD-0MdOEBmz7intriBReIsIDNlukNVoNu6o" },
        };
    };
    pub const @"zmultiformats-0.1.0-yjvchohoBADALnCylBLeQF7Vn0SKULmQ_sFOrhzgmvQO" = struct {
        pub const build_root = "/Users/mercynaps/.cache/zig/p/zmultiformats-0.1.0-yjvchohoBADALnCylBLeQF7Vn0SKULmQ_sFOrhzgmvQO";
        pub const build_zig = @import("zmultiformats-0.1.0-yjvchohoBADALnCylBLeQF7Vn0SKULmQ_sFOrhzgmvQO");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "libp2p", "../../../eth-p2p-z" },
};

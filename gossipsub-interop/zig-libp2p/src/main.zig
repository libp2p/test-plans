/// Phase 2.1 — Binary Skeleton
///
/// Starts up, derives a deterministic PeerID from the Shadow node hostname,
/// logs it to stdout in the same JSON format as the Go binary, then exits.
///
/// TODO Phase 2.3: wire TCP + TLS + Yamux host listening on port 9000
/// TODO Phase 2.2: parse params file and run experiment instructions

pub const std_options = @import("zig-libp2p").std_options;

const std = @import("std");
const libp2p = @import("zig-libp2p");
const keys_mod = @import("peer_id").keys;
const PeerId = @import("peer_id").PeerId;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // ------------------------------------------------------------------ //
    // 1. Parse --params flag
    // ------------------------------------------------------------------ //
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var params_path: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--params") and i + 1 < args.len) {
            params_path = args[i + 1];
            i += 1;
        }
    }
    if (params_path == null) {
        std.log.err("--params <path> flag is required", .{});
        std.process.exit(1);
    }

    // ------------------------------------------------------------------ //
    // 2. Hostname → node ID
    //    Shadow sets hostnames as "node0", "node1", …
    // ------------------------------------------------------------------ //
    var hostname_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = try std.posix.gethostname(hostname_buf[0..]);

    var node_id: u64 = 0;
    if (std.mem.startsWith(u8, hostname, "node")) {
        node_id = std.fmt.parseInt(u64, hostname[4..], 10) catch blk: {
            std.log.warn("could not parse node ID from hostname '{s}', defaulting to 0", .{hostname});
            break :blk 0;
        };
    }

    // ------------------------------------------------------------------ //
    // 3. Deterministic ED25519 key — matches Go's nodePrivKey(id):
    //      seed = [32]u8{0}, seed[0..8] = LE u64(node_id)
    //      privkey = ed25519.NewKeyFromSeed(seed)
    // ------------------------------------------------------------------ //
    const Ed25519 = std.crypto.sign.Ed25519;
    var seed: [Ed25519.KeyPair.seed_length]u8 = [_]u8{0} ** Ed25519.KeyPair.seed_length;
    std.mem.writeInt(u64, seed[0..8], node_id, .little);
    const ed_kp = try Ed25519.KeyPair.generateDeterministic(seed);

    // ------------------------------------------------------------------ //
    // 4. Derive libp2p PeerID from the ED25519 public key
    // ------------------------------------------------------------------ //
    var pub_key = keys_mod.PublicKey{
        .type = .ED25519,
        .data = &ed_kp.public_key.bytes,
    };
    const peer_id = try PeerId.fromPublicKey(allocator, &pub_key);

    const b58_len = peer_id.toBase58Len();
    const b58_buf = try allocator.alloc(u8, b58_len);
    defer allocator.free(b58_buf);
    const peer_id_str = try peer_id.toBase58(b58_buf);

    // ------------------------------------------------------------------ //
    // 5. Log PeerID to stdout — matches Go slog JSON format:
    //    {"time":"...","level":"INFO","msg":"PeerID","id":"<b58>","node_id":N}
    // ------------------------------------------------------------------ //
    const now_s = std.time.timestamp();
    const stdout_file: std.fs.File = .{ .handle = std.posix.STDOUT_FILENO };
    var stdout_buf: [512]u8 = undefined;
    var stdout_writer = stdout_file.writer(&stdout_buf);
    try stdout_writer.interface.print(
        "{{\"time\":\"{d}\",\"level\":\"INFO\",\"msg\":\"PeerID\",\"id\":\"{s}\",\"node_id\":{d}}}\n",
        .{ now_s, peer_id_str, node_id },
    );
    try stdout_writer.interface.flush();

    // ------------------------------------------------------------------ //
    // 6. Initialise event loop (proves the runtime starts cleanly)
    //    TCP listener + gossipsub host wired in Phase 2.3
    // ------------------------------------------------------------------ //
    var loop: libp2p.thread_event_loop.ThreadEventLoop = undefined;
    try loop.init(allocator);
    defer {
        loop.close();
        loop.deinit();
    }

    std.log.info("Phase 2.1 skeleton started — node_id={d} peer_id={s}", .{ node_id, peer_id_str });
    // Phase 2.2 will read params_path and execute experiment instructions here
}

const std = @import("std");
const Multicodec = @import("multicodec.zig").Multicodec;
const varint = @import("unsigned_varint.zig");
const testing = std.testing;

/// Multihash is a wrapper around a digest and a code.
/// S is larger or equal to the size of the digest.
pub fn Multihash(comptime S: usize) type {
    return struct {
        code: Multicodec,
        size: u8,
        digest: [S]u8,

        const Self = @This();

        /// wrap creates a new Multihash from a given code and digest.
        pub fn wrap(code: Multicodec, input_digest: []const u8) !Self {
            if (input_digest.len > S) {
                return error.InvalidSize;
            }

            var digest = [_]u8{0} ** S;
            @memcpy(digest[0..input_digest.len], input_digest[0..input_digest.len]); // Specify exact length

            return Self{
                .code = code,
                .size = @intCast(input_digest.len),
                .digest = digest,
            };
        }

        /// getCode returns the code of the Multihash.
        pub fn getCode(self: *const Self) Multicodec {
            return self.code;
        }

        /// getSize returns the size of the Multihash.
        pub fn getSize(self: *const Self) u8 {
            return self.size;
        }

        /// getDigest returns the digest of the Multihash.
        pub fn getDigest(self: *const Self) []const u8 {
            return self.digest[0..self.size];
        }

        /// truncate creates a new Multihash with a truncated digest.
        pub fn truncate(self: *const Self, new_size: u8) Self {
            return Self{
                .code = self.code,
                .size = @min(self.size, new_size),
                .digest = self.digest,
            };
        }

        /// resize creates a new Multihash with a resized digest.
        pub fn resize(self: *const Self, comptime R: usize) !Multihash(R) {
            if (self.size > R) {
                return error.InvalidSize;
            }

            var new_digest = [_]u8{0} ** R;
            @memcpy(new_digest[0..self.size], self.digest[0..self.size]);

            return Multihash(R){
                .code = self.code,
                .size = self.size,
                .digest = new_digest,
            };
        }

        pub fn encodedLen(self: *const Self) usize {
            var code_buf: [varint.bufferSize(u64)]u8 = undefined;
            const code_encoded = varint.encode(u64, self.code.getCode(), &code_buf);

            var size_buf: [varint.bufferSize(u8)]u8 = undefined;
            const size_encoded = varint.encode(u8, self.size, &size_buf);

            return code_encoded.len + size_encoded.len + self.size;
        }

        /// write writes the Multihash to a writer.
        pub fn write(self: *const Self, writer: anytype) !usize {
            var code_buf: [varint.bufferSize(u64)]u8 = undefined;
            const code_encoded = varint.encode(u64, self.code.getCode(), &code_buf);
            try writer.writeAll(code_encoded);

            var size_buf: [varint.bufferSize(u8)]u8 = undefined;
            const size_encoded = varint.encode(u8, self.size, &size_buf);
            try writer.writeAll(size_encoded);

            try writer.writeAll(self.digest[0..self.size]);

            return code_encoded.len + size_encoded.len + self.size;
        }

        /// readBytes reads a Multihash from a byte slice.
        pub fn readBytes(bytes: []const u8) !Self {
            var stream = std.io.fixedBufferStream(bytes);
            return try Self.read(stream.reader());
        }

        /// read reads a Multihash from a reader.
        pub fn read(reader: anytype) !Self {
            const code = try varint.decodeStream(reader, u64);
            const size = try varint.decodeStream(reader, u8);

            if (size > S) {
                return error.InvalidSize;
            }

            var digest = [_]u8{0} ** S;
            try reader.readNoEof(digest[0..size]);

            return Self{
                .code = try Multicodec.fromCode(code),
                .size = size,
                .digest = digest,
            };
        }

        /// toBytes converts the Multihash to a byte slice.
        pub fn toBytes(self: *const Self, dest: []u8) ![]const u8 {
            var stream = std.io.fixedBufferStream(dest);
            const written = try self.write(stream.writer());
            return dest[0..written];
        }
    };
}

/// MultihashDigest is a generic type that can be used to create a Multihash from a given input.
pub fn MultihashDigest(comptime T: type) type {
    const DigestSize = struct {
        fn getSize(comptime code: T) comptime_int {
            return switch (code) {
                .SHA2_256 => 32,
                .SHA2_512 => 64,
                .SHA3_224 => 28,
                .SHA3_256 => 32,
                .SHA3_384 => 48,
                .SHA3_512 => 64,
                .KECCAK_224 => 28,
                .KECCAK_256 => 32,
                .KECCAK_384 => 48,
                .KECCAK_512 => 64,
                .BLAKE2B_256 => 32,
                .BLAKE2B_512 => 64,
                .BLAKE2S_128 => 16,
                .BLAKE2S_256 => 32,
                .BLAKE3 => 64,
            };
        }
    };

    return struct {
        /// digest creates a new Multihash from the given input.
        pub fn digest(comptime code: T, input: []const u8) !Multihash(DigestSize.getSize(code)) {
            var hasher = Hasher.init(code);
            try hasher.update(input);
            const digest_bytes = switch (hasher) {
                inline else => |*h| h.finalize()[0..],
            };
            return try Multihash(DigestSize.getSize(code)).wrap(try Multicodec.fromCode(@intFromEnum(code)), digest_bytes);
        }
    };
}

/// Multihash is a generic type that can be used to create a Multihash from a given input.
pub const Hasher = union(enum) {
    sha2_256: Sha2_256,
    sha2_512: Sha2_512,
    sha3_224: Sha3_224,
    sha3_256: Sha3_256,
    sha3_384: Sha3_384,
    sha3_512: Sha3_512,
    keccak_224: Keccak_224,
    keccak_256: Keccak_256,
    keccak_384: Keccak_384,
    keccak_512: Keccak_512,
    blake2b256: Blake2b256,
    blake2b512: Blake2b512,
    blake2s128: Blake2s128,
    blake2s256: Blake2s256,
    blake3: Blake3,

    /// init initializes a new Hasher.
    pub fn init(code: MultihashCodecs) Hasher {
        return switch (code) {
            .SHA2_256 => .{ .sha2_256 = Sha2_256.init() },
            .SHA2_512 => .{ .sha2_512 = Sha2_512.init() },
            .SHA3_224 => .{ .sha3_224 = Sha3_224.init() },
            .SHA3_256 => .{ .sha3_256 = Sha3_256.init() },
            .SHA3_384 => .{ .sha3_384 = Sha3_384.init() },
            .SHA3_512 => .{ .sha3_512 = Sha3_512.init() },
            .KECCAK_224 => .{ .keccak_224 = Keccak_224.init() },
            .KECCAK_256 => .{ .keccak_256 = Keccak_256.init() },
            .KECCAK_384 => .{ .keccak_384 = Keccak_384.init() },
            .KECCAK_512 => .{ .keccak_512 = Keccak_512.init() },
            .BLAKE2B_256 => .{ .blake2b256 = Blake2b256.init() },
            .BLAKE2B_512 => .{ .blake2b512 = Blake2b512.init() },
            .BLAKE2S_128 => .{ .blake2s128 = Blake2s128.init() },
            .BLAKE2S_256 => .{ .blake2s256 = Blake2s256.init() },
            .BLAKE3 => .{ .blake3 = Blake3.init() },
        };
    }

    /// update updates the Hasher with the given data.
    pub fn update(self: *Hasher, data: []const u8) !void {
        switch (self.*) {
            inline else => |*h| try h.update(data),
        }
    }
};

/// MultihashCodecs is an enum that represents the different multihash codecs.
/// It is used to implement the MultihashDigest trait for all multihash digests.
pub const MultihashCodecs = enum(u64) {
    SHA2_256 = Multicodec.SHA2_256.getCode(),
    SHA2_512 = Multicodec.SHA2_512.getCode(),
    SHA3_224 = Multicodec.SHA3_224.getCode(),
    SHA3_256 = Multicodec.SHA3_256.getCode(),
    SHA3_384 = Multicodec.SHA3_384.getCode(),
    SHA3_512 = Multicodec.SHA3_512.getCode(),
    KECCAK_256 = Multicodec.KECCAK_256.getCode(),
    KECCAK_512 = Multicodec.KECCAK_512.getCode(),
    KECCAK_224 = Multicodec.KECCAK_224.getCode(),
    KECCAK_384 = Multicodec.KECCAK_384.getCode(),
    BLAKE2B_256 = Multicodec.BLAKE2B_256.getCode(),
    BLAKE2B_512 = Multicodec.BLAKE2B_512.getCode(),
    BLAKE2S_128 = Multicodec.BLAKE2S_128.getCode(),
    BLAKE2S_256 = Multicodec.BLAKE2S_256.getCode(),
    BLAKE3 = Multicodec.BLAKE3.getCode(),

    const DigestSize = struct {
        fn getSize(comptime code: MultihashCodecs) comptime_int {
            return switch (code) {
                .SHA2_256 => 32,
                .SHA2_512 => 64,
                .SHA3_224 => 28,
                .SHA3_256 => 32,
                .SHA3_384 => 48,
                .SHA3_512 => 64,
                .KECCAK_224 => 28,
                .KECCAK_256 => 32,
                .KECCAK_384 => 48,
                .KECCAK_512 => 64,
                .BLAKE2B_256 => 32,
                .BLAKE2B_512 => 64,
                .BLAKE2S_128 => 16,
                .BLAKE2S_256 => 32,
                .BLAKE3 => 64,
            };
        }
    };

    /// digest creates a new Multihash from the given input.
    pub fn digest(comptime code: MultihashCodecs, input: []const u8) !Multihash(DigestSize.getSize(code)) {
        var hasher = Hasher.init(code);
        try hasher.update(input);
        const digest_bytes = switch (hasher) {
            inline else => |*h| h.finalize()[0..],
        };
        return try Multihash(DigestSize.getSize(code)).wrap(try Multicodec.fromCode(@intFromEnum(code)), digest_bytes);
    }
};

/// Sha2_256 is a struct that represents the SHA2-256 hash algorithm.
/// It is used to implement the MultihashDigest trait for the SHA2-256 hash algorithm.
pub const Sha2_256 = struct {
    ctx: std.crypto.hash.sha2.Sha256,

    /// init initializes a new Sha2_256.
    pub fn init() Sha2_256 {
        return .{ .ctx = std.crypto.hash.sha2.Sha256.init(.{}) };
    }

    /// update updates the Sha2_256 with the given data.
    pub fn update(self: *Sha2_256, data: []const u8) !void {
        self.ctx.update(data);
    }

    /// finalize finalizes the Sha2_256 and returns the digest.
    pub fn finalize(self: *Sha2_256) [32]u8 {
        return self.ctx.finalResult();
    }
};

/// Sha2_512 is a struct that represents the SHA2-512 hash algorithm.
/// It is used to implement the MultihashDigest trait for the SHA2-512 hash algorithm.
pub const Sha2_512 = struct {
    ctx: std.crypto.hash.sha2.Sha512,

    /// init initializes a new Sha2_512.
    pub fn init() Sha2_512 {
        return .{ .ctx = std.crypto.hash.sha2.Sha512.init(.{}) };
    }

    /// update updates the Sha2_512 with the given data.
    pub fn update(self: *Sha2_512, data: []const u8) !void {
        self.ctx.update(data);
    }

    /// finalize finalizes the Sha2_512 and returns the digest.
    pub fn finalize(self: *Sha2_512) [64]u8 {
        return self.ctx.finalResult();
    }
};

/// Sha3_224 is a struct that represents the SHA3-224 hash algorithm.
/// It is used to implement the MultihashDigest trait for the SHA3-224 hash algorithm.
pub const Sha3_224 = struct {
    ctx: std.crypto.hash.sha3.Sha3_224,

    /// init initializes a new Sha3_224.
    pub fn init() Sha3_224 {
        return .{ .ctx = std.crypto.hash.sha3.Sha3_224.init(.{}) };
    }

    /// update updates the Sha3_224 with the given data.
    pub fn update(self: *Sha3_224, data: []const u8) !void {
        self.ctx.update(data);
    }

    /// finalize finalizes the Sha3_224 and returns the digest.
    pub fn finalize(self: *Sha3_224) [28]u8 {
        var out = [_]u8{0} ** 28;
        self.ctx.final(&out);
        return out;
    }
};

/// Sha3_256 is a struct that represents the SHA3-256 hash algorithm.
/// It is used to implement the MultihashDigest trait for the SHA3-256 hash algorithm.
pub const Sha3_256 = struct {
    ctx: std.crypto.hash.sha3.Sha3_256,

    /// init initializes a new Sha3_256.
    pub fn init() Sha3_256 {
        return .{ .ctx = std.crypto.hash.sha3.Sha3_256.init(.{}) };
    }

    /// update updates the Sha3_256 with the given data.
    pub fn update(self: *Sha3_256, data: []const u8) !void {
        self.ctx.update(data);
    }

    /// finalize finalizes the Sha3_256 and returns the digest.
    pub fn finalize(self: *Sha3_256) [32]u8 {
        var out = [_]u8{0} ** 32;
        self.ctx.final(&out);
        return out;
    }
};

/// Sha3_384 is a struct that represents the SHA3-384 hash algorithm.
/// It is used to implement the MultihashDigest trait for the SHA3-384 hash algorithm.
pub const Sha3_384 = struct {
    ctx: std.crypto.hash.sha3.Sha3_384,

    /// init initializes a new Sha3_384.
    pub fn init() Sha3_384 {
        return .{ .ctx = std.crypto.hash.sha3.Sha3_384.init(.{}) };
    }

    /// update updates the Sha3_384 with the given data.
    pub fn update(self: *Sha3_384, data: []const u8) !void {
        self.ctx.update(data);
    }

    /// finalize finalizes the Sha3_384 and returns the digest.
    pub fn finalize(self: *Sha3_384) [48]u8 {
        var out = [_]u8{0} ** 48;
        self.ctx.final(&out);
        return out;
    }
};

/// Sha3_512 is a struct that represents the SHA3-512 hash algorithm.
/// It is used to implement the MultihashDigest trait for the SHA3-512 hash algorithm.
pub const Sha3_512 = struct {
    ctx: std.crypto.hash.sha3.Sha3_512,

    /// init initializes a new Sha3_512.
    pub fn init() Sha3_512 {
        return .{ .ctx = std.crypto.hash.sha3.Sha3_512.init(.{}) };
    }

    /// update updates the Sha3_512 with the given data.
    pub fn update(self: *Sha3_512, data: []const u8) !void {
        self.ctx.update(data);
    }

    /// finalize finalizes the Sha3_512 and returns the digest.
    pub fn finalize(self: *Sha3_512) [64]u8 {
        var out = [_]u8{0} ** 64;
        self.ctx.final(&out);
        return out;
    }
};

/// Keccak-224 is a struct that represents the Keccak-224 hash algorithm.
/// It is used to implement the MultihashDigest trait for the Keccak-224 hash algorithm.
pub const Keccak_224 = struct {
    ctx: std.crypto.hash.sha3.Keccak(1600, 224, 0x01, 24),

    /// init initializes a new Keccak_224.
    pub fn init() Keccak_224 {
        return .{ .ctx = std.crypto.hash.sha3.Keccak(1600, 224, 0x01, 24).init(.{}) };
    }

    /// update updates the Keccak_224 with the given data.
    pub fn update(self: *Keccak_224, data: []const u8) !void {
        self.ctx.update(data);
    }

    /// finalize finalizes the Keccak_224 and returns the digest.
    pub fn finalize(self: *Keccak_224) [28]u8 {
        var out = [_]u8{0} ** 28;
        self.ctx.final(&out);
        return out;
    }
};

/// Keccak_256 is a struct that represents the Keccak-256 hash algorithm.
/// It is used to implement the MultihashDigest trait for the Keccak-256 hash algorithm.
pub const Keccak_256 = struct {
    ctx: std.crypto.hash.sha3.Keccak256,

    /// init initializes a new Keccak_256.
    pub fn init() Keccak_256 {
        return .{ .ctx = std.crypto.hash.sha3.Keccak256.init(.{}) };
    }

    /// update updates the Keccak_256 with the given data.
    pub fn update(self: *Keccak_256, data: []const u8) !void {
        self.ctx.update(data);
    }

    /// finalize finalizes the Keccak_256 and returns the digest.
    pub fn finalize(self: *Keccak_256) [32]u8 {
        var out = [_]u8{0} ** 32;
        self.ctx.final(&out);
        return out;
    }
};

/// Keccak_384 is a struct that represents the Keccak-384 hash algorithm.
/// It is used to implement the MultihashDigest trait for the Keccak-384 hash algorithm.
pub const Keccak_384 = struct {
    ctx: std.crypto.hash.sha3.Keccak(1600, 384, 0x01, 24),

    /// init initializes a new Keccak_384.
    pub fn init() Keccak_384 {
        return .{ .ctx = std.crypto.hash.sha3.Keccak(1600, 384, 0x01, 24).init(.{}) };
    }

    /// update updates the Keccak_384 with the given data.
    pub fn update(self: *Keccak_384, data: []const u8) !void {
        self.ctx.update(data);
    }

    /// finalize finalizes the Keccak_384 and returns the digest.
    pub fn finalize(self: *Keccak_384) [48]u8 {
        var out = [_]u8{0} ** 48;
        self.ctx.final(&out);
        return out;
    }
};

/// Keccak_512 is a struct that represents the Keccak-512 hash algorithm.
/// It is used to implement the MultihashDigest trait for the Keccak-512 hash algorithm.
pub const Keccak_512 = struct {
    ctx: std.crypto.hash.sha3.Keccak512,

    /// init initializes a new Keccak_512.
    pub fn init() Keccak_512 {
        return .{ .ctx = std.crypto.hash.sha3.Keccak512.init(.{}) };
    }

    /// update updates the Keccak_512 with the given data.
    pub fn update(self: *Keccak_512, data: []const u8) !void {
        self.ctx.update(data);
    }

    /// finalize finalizes the Keccak_512 and returns the digest.
    pub fn finalize(self: *Keccak_512) [64]u8 {
        var out = [_]u8{0} ** 64;
        self.ctx.final(&out);
        return out;
    }
};

/// Blake2b256 is a struct that represents the Blake2b-256 hash algorithm.
/// It is used to implement the MultihashDigest trait for the Blake2b-256 hash algorithm.
pub const Blake2b256 = struct {
    ctx: std.crypto.hash.blake2.Blake2b256,

    /// init initializes a new Blake2b256.
    pub fn init() Blake2b256 {
        return .{ .ctx = std.crypto.hash.blake2.Blake2b256.init(.{}) };
    }

    /// update updates the Blake2b256 with the given data.
    pub fn update(self: *Blake2b256, data: []const u8) !void {
        self.ctx.update(data);
    }

    /// finalize finalizes the Blake2b256 and returns the digest.
    pub fn finalize(self: *Blake2b256) [32]u8 {
        var out = [_]u8{0} ** 32;
        self.ctx.final(&out);
        return out;
    }
};

/// Blake2b512 is a struct that represents the Blake2b-512 hash algorithm.
/// It is used to implement the MultihashDigest trait for the Blake2b-512 hash algorithm.
pub const Blake2b512 = struct {
    ctx: std.crypto.hash.blake2.Blake2b512,

    /// init initializes a new Blake2b512.
    pub fn init() Blake2b512 {
        return .{ .ctx = std.crypto.hash.blake2.Blake2b512.init(.{}) };
    }

    /// update updates the Blake2b512 with the given data.
    pub fn update(self: *Blake2b512, data: []const u8) !void {
        self.ctx.update(data);
    }

    /// finalize finalizes the Blake2b512 and returns the digest.
    pub fn finalize(self: *Blake2b512) [64]u8 {
        var out = [_]u8{0} ** 64;
        self.ctx.final(&out);
        return out;
    }
};

/// Blake2s128 is a struct that represents the Blake2s-128 hash algorithm.
/// It is used to implement the MultihashDigest trait for the Blake2s-128 hash algorithm.
pub const Blake2s128 = struct {
    ctx: std.crypto.hash.blake2.Blake2s128,

    /// init initializes a new Blake2s128.
    pub fn init() Blake2s128 {
        return .{ .ctx = std.crypto.hash.blake2.Blake2s128.init(.{}) };
    }

    /// update updates the Blake2s128 with the given data.
    pub fn update(self: *Blake2s128, data: []const u8) !void {
        self.ctx.update(data);
    }

    /// finalize finalizes the Blake2s128 and returns the digest.
    pub fn finalize(self: *Blake2s128) [16]u8 {
        var out = [_]u8{0} ** 16;
        self.ctx.final(&out);
        return out;
    }
};

/// Blake2s256 is a struct that represents the Blake2s-256 hash algorithm.
/// It is used to implement the MultihashDigest trait for the Blake2s-256 hash algorithm.
pub const Blake2s256 = struct {
    ctx: std.crypto.hash.blake2.Blake2s256,

    /// init initializes a new Blake2s256.
    pub fn init() Blake2s256 {
        return .{ .ctx = std.crypto.hash.blake2.Blake2s256.init(.{}) };
    }

    /// update updates the Blake2s256 with the given data.
    pub fn update(self: *Blake2s256, data: []const u8) !void {
        self.ctx.update(data);
    }

    /// finalize finalizes the Blake2s256 and returns the digest.
    pub fn finalize(self: *Blake2s256) [32]u8 {
        var out = [_]u8{0} ** 32;
        self.ctx.final(&out);
        return out;
    }
};

/// Blake3 is a struct that represents the Blake3 hash algorithm.
/// It is used to implement the MultihashDigest trait for the Blake3 hash algorithm.
pub const Blake3 = struct {
    ctx: std.crypto.hash.Blake3,

    /// init initializes a new Blake3.
    pub fn init() Blake3 {
        return .{ .ctx = std.crypto.hash.Blake3.init(.{}) };
    }

    /// update updates the Blake3 with the given data.
    pub fn update(self: *Blake3, data: []const u8) !void {
        self.ctx.update(data);
    }

    /// finalize finalizes the Blake3 and returns the digest.
    pub fn finalize(self: *Blake3) [64]u8 {
        var out = [_]u8{0} ** 64;
        self.ctx.final(&out);
        return out;
    }
};

test "basic multihash operations" {
    const expected_digest = [_]u8{
        0xB9, 0x4D, 0x27, 0xB9, 0x93, 0x4D, 0x3E, 0x08,
        0xA5, 0x2E, 0x52, 0xD7, 0xDA, 0x7D, 0xAB, 0xFA,
        0xC4, 0x84, 0xEF, 0xE3, 0x7A, 0x53, 0x80, 0xEE,
        0x90, 0x88, 0xF7, 0xAC, 0xE2, 0xEF, 0xCD, 0xE9,
    };

    var mh = try Multihash(32).wrap(Multicodec.SHA2_256, &expected_digest);
    try testing.expectEqual(mh.getCode(), Multicodec.SHA2_256);
    try testing.expectEqual(mh.getSize(), expected_digest.len);
    try testing.expectEqualSlices(u8, mh.getDigest(), &expected_digest);
}
test "multihash resize" {
    const input = "test data";
    var mh = try Multihash(32).wrap(Multicodec.CIDV1, input);

    // Resize up
    var larger = try mh.resize(64);
    try testing.expectEqual(larger.getSize(), input.len);
    try testing.expectEqualSlices(u8, larger.getDigest(), input);

    // Resize down should fail
    try testing.expectError(error.InvalidSize, mh.resize(4));
}

test "multihash serialization" {
    const expected_bytes = [_]u8{ 0x12, 0x0a, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    var mh = try Multihash(32).wrap(Multicodec.SHA2_256, &[_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 });

    var buf: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const written = try mh.write(fbs.writer());
    try testing.expectEqual(written, expected_bytes.len);
    try testing.expectEqualSlices(u8, buf[0..written], &expected_bytes);
}

test "multihash deserialization" {
    const input = [_]u8{ 0x12, 0x0a, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    var fbs = std.io.fixedBufferStream(&input);
    var mh = try Multihash(32).read(fbs.reader());

    try testing.expectEqual(mh.getCode().getCode(), 0x12);
    try testing.expectEqual(mh.getSize(), 10);
    try testing.expectEqualSlices(u8, mh.getDigest(), input[2..]);
}

test "multihash truncate" {
    var mh = try Multihash(32).wrap(Multicodec.CIDV1, "hello world");
    const truncated = mh.truncate(5);
    try testing.expectEqual(truncated.getSize(), 5);
    try testing.expectEqualSlices(u8, truncated.getDigest(), "hello");
}

test "sha256 hash operations" {
    const input = "hello world";
    const hash = try MultihashCodecs.SHA2_256.digest(input);
    try testing.expectEqual(@as(u64, 0x12), hash.code.getCode());
    try testing.expectEqual(@as(usize, 32), hash.getSize());

    var hash1 = std.crypto.hash.sha2.Sha256.init(.{});
    hash1.update(input);
    const hash_bytes = hash1.finalResult();
    try testing.expectEqualSlices(u8, &hash_bytes, hash.getDigest());
}

test "sha512 hash operations" {
    const input = "hello world";
    const hash = try MultihashCodecs.SHA2_512.digest(input);
    try testing.expectEqual(@as(u64, 0x13), hash.code.getCode());
    try testing.expectEqual(@as(usize, 64), hash.getSize());

    var hash1 = std.crypto.hash.sha2.Sha512.init(.{});
    hash1.update(input);
    const hash_bytes = hash1.finalResult();
    try testing.expectEqualSlices(u8, &hash_bytes, hash.getDigest());
}

test "sha3_224 hash operations" {
    const input = "hello world";
    const hash = try MultihashCodecs.SHA3_224.digest(input);
    try testing.expectEqual(@as(u64, 0x17), hash.code.getCode());
    try testing.expectEqual(@as(usize, 28), hash.getSize());

    var hash1 = std.crypto.hash.sha3.Sha3_224.init(.{});
    hash1.update(input);
    var out = [_]u8{0} ** 28;
    hash1.final(&out);
    try testing.expectEqualSlices(u8, &out, hash.getDigest());
}

test "sha3_256 hash operations" {
    const input = "hello world";
    const hash = try MultihashCodecs.SHA3_256.digest(input);
    try testing.expectEqual(@as(u64, 0x16), hash.code.getCode());
    try testing.expectEqual(@as(usize, 32), hash.getSize());

    var hash1 = std.crypto.hash.sha3.Sha3_256.init(.{});
    hash1.update(input);
    var out = [_]u8{0} ** 32;
    hash1.final(&out);
    try testing.expectEqualSlices(u8, &out, hash.getDigest());
}

test "sha3_384 hash operations" {
    const input = "hello world";
    const hash = try MultihashCodecs.SHA3_384.digest(input);
    try testing.expectEqual(@as(u64, 0x15), hash.code.getCode());
    try testing.expectEqual(@as(usize, 48), hash.getSize());

    var hash1 = std.crypto.hash.sha3.Sha3_384.init(.{});
    hash1.update(input);
    var out = [_]u8{0} ** 48;
    hash1.final(&out);
    try testing.expectEqualSlices(u8, &out, hash.getDigest());
}

test "sha3_512 hash operations" {
    const input = "hello world";
    const hash = try MultihashCodecs.SHA3_512.digest(input);
    try testing.expectEqual(@as(u64, 0x14), hash.code.getCode());
    try testing.expectEqual(@as(usize, 64), hash.getSize());

    var hash1 = std.crypto.hash.sha3.Sha3_512.init(.{});
    hash1.update(input);
    var out = [_]u8{0} ** 64;
    hash1.final(&out);
    try testing.expectEqualSlices(u8, &out, hash.getDigest());
}

test "keccak_224 hash operations" {
    const input = "hello world";
    const hash = try MultihashCodecs.KECCAK_224.digest(input);
    try testing.expectEqual(@as(u64, 0x1a), hash.code.getCode());
    try testing.expectEqual(@as(usize, 28), hash.getSize());

    var hash1 = std.crypto.hash.sha3.Keccak(1600, 224, 0x01, 24).init(.{});
    hash1.update(input);
    var out = [_]u8{0} ** 28;
    hash1.final(&out);
    try testing.expectEqualSlices(u8, &out, hash.getDigest());
}

test "keccak_256 hash operations" {
    const input = "hello world";
    const hash = try MultihashCodecs.KECCAK_256.digest(input);
    try testing.expectEqual(@as(u64, 0x1b), hash.code.getCode());
    try testing.expectEqual(@as(usize, 32), hash.getSize());

    var hash1 = std.crypto.hash.sha3.Keccak256.init(.{});
    hash1.update(input);
    var out = [_]u8{0} ** 32;
    hash1.final(&out);
    try testing.expectEqualSlices(u8, &out, hash.getDigest());
}

test "keccak_384 hash operations" {
    const input = "hello world";
    const hash = try MultihashCodecs.KECCAK_384.digest(input);
    try testing.expectEqual(@as(u64, 0x1c), hash.code.getCode());
    try testing.expectEqual(@as(usize, 48), hash.getSize());

    var hash1 = std.crypto.hash.sha3.Keccak(1600, 384, 0x01, 24).init(.{});
    hash1.update(input);
    var out = [_]u8{0} ** 48;
    hash1.final(&out);
    try testing.expectEqualSlices(u8, &out, hash.getDigest());
}

test "keccak_512 hash operations" {
    const input = "hello world";
    const hash = try MultihashCodecs.KECCAK_512.digest(input);
    try testing.expectEqual(@as(u64, 0x1d), hash.code.getCode());
    try testing.expectEqual(@as(usize, 64), hash.getSize());

    var hash1 = std.crypto.hash.sha3.Keccak512.init(.{});
    hash1.update(input);
    var out = [_]u8{0} ** 64;
    hash1.final(&out);
    try testing.expectEqualSlices(u8, &out, hash.getDigest());
}

test "blake2b_256 hash operations" {
    const input = "hello world";
    const hash = try MultihashCodecs.BLAKE2B_256.digest(input);
    try testing.expectEqual(@as(u64, 0xb220), hash.code.getCode());
    try testing.expectEqual(@as(usize, 32), hash.getSize());

    var hash1 = std.crypto.hash.blake2.Blake2b256.init(.{});
    hash1.update(input);
    var out = [_]u8{0} ** 32;
    hash1.final(&out);
    try testing.expectEqualSlices(u8, &out, hash.getDigest());
}

test "blake2b_512 hash operations" {
    const input = "hello world";
    const hash = try MultihashCodecs.BLAKE2B_512.digest(input);
    try testing.expectEqual(@as(u64, 0xb240), hash.code.getCode());
    try testing.expectEqual(@as(usize, 64), hash.getSize());

    var hash1 = std.crypto.hash.blake2.Blake2b512.init(.{});
    hash1.update(input);
    var out = [_]u8{0} ** 64;
    hash1.final(&out);
    try testing.expectEqualSlices(u8, &out, hash.getDigest());
}

test "blake2s_128 hash operations" {
    const input = "hello world";
    const hash = try MultihashCodecs.BLAKE2S_128.digest(input);
    try testing.expectEqual(@as(u64, 0xb250), hash.code.getCode());
    try testing.expectEqual(@as(usize, 16), hash.getSize());

    var hash1 = std.crypto.hash.blake2.Blake2s128.init(.{});
    hash1.update(input);
    var out = [_]u8{0} ** 16;
    hash1.final(&out);
    try testing.expectEqualSlices(u8, &out, hash.getDigest());
}

test "blake2s_256 hash operations" {
    const input = "hello world";
    const hash = try MultihashCodecs.BLAKE2S_256.digest(input);
    try testing.expectEqual(@as(u64, 0xb260), hash.code.getCode());
    try testing.expectEqual(@as(usize, 32), hash.getSize());

    var hash1 = std.crypto.hash.blake2.Blake2s256.init(.{});
    hash1.update(input);
    var out = [_]u8{0} ** 32;
    hash1.final(&out);
    try testing.expectEqualSlices(u8, &out, hash.getDigest());
}

test "blake3 hash operations" {
    const input = "hello world";
    const hash = try MultihashCodecs.BLAKE3.digest(input);
    try testing.expectEqual(@as(u64, 0x1e), hash.code.getCode());
    try testing.expectEqual(@as(usize, 64), hash.getSize());

    var hash1 = std.crypto.hash.Blake3.init(.{});
    hash1.update(input);
    var out = [_]u8{0} ** 64;
    hash1.final(&out);
    try testing.expectEqualSlices(u8, &out, hash.getDigest());
}

test "multihash readBytes" {
    const input = [_]u8{ 0x12, 0x0a, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    var mh = try Multihash(32).readBytes(&input);

    try testing.expectEqual(mh.getCode().getCode(), 0x12);
    try testing.expectEqual(mh.getSize(), 10);
    try testing.expectEqualSlices(u8, mh.getDigest(), input[2..]);
}

test "multihash toBytes" {
    const expected_bytes = [_]u8{ 0x12, 0x0a, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    var mh = try Multihash(32).wrap(Multicodec.SHA2_256, &[_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 });

    var buf: [100]u8 = undefined;
    const bytes = try mh.toBytes(buf[0..]);
    try testing.expectEqualSlices(u8, bytes, &expected_bytes);
}

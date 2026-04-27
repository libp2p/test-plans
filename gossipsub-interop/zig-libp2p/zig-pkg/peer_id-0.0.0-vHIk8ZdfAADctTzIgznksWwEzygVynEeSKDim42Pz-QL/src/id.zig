const std = @import("std");
const Allocator = std.mem.Allocator;
const multiformats = @import("multiformats");
const multihash = multiformats.multihash;
const Multihash = multihash.Multihash;
const Multicodec = multiformats.multicodec.Multicodec;
const multibase = multiformats.multibase;
const cid = multiformats.cid;
const CID = cid.CID;
const keys = @import("keys.proto.zig");

/// Maximum length for inline keys that use identity multihash
const MAX_INLINE_KEY_LENGTH: usize = 42;

/// Multihash codes for PeerID
const MULTIHASH_IDENTITY_CODE = Multicodec.IDENTITY;
const MULTIHASH_SHA256_CODE = Multicodec.SHA2_256;

/// Errors that can occur when parsing a PeerId
pub const ParseError = error{
    /// Base58 decoding error
    Base58DecodeError,
    /// Unsupported multihash code
    UnsupportedCode,
    /// Invalid multihash format
    InvalidMultihash,
    /// Input too short
    InputTooShort,
    /// Invalid character in base58 string
    InvalidChar,
    /// Invalid CID type for PeerId
    InvalidCidType,
};

/// Identifier of a peer in the network
///
/// The data is a CIDv0 compatible multihash of the protobuf encoded public key
/// as specified in libp2p specs
/// https://github.com/libp2p/specs/blob/0caf71bb29a525ab0ef14ea4511d68e873d4a2d9/peer-ids/peer-ids.md#peer-ids
pub const PeerId = struct {
    /// The underlying multihash (64 bytes to accommodate 512-bit hashes)
    multihash: Multihash(64),

    const Self = @This();

    /// Creates a PeerId from a public key
    /// For keys <= 42 bytes, uses identity multihash
    /// For larger keys, uses SHA2-256 hash
    pub fn fromPublicKey(allocator: Allocator, public_key: *keys.PublicKey) !Self {
        var protobuf_public_key = try public_key.encode(allocator);
        defer allocator.free(protobuf_public_key);

        if (public_key.type == .RSA) {
            // RSA is the default key type (0) so the encoder omits it. Append the tag/value to
            // match other implementations when hashing protobuf-encoded keys.
            const augmented = blk: {
                const type_field = [_]u8{ 0x08, 0x00 };
                const original = protobuf_public_key;
                defer allocator.free(original);
                break :blk try std.mem.concat(allocator, u8, &.{ &type_field, original });
            };
            protobuf_public_key = augmented;
        }

        if (protobuf_public_key.len <= MAX_INLINE_KEY_LENGTH) {
            // Use identity multihash for small keys
            const mh = try Multihash(64).wrap(MULTIHASH_IDENTITY_CODE, protobuf_public_key);
            return Self{ .multihash = mh };
        } else {
            // Use SHA2-256 for larger keys
            var sha2_256 = multihash.Sha2_256.init();
            try sha2_256.update(protobuf_public_key);
            const hash = sha2_256.finalize();
            const mh = try Multihash(64).wrap(MULTIHASH_SHA256_CODE, &hash);
            return Self{ .multihash = mh };
        }
    }

    /// Parses a PeerId from bytes
    pub fn fromBytes(bytes: []const u8) !Self {
        const mh = try Multihash(64).readBytes(bytes);
        return Self.fromMultihash(mh);
    }

    /// Creates a PeerId from a multihash
    /// Validates that the multihash uses a supported algorithm
    pub fn fromMultihash(multi_hash: Multihash(64)) !Self {
        switch (multi_hash.getCode()) {
            MULTIHASH_SHA256_CODE => {},
            MULTIHASH_IDENTITY_CODE => {
                if (multi_hash.getSize() > MAX_INLINE_KEY_LENGTH) {
                    return ParseError.UnsupportedCode;
                }
            },
            else => return ParseError.UnsupportedCode,
        }
        return Self{ .multihash = multi_hash };
    }

    /// Converts a CID to a peer ID, if possible
    /// The CID must have codec type Libp2pKey to be valid for peer ID conversion
    pub fn fromCid(c: CID(64)) !Self {
        if (c.getCodec() != Multicodec.LIBP2P_KEY) {
            return ParseError.InvalidCidType;
        }

        return try Self.fromMultihash(c.hash);
    }

    /// Generates a random PeerID for testing or DHT walking
    pub fn random() !Self {
        var peer_id_bytes: [32]u8 = undefined;
        std.crypto.random.bytes(&peer_id_bytes);

        const mh = try Multihash(64).wrap(MULTIHASH_IDENTITY_CODE, &peer_id_bytes);
        return Self{ .multihash = mh };
    }

    pub fn toBytesLen(self: *const Self) usize {
        return self.multihash.encodedLen();
    }

    /// Returns the raw bytes representation of this PeerId
    pub fn toBytes(self: *const Self, dest: []u8) ![]const u8 {
        return try self.multihash.toBytes(dest);
    }

    pub fn toBase58Len(self: *const Self) usize {
        return multibase.MultiBaseCodec.Base58Btc.encodedLenBySize(self.toBytesLen());
    }

    /// Returns a base58-encoded string of this PeerId
    pub fn toBase58(self: *const Self, dest: []u8) ![]const u8 {
        var bytes_buffer: [128]u8 = undefined; // Sufficient for a 64-byte digest multihash
        const source_bytes = try self.toBytes(&bytes_buffer);
        return multibase.MultiBaseCodec.Base58Impl.encodeBtc(dest, source_bytes);
    }

    /// Encodes a peer ID as a CID of the public key.
    /// Returns a CIDv1 with Libp2pKey codec and the peer ID's multihash.
    /// If the peer ID is invalid, this will return an error
    pub fn toCid(self: *const Self) !CID(64) {
        // Create a CIDv1 with Libp2pKey codec and the peer ID's multihash
        return try CID(64).newV1(Multicodec.LIBP2P_KEY, self.multihash);
    }

    /// Parses a PeerId from a base58-encoded string
    pub fn fromBase58(allocator: Allocator, s: []const u8) !Self {
        const decoded_len = multibase.MultiBaseCodec.Base58Btc.decodedLen(s);
        const decoded_bytes = try allocator.alloc(u8, decoded_len);
        defer allocator.free(decoded_bytes);

        const actual_decoded = try multibase.MultiBaseCodec.Base58Impl.decodeBtc(decoded_bytes, s);

        return try Self.fromBytes(actual_decoded);
    }

    /// Checks if two PeerIds are equal
    pub fn eql(self: *const Self, other: *const Self) bool {
        return std.mem.eql(u8, self.multihash.getDigest(), other.multihash.getDigest()) and
            self.multihash.getCode() == other.multihash.getCode() and
            self.multihash.getSize() == other.multihash.getSize();
    }

    /// Returns the underlying multihash
    pub fn getMultihash(self: *const Self) *const Multihash(64) {
        return &self.multihash;
    }

    pub fn fromString(allocator: Allocator, s: []const u8) !Self {
        // Check if it's a bare base58btc encoded multihash
        if (std.mem.startsWith(u8, s, "Qm") or std.mem.startsWith(u8, s, "1")) {
            return try Self.fromBase58(allocator, s);
        }

        const decoded_cid = try cid.decodedCID(s);
        const dest = try allocator.alloc(u8, decoded_cid.dest_len);
        defer allocator.free(dest);
        const actual_cid = try decoded_cid.toCID(64, dest);
        return try Self.fromCid(actual_cid);
    }
};

test "PeerId bytes round trip" {
    const testing = std.testing;

    const original_peer_id = try PeerId.random();

    var bytes_buffer: [64]u8 = undefined;
    const bytes = try original_peer_id.toBytes(&bytes_buffer);

    const reconstructed_peer_id = try PeerId.fromBytes(bytes);

    try testing.expect(original_peer_id.eql(&reconstructed_peer_id));
}

test "PeerId base58 string round trip" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const original_peer_id = try PeerId.random();

    const original_peer_id_base58_len = original_peer_id.toBase58Len();
    const base58_str_buffer = try allocator.alloc(u8, original_peer_id_base58_len);
    defer allocator.free(base58_str_buffer);
    const actual_base58_str = try original_peer_id.toBase58(base58_str_buffer);

    const reconstructed_peer_id = try PeerId.fromBase58(allocator, actual_base58_str);

    try testing.expect(original_peer_id.eql(&reconstructed_peer_id));
}

test "PeerId CID conversion round trip" {
    const testing = std.testing;

    const original_peer_id = try PeerId.random();

    const cid_from_peer = try original_peer_id.toCid();

    try testing.expectEqual(.V1, cid_from_peer.getVersion());
    try testing.expectEqual(Multicodec.LIBP2P_KEY, cid_from_peer.getCodec());

    const peer_from_cid = try PeerId.fromCid(cid_from_peer);

    try testing.expect(original_peer_id.eql(&peer_from_cid));
}

test "PeerId fromCid with invalid codec" {
    const testing = std.testing;

    const hash = try Multihash(64).wrap(MULTIHASH_SHA256_CODE, &[_]u8{0} ** 32);
    const invalid_cid = try CID(64).newV1(Multicodec.RAW, hash);

    try testing.expectError(ParseError.InvalidCidType, PeerId.fromCid(invalid_cid));
}

test "PeerId fromMultihash with unsupported code" {
    const testing = std.testing;

    const unsupported_hash = try Multihash(64).wrap(Multicodec.BLAKE2B_256, &[_]u8{0} ** 32);

    try testing.expectError(ParseError.UnsupportedCode, PeerId.fromMultihash(unsupported_hash));
}

test "PeerId fromMultihash with oversized identity hash" {
    const testing = std.testing;

    const large_data = [_]u8{0x42} ** 50;

    const oversized_identity_hash = try Multihash(64).wrap(MULTIHASH_IDENTITY_CODE, &large_data);

    try testing.expectError(ParseError.UnsupportedCode, PeerId.fromMultihash(oversized_identity_hash));
}

test "PeerId equality" {
    const testing = std.testing;

    const data = [_]u8{ 0x12, 0x34, 0x56, 0x78 };
    const hash1 = try Multihash(64).wrap(MULTIHASH_IDENTITY_CODE, &data);
    const hash2 = try Multihash(64).wrap(MULTIHASH_IDENTITY_CODE, &data);

    const peer1 = try PeerId.fromMultihash(hash1);
    const peer2 = try PeerId.fromMultihash(hash2);

    try testing.expect(peer1.eql(&peer2));

    const different_data = [_]u8{ 0x87, 0x65, 0x43, 0x21 };
    const hash3 = try Multihash(64).wrap(MULTIHASH_IDENTITY_CODE, &different_data);
    const peer3 = try PeerId.fromMultihash(hash3);

    try testing.expect(!peer1.eql(&peer3));
}

// test "PeerId from public key to CID complete flow" {
//     const testing = std.testing;
//     const ssl = @import("ssl");
//     const allocator = testing.allocator;

//     const pctx = ssl.EVP_PKEY_CTX_new_id(ssl.EVP_PKEY_ED25519, null) orelse return error.OpenSSLFailed;
//     defer ssl.EVP_PKEY_CTX_free(pctx);

//     if (ssl.EVP_PKEY_keygen_init(pctx) == 0) {
//         return error.OpenSSLFailed;
//     }

//     var maybe_key: ?*ssl.EVP_PKEY = null;
//     if (ssl.EVP_PKEY_keygen(pctx, &maybe_key) == 0) {
//         return error.OpenSSLFailed;
//     }
//     const key = maybe_key orelse return error.OpenSSLFailed;
//     defer ssl.EVP_PKEY_free(key);

//     var len: usize = 0;
//     if (ssl.EVP_PKEY_get_raw_public_key(key, null, &len) == 0) return error.RawPubKeyGetFailed;
//     const buf = try allocator.alloc(u8, len);
//     defer allocator.free(buf);
//     if (ssl.EVP_PKEY_get_raw_public_key(key, buf.ptr, &len) == 0) {
//         allocator.free(buf);
//         return error.RawPubKeyGetFailed;
//     }

//     var public_key = peerid.PublicKey{
//         .type = .ED25519,
//         .data = buf,
//     };

//     const peer_id = try PeerId.fromPublicKey(allocator, &public_key);

//     try testing.expectEqual(MULTIHASH_IDENTITY_CODE, peer_id.multihash.getCode());

//     const peer_cid = try peer_id.toCid();

//     const recovered_peer_id = try PeerId.fromCid(peer_cid);

//     try testing.expect(peer_id.eql(&recovered_peer_id));
// }

test "PeerId random generation" {
    const testing = std.testing;

    const peer1 = try PeerId.random();
    const peer2 = try PeerId.random();

    try testing.expect(!peer1.eql(&peer2));

    try testing.expectEqual(MULTIHASH_IDENTITY_CODE, peer1.multihash.getCode());
    try testing.expectEqual(MULTIHASH_IDENTITY_CODE, peer2.multihash.getCode());
}

test "PeerId getMultihash" {
    const testing = std.testing;

    const peer_id = try PeerId.random();

    const mh = peer_id.getMultihash();

    try testing.expectEqual(MULTIHASH_IDENTITY_CODE, mh.getCode());

    const peer_from_mh = try PeerId.fromMultihash(mh.*);
    try testing.expect(peer_id.eql(&peer_from_mh));
}

// Test vector in the peer-id spec
// https://github.com/libp2p/specs/blob/0caf71bb29a525ab0ef14ea4511d68e873d4a2d9/peer-ids/peer-ids.md#decoding
test "PeerId fromString with base58" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const str1 = "bafzbeie5745rpv2m6tjyuugywy4d5ewrqgqqhfnf445he3omzpjbx5xqxe";
    const peerId1 = try PeerId.fromString(allocator, str1);
    try testing.expectEqual(MULTIHASH_SHA256_CODE, peerId1.multihash.getCode());
    const str2 = "QmYyQSo1c1Ym7orWxLYvCrM2EmxFTANf8wXmmE7DWjhx5N";
    const peerId2 = try PeerId.fromString(allocator, str2);
    try testing.expectEqual(MULTIHASH_SHA256_CODE, peerId2.multihash.getCode());
    const str3 = "12D3KooWD3eckifWpRn9wQpMG9R9hX3sD158z7EqHWmweQAJU5SA";
    const peerId3 = try PeerId.fromString(allocator, str3);
    try testing.expectEqual(MULTIHASH_IDENTITY_CODE, peerId3.multihash.getCode());
}

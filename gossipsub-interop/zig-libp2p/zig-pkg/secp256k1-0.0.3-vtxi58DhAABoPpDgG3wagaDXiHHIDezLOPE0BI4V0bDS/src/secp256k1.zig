const std = @import("std");
const crypto = std.crypto;
const ecdsa_lib = @import("ecdsa/ecdsa.zig");
const recovery_lib = @import("ecdsa/recovery.zig");
const schnorr_lib = @import("schnorr.zig");

pub const constants = @import("constants.zig");

/// The main error type for this library.
pub const Error = error{
    /// Signature failed verification.
    IncorrectSignature,
    /// Bad sized message ("messages" are actually fixed-sized digests [`constants::MESSAGE_SIZE`]).
    InvalidMessage,
    /// Bad public key.
    InvalidPublicKey,
    /// Bad signature.
    InvalidSignature,
    /// Bad secret key.
    InvalidSecretKey,
    /// Bad shared secret.
    InvalidSharedSecret,
    /// Bad recovery id.
    InvalidRecoveryId,
    /// Tried to add/multiply by an invalid tweak.
    InvalidTweak,
    /// Didn't pass enough memory to context creation with preallocated memory.
    NotEnoughMemory,
    /// Bad set of public keys.
    InvalidPublicKeySum,
    /// The only valid parity values are 0 or 1.
    InvalidParityValue,
    /// Bad EllSwift value
    InvalidEllSwift,

    // allocator error
    OutOfMemory,
};

pub const ecdsa = struct {
    pub const Signature = ecdsa_lib.Signature;
    pub const SerializedSignature = ecdsa_lib.SerializedSignature;
    pub const RecoverableSignature = recovery_lib.RecoverableSignature;
    pub const RecoveryId = recovery_lib.RecoveryId;
};

pub const schnorr = struct {
    pub const Signature = schnorr_lib.Signature;
};

pub const secp256k1 = @cImport({
    @cInclude("secp256k1.h");
    @cInclude("secp256k1_recovery.h");
    @cInclude("secp256k1_preallocated.h");
    @cInclude("secp256k1_schnorrsig.h");
});

/// A (hashed) message input to an ECDSA signature.
pub const Message = struct {
    inner: [constants.message_size]u8,

    /// Creates a [`Message`] from a `digest`.
    ///
    /// The `digest` array has to be a cryptographically secure hash of the actual message that's
    /// going to be signed. Otherwise the result of signing isn't a [secure signature].
    ///
    /// [secure signature]: https://twitter.com/pwuille/status/1063582706288586752
    pub inline fn fromDigest(digest: [32]u8) Message {
        return .{ .inner = digest };
    }
};

pub const KeyPair = struct {
    inner: secp256k1.secp256k1_keypair,

    /// Creates a [`KeyPair`] directly from a Secp256k1 secret key.
    pub fn fromSecretKey(secp: *const Secp256k1, sk: *const SecretKey) Error!KeyPair {
        var kp = secp256k1.secp256k1_keypair{};

        if (secp256k1.secp256k1_keypair_create(secp.ctx, &kp, &sk.data) != 1) {
            @panic("the provided secret key is invalid: it is corrupted or was not produced by Secp256k1 library");
        }

        return .{ .inner = kp };
    }

    /// Creates a [`KeyPair`] directly from a secret key string.
    ///
    /// # Errors
    ///
    /// [`error.InvalidSecretKey`] if corresponding public key for the provided secret key is not even.
    pub fn fromSeckeyStr(secp: *const Secp256k1, s: []const u8) Error!KeyPair {
        if (s.len / 2 > constants.secret_key_size) return Error.InvalidSecretKey;
        var res = [_]u8{0} ** constants.secret_key_size;

        return try fromSeckeySlice(secp, std.fmt.hexToBytes(&res, s) catch return Error.InvalidSecretKey);
    }

    pub fn fromSeckeySlice(
        secp: *const Secp256k1,
        data: []const u8,
    ) Error!KeyPair {
        if (data.len == 0 or data.len != constants.secret_key_size) {
            return Error.InvalidSecretKey;
        }

        var kp = secp256k1.secp256k1_keypair{};
        if (secp256k1.secp256k1_keypair_create(secp.ctx, &kp, data.ptr) == 1) {
            return .{
                .inner = kp,
            };
        } else {
            return Error.InvalidSecretKey;
        }
    }
};

pub const XOnlyPublicKey = struct {
    inner: secp256k1.secp256k1_xonly_pubkey,

    /// Creates a schnorr public key directly from a slice.
    ///
    /// # Errors
    ///
    /// Returns [`Error::InvalidPublicKey`] if the length of the data slice is not 32 bytes or the
    /// slice does not represent a valid Secp256k1 point x coordinate.
    pub inline fn fromSlice(data: []const u8) Error!XOnlyPublicKey {
        if (data.len == 0 or data.len != 32) {
            return Error.InvalidPublicKey;
        }

        var pk: secp256k1.secp256k1_xonly_pubkey = undefined;

        if (secp256k1.secp256k1_xonly_pubkey_parse(
            secp256k1.secp256k1_context_no_precomp,
            &pk,
            data.ptr,
        ) == 1) {
            return .{ .inner = pk };
        }

        return Error.InvalidPublicKey;
    }

    /// Serializes the key as a byte-encoded x coordinate value (32 bytes).
    pub inline fn serialize(self: XOnlyPublicKey) [32]u8 {
        var ret: [32]u8 = undefined;

        const err = secp256k1.secp256k1_xonly_pubkey_serialize(
            secp256k1.secp256k1_context_no_precomp,
            &ret,
            &self.inner,
        );
        std.debug.assert(err == 1);
        return ret;
    }

    /// Creates a [`PublicKey`] using the key material from `pk` combined with the `parity`.
    pub fn publicKey(pk: XOnlyPublicKey, parity: enum {
        even,
        odd,
    }) PublicKey {
        var buf: [33]u8 = undefined;

        // First byte of a compressed key should be `0x02 AND parity`.
        buf[0] = switch (parity) {
            .even => 0x02,
            .odd => 0x03,
        };

        buf[1..33].* = pk.serialize();

        return PublicKey.fromSlice(&buf) catch @panic("buffer is valid");
    }
};

pub const Secp256k1 = struct {
    ctx: ?*secp256k1.struct_secp256k1_context_struct,

    pub fn deinit(self: @This()) void {
        secp256k1.secp256k1_context_destroy(self.ctx);
    }

    // Re-exported from ecdsa_lib.Secp
    pub const signEcdsa = ecdsa_lib.Secp.signEcdsa;
    pub const signEcdsaWithNoncedata = ecdsa_lib.Secp.signEcdsaWithNoncedata;
    pub const signEcdsaGrindR = ecdsa_lib.Secp.signEcdsaGrindR;
    pub const signEcdsaLowR = ecdsa_lib.Secp.signEcdsaLowR;
    pub const verifyEcdsa = ecdsa_lib.Secp.verifyEcdsa;

    // Re-exported from schnorr_lib.Secp
    pub const signSchnorrWithAuxRand = schnorr_lib.Secp.signSchnorrWithAuxRand;
    pub const verifySchnorr = schnorr_lib.Secp.verifySchnorr;
    pub const signSchnorrHelper = schnorr_lib.Secp.signSchnorrHelper;

    // Re-exported from recovery_lib.Secp
    pub const signEcdsaRecoverable = recovery_lib.Secp.signEcdsaRecoverable;
    pub const signEcdsaRecoverableWithNoncedata = recovery_lib.Secp.signEcdsaRecoverableWithNoncedata;
    pub const recoverEcdsa = recovery_lib.Secp.recoverEcdsa;

    /// Creating new [`Secp256k1`] object, after all u need to call DEINIT
    pub fn genNew() @This() {
        const ctx =
            secp256k1.secp256k1_context_create(257 | 513);

        // Create 32 byte random seed.
        var seed: [32]u8 = undefined;
        crypto.random.bytes(&seed);

        const res = secp256k1.secp256k1_context_randomize(ctx, &seed);
        std.debug.assert(res == 1);

        return .{
            .ctx = ctx,
        };
    }

    /// (Re)randomizes the Secp256k1 context for extra sidechannel resistance given 32 bytes of
    /// cryptographically-secure random data;
    /// see comment in libsecp256k1 commit d2275795f by Gregory Maxwell.
    pub fn seededRandomize(self: *const Secp256k1, seed: [32]u8) void {
        const err = secp256k1.secp256k1_context_randomize(self.ctx, &seed);
        // This function cannot fail; it has an error return for future-proofing.
        // We do not expose this error since it is impossible to hit, and we have
        // precedent for not exposing impossible errors (for example in
        // `PublicKey::from_secret_key` where it is impossible to create an invalid
        // secret key through the API.)
        // However, if this DOES fail, the result is potentially weaker side-channel
        // resistance, which is deadly and undetectable, so we take out the entire
        // thread to be on the safe side.
        std.debug.assert(err == 1);
    }

    /// Generates a random keypair. Convenience function for [`SecretKey::new`] and
    /// [`PublicKey.fromSecretKey`].
    pub inline fn generateKeypair(
        self: Secp256k1,
        rng: std.Random,
    ) struct { SecretKey, PublicKey } {
        const sk = SecretKey.generateWithRandom(rng);
        const pk = PublicKey.fromSecretKey(self, sk);
        return .{ sk, pk };
    }
};

pub const Scalar = struct {
    data: [32]u8,

    pub inline fn fromSecretKey(sk: SecretKey) @This() {
        return .{ .data = sk.secretBytes() };
    }
};

pub const ErrorParseHex = error{
    InvalidLength,
    NoSpaceLeft,
    InvalidCharacter,
};

pub const PublicKey = struct {
    pk: secp256k1.secp256k1_pubkey,

    pub fn eql(self: PublicKey, other: PublicKey) bool {
        return std.mem.eql(u8, &self.pk.data, &other.pk.data);
    }

    // json serializing func
    pub fn jsonStringify(self: PublicKey, out: anytype) !void {
        try out.write(std.fmt.bytesToHex(&self.serialize(), .lower));
    }

    pub fn jsonParse(_: std.mem.Allocator, source: anytype, _: std.json.ParseOptions) !@This() {
        switch (try source.next()) {
            .string => |s| {
                var hex_buffer: [60]u8 = undefined;

                const hex = std.fmt.hexToBytes(&hex_buffer, s) catch return error.UnexpectedToken;

                return PublicKey.fromSlice(hex) catch error.UnexpectedToken;
            },
            else => return error.UnexpectedToken,
        }
    }

    /// Returns the [`XOnlyPublicKey`] (and it's [`Parity`]) for this [`PublicKey`].
    pub inline fn xOnlyPublicKey(self: *const PublicKey) struct { XOnlyPublicKey, enum { even, odd } } {
        var pk_parity: i32 = 0;
        var xonly_pk = secp256k1.secp256k1_xonly_pubkey{};
        const ret = secp256k1.secp256k1_xonly_pubkey_from_pubkey(
            secp256k1.secp256k1_context_no_precomp,
            &xonly_pk,
            &pk_parity,
            &self.pk,
        );

        std.debug.assert(ret == 1);

        return .{
            .{ .inner = xonly_pk },
            if (pk_parity & 1 == 0) .even else .odd,
        };
    }

    /// Verify schnorr signature
    pub fn verify(self: *const PublicKey, secp: *Secp256k1, msg: []const u8, sig: schnorr_lib.Signature) !void {
        var hasher = crypto.hash.sha2.Sha256.init(.{});
        hasher.update(msg);

        const hash = hasher.finalResult();

        try secp.verifySchnorr(sig, hash, self.xOnlyPublicKey()[0]);
    }

    /// [`PublicKey`] from hex string
    pub fn fromString(s: []const u8) (ErrorParseHex || Error)!@This() {
        var buf: [100]u8 = undefined;
        const decoded = try std.fmt.hexToBytes(&buf, s);

        return try PublicKey.fromSlice(decoded);
    }

    /// [`PublicKey`] from bytes slice
    pub fn fromSlice(c: []const u8) Error!@This() {
        var pk: secp256k1.secp256k1_pubkey = .{};

        if (secp256k1.secp256k1_ec_pubkey_parse(secp256k1.secp256k1_context_no_precomp, &pk, c.ptr, c.len) == 1) {
            return .{ .pk = pk };
        }
        return Error.InvalidPublicKey;
    }

    pub fn fromSecretKey(secp_: Secp256k1, sk: SecretKey) PublicKey {
        var pk: secp256k1.secp256k1_pubkey = .{};

        const res = secp256k1.secp256k1_ec_pubkey_create(secp_.ctx, &pk, &sk.data);

        std.debug.assert(res == 1);

        return PublicKey{ .pk = pk };
    }

    /// Serializes the key as a byte-encoded pair of values. In compressed form the y-coordinate is
    /// represented by only a single bit, as x determines it up to one bit.
    pub fn serialize(self: PublicKey) [33]u8 {
        var ret = [_]u8{0} ** 33;
        self.serializeInternal(&ret, 258);

        return ret;
    }

    /// Serializes the key as a byte-encoded pair of values, in uncompressed form.
    pub inline fn serializeUncompressed(self: PublicKey) [65]u8 {
        var ret = [_]u8{0} ** 65;

        self.serializeInternal(&ret, 2);
        return ret;
    }

    inline fn serializeInternal(self: PublicKey, ret: []u8, flag: u32) void {
        var ret_len = ret.len;

        const res = secp256k1.secp256k1_ec_pubkey_serialize(secp256k1.secp256k1_context_no_precomp, ret.ptr, &ret_len, &self.pk, flag);

        std.debug.assert(res == 1);
        std.debug.assert(ret_len == ret.len);
    }

    pub fn negate(self: @This(), secp: *const Secp256k1) PublicKey {
        var pk = self.pk;
        const res = secp256k1.secp256k1_ec_pubkey_negate(secp.ctx, &pk);

        std.debug.assert(res == 1);

        return .{ .pk = pk };
    }

    pub fn mulTweak(self: @This(), secp: *const Secp256k1, other: Scalar) !PublicKey {
        var pk = self.pk;
        if (secp256k1.secp256k1_ec_pubkey_tweak_mul(secp.ctx, &pk, @ptrCast(&other.data)) == 1) return .{ .pk = pk };

        return error.InvalidTweak;
    }

    /// Tweaks a [`PublicKey`] by adding `tweak * G` modulo the curve order.
    ///
    /// # Errors
    ///
    /// Returns an error if the resulting key would be invalid.
    pub inline fn addExpTweak(
        self: *const PublicKey,
        secp: Secp256k1,
        tweak: Scalar,
    ) Error!PublicKey {
        var s = self.*;
        if (secp256k1.secp256k1_ec_pubkey_tweak_add(secp.ctx, &s.pk, &tweak.data) == 1) {
            return s;
        } else {
            return Error.InvalidTweak;
        }
    }

    /// Adds public key `self` to public key `other`.
    ///
    /// # Errors
    ///
    /// Returns [`InvalidPublicKeySum`] if sum of public keys not valid.
    pub fn combine(self: @This(), other: PublicKey) Error!PublicKey {
        return try PublicKey.combineKeys(&.{
            &self, &other,
        });
    }

    pub fn combineKeys(keys: []const *const PublicKey) Error!PublicKey {
        if (keys.len == 0) return error.InvalidPublicKeySum;

        var ret = PublicKey{
            .pk = .{},
        };

        if (secp256k1.secp256k1_ec_pubkey_combine(secp256k1.secp256k1_context_no_precomp, &ret.pk, @ptrCast(keys.ptr), keys.len) == 1) return ret;

        return Error.InvalidPublicKeySum;
    }

    pub fn toString(self: @This()) [33 * 2]u8 {
        return std.fmt.bytesToHex(&self.serialize(), .lower);
    }
};

pub const SecretKey = struct {
    data: [32]u8,

    /// Schnorr Signature on Message
    pub fn sign(self: *const SecretKey, msg: []const u8) !schnorr_lib.Signature {
        var hasher = crypto.hash.sha2.Sha256.init(.{});
        hasher.update(msg);

        const hash = hasher.finalResult();

        var secp = Secp256k1.genNew();
        defer secp.deinit();

        var aux: [32]u8 = undefined;
        std.crypto.random.bytes(&aux);

        return secp.signSchnorrHelper(&hash, try KeyPair.fromSecretKey(&secp, self), &aux);
    }

    /// Generate random [`SecretKey`] with default custom random engine
    pub fn generateWithRandom(rng: std.Random) SecretKey {
        var d: [32]u8 = undefined;

        while (true) {
            rng.bytes(&d);
            if (SecretKey.fromSlice(&d)) |sk| return sk else |_| continue;
        }
    }

    /// Generate random [`SecretKey`] with default random
    pub fn generate() SecretKey {
        return generateWithRandom(std.crypto.random);
    }

    pub fn fromString(data: []const u8) (Error || ErrorParseHex)!@This() {
        var buf: [100]u8 = undefined;

        return try SecretKey.fromSlice(try std.fmt.hexToBytes(&buf, data));
    }

    pub fn fromSlice(data: []const u8) Error!@This() {
        if (data.len != 32) {
            return Error.InvalidSecretKey;
        }

        if (secp256k1.secp256k1_ec_seckey_verify(
            secp256k1.secp256k1_context_no_precomp,
            @ptrCast(data.ptr),
        ) == 0) return Error.InvalidSecretKey;

        return .{
            .data = data[0..32].*,
        };
    }

    pub inline fn publicKey(self: @This(), secp: Secp256k1) PublicKey {
        return PublicKey.fromSecretKey(secp, self);
    }

    pub inline fn secretBytes(self: @This()) [32]u8 {
        return self.data;
    }

    pub fn toString(self: @This()) [32 * 2]u8 {
        return std.fmt.bytesToHex(&self.data, .lower);
    }

    /// Tweaks a [`SecretKey`] by multiplying by `tweak` modulo the curve order.
    ///
    /// # Errors
    ///
    /// Returns an error if the resulting key would be invalid.
    pub inline fn mulTweak(self: *const SecretKey, tweak: Scalar) Error!SecretKey {
        var s = self.*;
        if (secp256k1.secp256k1_ec_seckey_tweak_mul(
            secp256k1.secp256k1_context_no_precomp,
            &s.data,
            &tweak.data,
        ) != 1) {
            return Error.InvalidTweak;
        }

        return s;
    }

    /// Tweaks a [`SecretKey`] by adding `tweak` modulo the curve order.
    ///
    /// # Errors
    ///
    /// Returns an error if the resulting key would be invalid.
    pub inline fn addTweak(self: *const SecretKey, tweak: Scalar) Error!SecretKey {
        var s = self.*;
        if (secp256k1.secp256k1_ec_seckey_tweak_add(
            secp256k1.secp256k1_context_no_precomp,
            &s.data,
            &tweak.data,
        ) != 1) {
            return Error.InvalidTweak;
        } else {
            return s;
        }
    }

    pub fn jsonStringify(self: *const SecretKey, out: anytype) !void {
        try out.write(self.toString());
    }

    pub fn jsonParse(_: std.mem.Allocator, source: anytype, _: std.json.ParseOptions) !@This() {
        return switch (try source.next()) {
            .string, .allocated_string => |hex_sec| SecretKey.fromString(hex_sec) catch return error.UnexpectedToken,
            else => return error.UnexpectedToken,
        };
    }
};

test "PublicKey combine table test" {
    const secp = Secp256k1.genNew();
    defer secp.deinit();

    // Test vectors stolen from https://web.archive.org/web/20190724010836/https://chuckbatson.wordpress.com/2014/11/26/secp256k1-test-vectors/.
    const table: [19][]const u8 = .{
        // [2]G = G + G
        "04C6047F9441ED7D6D3045406E95C07CD85C778E4B8CEF3CA7ABAC09B95C709EE51AE168FEA63DC339A3C58419466CEAEEF7F632653266D0E1236431A950CFE52A",
        // [3]G = G + G + G
        "04f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9388f7b0f632de8140fe337e62a37f3566500a99934c2231b6cb9fd7584b8e672",
        // ...
        "04e493dbf1c10d80f3581e4904930b1404cc6c13900ee0758474fa94abe8c4cd1351ed993ea0d455b75642e2098ea51448d967ae33bfbdfe40cfe97bdc47739922",
        "042f8bde4d1a07209355b4a7250a5c5128e88b84bddc619ab7cba8d569b240efe4d8ac222636e5e3d6d4dba9dda6c9c426f788271bab0d6840dca87d3aa6ac62d6",
        "04fff97bd5755eeea420453a14355235d382f6472f8568a18b2f057a1460297556ae12777aacfbb620f3be96017f45c560de80f0f6518fe4a03c870c36b075f297",
        "045cbdf0646e5db4eaa398f365f2ea7a0e3d419b7e0330e39ce92bddedcac4f9bc6aebca40ba255960a3178d6d861a54dba813d0b813fde7b5a5082628087264da",
        "042f01e5e15cca351daff3843fb70f3c2f0a1bdd05e5af888a67784ef3e10a2a015c4da8a741539949293d082a132d13b4c2e213d6ba5b7617b5da2cb76cbde904",
        "04acd484e2f0c7f65309ad178a9f559abde09796974c57e714c35f110dfc27ccbecc338921b0a7d9fd64380971763b61e9add888a4375f8e0f05cc262ac64f9c37",
        "04a0434d9e47f3c86235477c7b1ae6ae5d3442d49b1943c2b752a68e2a47e247c7893aba425419bc27a3b6c7e693a24c696f794c2ed877a1593cbee53b037368d7",
        "04774ae7f858a9411e5ef4246b70c65aac5649980be5c17891bbec17895da008cbd984a032eb6b5e190243dd56d7b7b365372db1e2dff9d6a8301d74c9c953c61b",
        "04d01115d548e7561b15c38f004d734633687cf4419620095bc5b0f47070afe85aa9f34ffdc815e0d7a8b64537e17bd81579238c5dd9a86d526b051b13f4062327",
        "04f28773c2d975288bc7d1d205c3748651b075fbc6610e58cddeeddf8f19405aa80ab0902e8d880a89758212eb65cdaf473a1a06da521fa91f29b5cb52db03ed81",
        "04499fdf9e895e719cfd64e67f07d38e3226aa7b63678949e6e49b241a60e823e4cac2f6c4b54e855190f044e4a7b3d464464279c27a3f95bcc65f40d403a13f5b",
        "04d7924d4f7d43ea965a465ae3095ff41131e5946f3c85f79e44adbcf8e27e080e581e2872a86c72a683842ec228cc6defea40af2bd896d3a5c504dc9ff6a26b58",
        "04e60fce93b59e9ec53011aabc21c23e97b2a31369b87a5ae9c44ee89e2a6dec0af7e3507399e595929db99f34f57937101296891e44d23f0be1f32cce69616821",
        "04defdea4cdb677750a420fee807eacf21eb9898ae79b9768766e4faa04a2d4a344211ab0694635168e997b0ead2a93daeced1f4a04a95c0f6cfb199f69e56eb77",
        "045601570cb47f238d2b0286db4a990fa0f3ba28d1a319f5e7cf55c2a2444da7ccc136c1dc0cbeb930e9e298043589351d81d8e0bc736ae2a1f5192e5e8b061d58",
        "042b4ea0a797a443d293ef5cff444f4979f06acfebd7e86d277475656138385b6c85e89bc037945d93b343083b5a1c86131a01f60c50269763b570c854e5c09b7a",
        "044ce119c96e2fa357200b559b2f7dd5a5f02d5290aff74b03f3e471b273211c9712ba26dcb10ec1625da61fa10a844c676162948271d96967450288ee9233dc3a",
    };

    const generator = PublicKey.fromSecretKey(secp, try SecretKey.fromString("0000000000000000000000000000000000000000000000000000000000000001"));
    var pubkey = generator;

    for (table) |pubkeystr| {
        pubkey = try pubkey.combine(generator);

        const expected = try PublicKey.fromString(pubkeystr);
        try std.testing.expectEqualDeep(
            pubkey,
            expected,
        );
    }
}

test "Secret sign" {
    const sk = SecretKey.generate();
    _ = try sk.sign("test_data");
}

test "Schnorr sign" {
    const secp = Secp256k1.genNew();
    defer secp.deinit();

    const sk = try KeyPair.fromSeckeyStr(&secp, "688C77BC2D5AAFF5491CF309D4753B732135470D05B7B2CD21ADD0744FE97BEF");

    var buf: [200]u8 = undefined;

    const msg = try std.fmt.hexToBytes(&buf, "E48441762FB75010B2AA31A512B62B4148AA3FB08EB0765D76B252559064A614");

    const aux_rand = try std.fmt.hexToBytes(buf[100..], "02CCE08E913F22A36C5648D6405A2C7C50106E7AA2F1649E381C7F09D16B80AB");

    const expected_sig = try schnorr_lib.Signature.fromStr("6470FD1303DDA4FDA717B9837153C24A6EAB377183FC438F939E0ED2B620E9EE5077C4A8B8DCA28963D772A94F5F0DDF598E1C47C137F91933274C7C3EDADCE8");

    const sig = secp.signSchnorrWithAuxRand(msg[0..32].*, sk, aux_rand[0..32].*);

    try std.testing.expectEqualDeep(
        expected_sig,
        sig,
    );
}

test "ECDSA verify" {
    const secp = Secp256k1.genNew();
    defer secp.deinit();

    const privKey = try SecretKey.fromString("d7fbc57b49b696ceaad08400622a5e8cf3f422774e67f35d3cee366e04926f65");
    const pubKey = privKey.publicKey(secp);

    var buf: [32]u8 = undefined;

    // zig bitcoin
    const msg = try std.fmt.hexToBytes(&buf, "D95F5DB92F175E6489219D1B23B3EFBF0D353DED9224DCD4B9AF3F3CB983469B");

    const sig = secp.signEcdsa(&.{ .inner = msg[0..32].* }, &privKey);

    try secp.verifyEcdsa(.{ .inner = msg[0..32].* }, sig, pubKey);
}

//! Provides a signing function that allows recovering the public key from the
//! signature.
//!
const std = @import("std");
const secp = @import("../secp256k1.zig");
const secp256k1 = secp.secp256k1;
const constants = @import("../constants.zig");

const Error = secp.Error;
const Signature = secp.ecdsa.Signature;
const Message = secp.Message;
const SecretKey = secp.SecretKey;
const PublicKey = secp.PublicKey;

/// A tag used for recovering the public key from a compact signature.
pub const RecoveryId = struct {
    value: i32,

    /// Allows library users to create valid recovery IDs from i32.
    pub fn fromI32(id: i32) Error!RecoveryId {
        return switch (id) {
            0...3 => .{ .value = id },
            else => Error.InvalidRecoveryId,
        };
    }

    pub fn toI32(self: RecoveryId) i32 {
        return self.value;
    }
};

/// An ECDSA signature with a recovery ID for pubkey recovery.
pub const RecoverableSignature = struct {
    inner: secp256k1.secp256k1_ecdsa_recoverable_signature,

    /// Converts a compact-encoded byte slice to a signature. This
    /// representation is nonstandard and defined by the libsecp256k1 library.
    pub fn fromCompact(data: []const u8, recid: RecoveryId) Error!RecoverableSignature {
        if (data.len == 0) {
            return Error.InvalidSignature;
        }

        var ret = secp256k1.secp256k1_ecdsa_recoverable_signature{};

        if (data.len != 64) {
            return Error.InvalidSignature;
        } else if (secp256k1.secp256k1_ecdsa_recoverable_signature_parse_compact(
            secp256k1.secp256k1_context_no_precomp,
            &ret,
            data.ptr,
            recid.value,
        ) == 1) {
            return .{ .inner = ret };
        } else {
            return Error.InvalidSignature;
        }
    }

    /// Serializes the recoverable signature in compact format.
    pub fn serializeCompact(self: RecoverableSignature) struct { RecoveryId, [64]u8 } {
        var ret = [_]u8{0} ** 64;
        var recid: i32 = 0;

        const err = secp256k1.secp256k1_ecdsa_recoverable_signature_serialize_compact(secp256k1.secp256k1_context_no_precomp, &ret, &recid, &self.inner);
        std.debug.assert(err == 1);

        return .{ .{ .value = recid }, ret };
    }

    /// Converts a recoverable signature to a non-recoverable one (this is needed
    /// for verification).
    pub inline fn toStandard(self: *const RecoverableSignature) Signature {
        var ret = secp256k1.secp256k1_ecdsa_signature{};
        const err = secp256k1.secp256k1_ecdsa_recoverable_signature_convert(
            secp256k1.secp256k1_context_no_precomp,
            &ret,
            &self.inner,
        );
        std.debug.assert(err == 1);
        return .{
            .inner = ret,
        };
    }

    /// Determines the public key for which this [`Signature`] is valid for `msg`. Requires a
    /// verify-capable context.
    pub inline fn recover(self: *const RecoverableSignature, msg: *const Message) Error!PublicKey {
        var s = secp.Secp256k1.genNew();
        defer s.deinit();
        return Secp.recoverEcdsa(&s, msg, self);
        // .recover_ecdsa(msg, self)
    }
};

pub const Secp = struct {
    fn signEcdsaRecoverableWithNoncedataPointer(
        self: *const secp.Secp256k1,
        msg: *const Message,
        sk: *const SecretKey,
        noncedata_ptr: ?*const anyopaque,
    ) RecoverableSignature {
        var ret = secp256k1.secp256k1_ecdsa_recoverable_signature{};
        // We can assume the return value because it's not possible to construct
        // an invalid signature from a valid `Message` and `SecretKey`
        std.debug.assert(secp256k1.secp256k1_ecdsa_sign_recoverable(
            self.ctx,
            &ret,
            &msg.inner,
            &sk.data,
            secp256k1.secp256k1_nonce_function_rfc6979,
            noncedata_ptr,
        ) == 1);

        return .{
            .inner = ret,
        };
    }

    /// Constructs a signature for `msg` using the secret key `sk` and RFC6979 nonce
    /// Requires a signing-capable context.
    pub fn signEcdsaRecoverable(
        self: *const secp.Secp256k1,
        msg: *const Message,
        sk: *const SecretKey,
    ) RecoverableSignature {
        return signEcdsaRecoverableWithNoncedataPointer(self, msg, sk, null);
    }

    /// Constructs a signature for `msg` using the secret key `sk` and RFC6979 nonce
    /// and includes 32 bytes of noncedata in the nonce generation via inclusion in
    /// one of the hash operations during nonce generation. This is useful when multiple
    /// signatures are needed for the same Message and SecretKey while still using RFC6979.
    /// Requires a signing-capable context.
    pub fn signEcdsaRecoverableWithNoncedata(
        self: *const secp.Secp256k1,
        msg: *const Message,
        sk: *const SecretKey,
        noncedata: [32]u8,
    ) RecoverableSignature {
        const noncedata_ptr: ?*const anyopaque = &noncedata;

        return signEcdsaRecoverableWithNoncedataPointer(self, msg, sk, noncedata_ptr);
    }

    /// Determines the public key for which `sig` is a valid signature for
    /// `msg`. Requires a verify-capable context.
    pub fn recoverEcdsa(
        self: *const secp.Secp256k1,
        msg: *const Message,
        sig: *const RecoverableSignature,
    ) Error!PublicKey {
        var pk = secp256k1.secp256k1_pubkey{};
        if (secp256k1.secp256k1_ecdsa_recover(
            self.ctx,
            &pk,
            &sig.inner,
            &msg.inner,
        ) != 1) {
            return Error.InvalidSignature;
        }

        return .{ .pk = pk };
    }
};

test "capabilities" {
    const _secp = secp.Secp256k1.genNew();
    defer _secp.deinit();

    var msg: [32]u8 = undefined;

    std.crypto.random.bytes(&msg);

    const _msg = Message{
        .inner = msg,
    };

    // Try key generation
    const sk, const pk = _secp.generateKeypair(std.crypto.random);
    _ = pk; // autofix

    // Try signing
    const sigr = Secp.signEcdsaRecoverable(&_secp, &_msg, &sk);

    // Try pk recovery
    _ = try Secp.recoverEcdsa(&_secp, &_msg, &sigr);
}

test "sign" {
    var s = secp.Secp256k1.genNew();
    defer s.deinit();

    var seed: [32]u8 = undefined;
    std.crypto.random.bytes(&seed);

    s.seededRandomize(seed);

    const sk = try secp.SecretKey.fromSlice(&constants.one);
    const msg = secp.Message{
        .inner = constants.one,
    };

    const sig = s.signEcdsaRecoverable(&msg, &sk);

    try std.testing.expectEqualDeep(
        try RecoverableSignature.fromCompact(
            &.{ 0x66, 0x73, 0xff, 0xad, 0x21, 0x47, 0x74, 0x1f, 0x04, 0x77, 0x2b, 0x6f, 0x92, 0x1f, 0x0b, 0xa6, 0xaf, 0x0c, 0x1e, 0x77, 0xfc, 0x43, 0x9e, 0x65, 0xc3, 0x6d, 0xed, 0xf4, 0x09, 0x2e, 0x88, 0x98, 0x4c, 0x1a, 0x97, 0x16, 0x52, 0xe0, 0xad, 0xa8, 0x80, 0x12, 0x0e, 0xf8, 0x02, 0x5e, 0x70, 0x9f, 0xff, 0x20, 0x80, 0xc4, 0xa3, 0x9a, 0xae, 0x06, 0x8d, 0x12, 0xee, 0xd0, 0x09, 0xb6, 0x8c, 0x89 },
            .{ .value = 1 },
        ),
        sig,
    );
}

test "sign with nonce data" {
    var s = secp.Secp256k1.genNew();
    defer s.deinit();

    var seed: [32]u8 = undefined;
    std.crypto.random.bytes(&seed);

    s.seededRandomize(seed);

    const sk = try secp.SecretKey.fromSlice(&constants.one);
    const msg = secp.Message{
        .inner = constants.one,
    };

    const noncedata = [_]u8{42} ** 32;

    const sig = s.signEcdsaRecoverableWithNoncedata(&msg, &sk, noncedata);

    try std.testing.expectEqualDeep(
        try RecoverableSignature.fromCompact(
            &.{ 0xb5, 0x0b, 0xb6, 0x79, 0x5f, 0x31, 0x74, 0x8a, 0x4d, 0x37, 0xc3, 0xa9, 0x7e, 0xbd, 0x06, 0xa2, 0x2e, 0xa3, 0x37, 0x71, 0x04, 0x0f, 0x5c, 0x05, 0xd6, 0xe2, 0xbb, 0x2d, 0x38, 0xc6, 0x22, 0x7c, 0x34, 0x3b, 0x66, 0x59, 0xdb, 0x96, 0x99, 0x59, 0xd9, 0xfd, 0xdb, 0x44, 0xbd, 0x0d, 0xd9, 0xb9, 0xdd, 0x47, 0x66, 0x6a, 0xb5, 0x28, 0x71, 0x90, 0x1d, 0x17, 0x61, 0xeb, 0x82, 0xec, 0x87, 0x22 },
            .{ .value = 0 },
        ),
        sig,
    );
}

test "sign and verify fail" {
    var s = secp.Secp256k1.genNew();
    defer s.deinit();

    var seed: [32]u8 = undefined;
    std.crypto.random.bytes(&seed);

    s.seededRandomize(seed);

    const msg = secp.Message{
        .inner = seed,
    };

    const sk, const pk = s.generateKeypair(std.crypto.random);

    const sigr = s.signEcdsaRecoverable(&msg, &sk);
    const sig = sigr.toStandard();

    std.crypto.random.bytes(&seed);

    const _msg = secp.Message{
        .inner = seed,
    };

    try std.testing.expectError(
        error.IncorrectSignature,
        s.verifyEcdsa(_msg, sig, pk),
    );
}

test "sign with recovery" {
    var s = secp.Secp256k1.genNew();
    defer s.deinit();

    var seed: [32]u8 = undefined;
    std.crypto.random.bytes(&seed);

    s.seededRandomize(seed);

    const msg = secp.Message{
        .inner = seed,
    };

    const sk, const pk = s.generateKeypair(std.crypto.random);

    const sigr = s.signEcdsaRecoverable(&msg, &sk);
    try std.testing.expectEqualDeep(
        try s.recoverEcdsa(&msg, &sigr),
        pk,
    );
}

test "sign with recovery and nonce data" {
    var s = secp.Secp256k1.genNew();
    defer s.deinit();

    var seed: [32]u8 = undefined;
    std.crypto.random.bytes(&seed);

    s.seededRandomize(seed);

    const msg = secp.Message{
        .inner = seed,
    };

    const sk, const pk = s.generateKeypair(std.crypto.random);

    const noncedata = [_]u8{42} ** 32;

    const sigr = s.signEcdsaRecoverableWithNoncedata(
        &msg,
        &sk,
        noncedata,
    );

    try std.testing.expectEqualDeep(
        try s.recoverEcdsa(&msg, &sigr),
        pk,
    );
}

test "recov sig serialize compact" {
    const recid_in: RecoveryId = .{ .value = 1 };
    const bytes_in = &.{ 0x66, 0x73, 0xff, 0xad, 0x21, 0x47, 0x74, 0x1f, 0x04, 0x77, 0x2b, 0x6f, 0x92, 0x1f, 0x0b, 0xa6, 0xaf, 0x0c, 0x1e, 0x77, 0xfc, 0x43, 0x9e, 0x65, 0xc3, 0x6d, 0xed, 0xf4, 0x09, 0x2e, 0x88, 0x98, 0x4c, 0x1a, 0x97, 0x16, 0x52, 0xe0, 0xad, 0xa8, 0x80, 0x12, 0x0e, 0xf8, 0x02, 0x5e, 0x70, 0x9f, 0xff, 0x20, 0x80, 0xc4, 0xa3, 0x9a, 0xae, 0x06, 0x8d, 0x12, 0xee, 0xd0, 0x09, 0xb6, 0x8c, 0x89 };

    const sig = try RecoverableSignature.fromCompact(bytes_in, recid_in);

    const recid_out, const bytes_out = sig.serializeCompact();

    try std.testing.expectEqualSlices(u8, bytes_in, &bytes_out);

    try std.testing.expectEqual(recid_in, recid_out);
}

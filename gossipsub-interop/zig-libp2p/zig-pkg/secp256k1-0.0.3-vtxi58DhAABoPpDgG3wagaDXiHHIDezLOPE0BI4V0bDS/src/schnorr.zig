const std = @import("std");
const constants = @import("constants.zig");
const crypto = std.crypto;

const secp_mod = @import("secp256k1.zig");
const secp256k1 = secp_mod.secp256k1;

const Error = secp_mod.Error;
const ErrorParseHex = secp_mod.ErrorParseHex;
const Secp256k1 = secp_mod.Secp256k1;
const KeyPair = secp_mod.KeyPair;
const SecretKey = secp_mod.SecretKey;
const XOnlyPublicKey = secp_mod.XOnlyPublicKey;

pub const Signature = struct {
    inner: [constants.schnorr_signature_size]u8,

    pub fn fromStr(s: []const u8) (ErrorParseHex || Error)!Signature {
        if (s.len > constants.schnorr_signature_size * 2) return error.InvalidSignature;
        var res: [constants.schnorr_signature_size]u8 = undefined;

        _ = try std.fmt.hexToBytes(&res, s);

        return .{ .inner = res };
    }

    /// Encodes a sequence of bytes as hexadecimal digits.
    /// Returns an array containing the encoded bytes.
    /// Lower-case format "abc"
    pub inline fn toStr(self: *const Signature) [constants.schnorr_signature_size * 2]u8 {
        return std.fmt.bytesToHex(self.inner, .lower);
    }
};

pub const Secp = struct {
    /// Creates a schnorr signature using the given auxiliary random data.
    pub fn signSchnorrWithAuxRand(
        self: *const Secp256k1,
        msg: [32]u8,
        keypair: KeyPair,
        aux_rand: [32]u8,
    ) Signature {
        return self.signSchnorrHelper(&msg, keypair, &aux_rand);
    }

    /// Verifies a schnorr signature.
    pub fn verifySchnorr(
        self: *const Secp256k1,
        sig: Signature,
        msg: [32]u8,
        pubkey: XOnlyPublicKey,
    ) Error!void {
        if (secp256k1.secp256k1_schnorrsig_verify(
            self.ctx,
            &sig.inner,
            &msg,
            32,
            &pubkey.inner,
        ) != 1) return Error.InvalidSignature;
    }

    pub fn signSchnorrHelper(self: *const Secp256k1, msg: []const u8, keypair: KeyPair, nonce_data: []const u8) Signature {
        var sig: [64]u8 = undefined;

        std.debug.assert(1 == secp256k1.secp256k1_schnorrsig_sign(self.ctx, (&sig).ptr, msg.ptr, &keypair.inner, nonce_data.ptr));

        return .{ .inner = sig };
    }
};

// SPDX-License-Identifier: CC0-1.0

//! Implements [`SerializedSignature`] and related types.
//!
//! DER-serialized signatures have the issue that they can have different lengths.
//! We want to avoid using `Vec` since that would require allocations making the code slower and
//! unable to run on platforms without allocator. We implement a special type to encapsulate
//! serialized signatures and since it's a bit more complicated it has its own module.
const std = @import("std");
const assert = std.debug.assert;
const ecdsa = @import("ecdsa.zig");

const Signature = ecdsa.Signature;

pub const MAX_LEN: usize = 72;

/// A DER serialized Signature
pub const SerializedSignature = struct {
    data: [MAX_LEN]u8,
    len: usize,

    pub fn toString(self: SerializedSignature) [MAX_LEN * 2]u8 {
        return std.fmt.bytesToHex(self.data, .lower);
    }

    /// Creates `SerializedSignature` from data and length.
    ///
    /// ## Panics
    ///
    /// If `len` > `MAX_LEN`
    pub inline fn fromRawParts(data: [MAX_LEN]u8, len: usize) SerializedSignature {
        assert(len <= MAX_LEN);
        return .{ .data = data, .len = len };
    }

    /// Convert the serialized signature into the Signature struct.
    /// (This DER deserializes it)
    pub inline fn toSignature(self: SerializedSignature) !Signature {
        return Signature.fromDer(self);
    }

    /// Create a SerializedSignature from a Signature.
    /// (this DER serializes it)
    pub inline fn fromSignature(sig: *const Signature) !SerializedSignature {
        return sig.serializeDer();
    }
};

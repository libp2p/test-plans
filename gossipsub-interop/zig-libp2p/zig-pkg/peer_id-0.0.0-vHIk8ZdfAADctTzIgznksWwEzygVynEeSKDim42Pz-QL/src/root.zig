pub const keys = @import("keys.proto.zig");
pub const PublicKey = keys.PublicKey;
pub const PrivateKey = keys.PrivateKey;
pub const KeyType = keys.KeyType;
pub const PrivateKeyReader = keys.PrivateKeyReader;
pub const PublicKeyReader = keys.PublicKeyReader;

pub const id = @import("id.zig");
pub const PeerId = id.PeerId;

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}

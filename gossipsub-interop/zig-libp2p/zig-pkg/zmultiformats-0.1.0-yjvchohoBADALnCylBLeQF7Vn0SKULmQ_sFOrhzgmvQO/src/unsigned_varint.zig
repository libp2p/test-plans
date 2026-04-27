const std = @import("std");
const testing = std.testing;

/// VarintError represents an error that occurred during varint encoding or decoding.
pub const VarintParseError = error{
    Insufficient,
    Overflow,
    NotMinimal,
};

/// encode encodes a number into a varint and writes it to the buffer.
pub fn encode(comptime T: type, number: T, buffer: []u8) []u8 {
    var n = number;
    var i: usize = 0;

    while (true) {
        buffer[i] = (@as(u8, @truncate(n))) | 0x80;
        n >>= 7;
        if (n == 0) {
            buffer[i] &= 0x7f;
            break;
        }
        i += 1;
    }

    return buffer[0 .. i + 1];
}

/// decode decodes a varint from a buffer and returns the decoded number and the remaining bytes.
pub fn decode(comptime T: type, buffer: []const u8) !struct { value: T, remaining: []const u8 } {
    var value: T = 0;
    var i: usize = 0;
    const max_bytes_len = maxBytesForType(T);

    while (i < buffer.len) {
        const b = buffer[i];

        const k = @as(T, b & 0x7F);
        value |= k << @intCast(i * 7);

        if (isLast(b)) {
            if (b == 0 and i > 0) {
                return VarintParseError.NotMinimal;
            }
            return .{
                .value = value,
                .remaining = buffer[i + 1 ..],
            };
        }

        i += 1;
        if (i >= max_bytes_len) {
            return VarintParseError.Overflow;
        }
    }
    return VarintParseError.Insufficient;
}

fn isLast(b: u8) bool {
    return (b & 0x80) == 0;
}

fn maxBytesForType(comptime T: type) usize {
    return switch (T) {
        u8 => 2,
        u16 => 3,
        u32 => 5,
        u64 => 10,
        u128 => 19,
        usize => switch (@sizeOf(usize)) {
            4 => 5, // 32-bit
            8 => 10, // 64-bit
            else => @compileError("Unsupported usize width"),
        },
        else => @compileError("Unsupported integer type"),
    };
}

/// bufferSize returns the size of the buffer needed to encode a varint.
pub fn bufferSize(comptime T: type) usize {
    return maxBytesForType(T);
}

/// encodeStream encodes a number into a varint and writes it to the writer.
pub fn encodeStream(writer: anytype, comptime T: type, number: T) !usize {
    var buf: [bufferSize(T)]u8 = undefined;
    const encoded = encode(T, number, &buf);
    try writer.writeAll(encoded);
    return encoded.len;
}

/// decodeStream decodes a varint from the reader and returns the decoded number.
pub fn decodeStream(reader: anytype, comptime T: type) !T {
    var value: T = 0;
    var i: usize = 0;
    var continuation_bytes: usize = 0;

    while (true) {
        const byte = try reader.readByte();

        if (!isLast(byte)) {
            continuation_bytes += 1;
            if (continuation_bytes >= maxBytesForType(T)) {
                return VarintParseError.Overflow;
            }
        }

        const k = @as(T, byte & 0x7F);
        value |= k << @intCast(i * 7);

        if (isLast(byte)) {
            if (byte == 0 and i > 0) {
                return VarintParseError.NotMinimal;
            }
            return value;
        }

        i += 1;
    }
}

test "identity_u8" {
    var buf: [bufferSize(u8)]u8 = undefined;
    var n: u8 = 0;
    while (n < std.math.maxInt(u8)) : (n += 1) {
        const encoded = encode(u8, n, &buf);
        const decoded = try decode(u8, encoded);
        try testing.expectEqual(n, decoded.value);
    }
}

test "identity_u16" {
    var buf: [bufferSize(u16)]u8 = undefined;
    var n: u16 = 0;
    while (n < std.math.maxInt(u16)) : (n += 1) {
        const encoded = encode(u16, n, &buf);
        const decoded = try decode(u16, encoded);
        try testing.expectEqual(n, decoded.value);
    }
}

test "identity_u32" {
    var buf: [bufferSize(u32)]u8 = undefined;
    var n: u32 = 0;
    while (n < 1_000_000) : (n += 1) {
        const encoded = encode(u32, n, &buf);
        const decoded = try decode(u32, encoded);
        try testing.expectEqual(n, decoded.value);
    }
    // Test max value
    const encoded = encode(u32, std.math.maxInt(u32), &buf);
    const decoded = try decode(u32, encoded);
    try testing.expectEqual(std.math.maxInt(u32), decoded.value);
}

test "various" {
    // Empty buffer test
    try testing.expectError(error.Insufficient, decode(u8, &[_]u8{}));

    // Single byte insufficient test
    try testing.expectError(error.Insufficient, decode(u8, &[_]u8{0x80}));

    // Simple values
    {
        const decoded = try decode(u8, &[_]u8{1});
        try testing.expectEqual(@as(u8, 1), decoded.value);
    }
    {
        const decoded = try decode(u8, &[_]u8{0b0111_1111});
        try testing.expectEqual(@as(u8, 127), decoded.value);
    }
    {
        const decoded = try decode(u8, &[_]u8{ 0b1000_0000, 1 });
        try testing.expectEqual(@as(u8, 128), decoded.value);
    }
    {
        const decoded = try decode(u8, &[_]u8{ 0b1111_1111, 1 });
        try testing.expectEqual(@as(u8, 255), decoded.value);
    }

    // Overflow test
    try testing.expectError(error.Overflow, decode(u64, &[_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80 }));
}

test "edge_cases" {
    var buf: [bufferSize(u64)]u8 = undefined;

    // Max values
    {
        const encoded = encode(u64, std.math.maxInt(u64), &buf);
        const decoded = try decode(u64, encoded);
        try testing.expectEqual(std.math.maxInt(u64), decoded.value);
    }

    // Zero
    {
        const encoded = encode(u64, 0, &buf);
        const decoded = try decode(u64, encoded);
        try testing.expectEqual(@as(u64, 0), decoded.value);
    }
}

test "error_cases" {
    // Empty buffer
    try testing.expectError(error.Insufficient, decode(u8, &[_]u8{}));

    // Incomplete sequence
    try testing.expectError(error.Insufficient, decode(u8, &[_]u8{0x80}));

    // Non-minimal encoding
    try testing.expectError(error.NotMinimal, decode(u8, &[_]u8{ 0x80, 0x00 }));

    // Overflow with too many continuation bytes
    try testing.expectError(error.Overflow, decode(u64, &[_]u8{
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,
    }));
}

test "specific_values" {
    // Test some specific interesting values
    const TestCase = struct {
        value: u64,
        encoded: []const u8,
    };

    const test_cases = [_]TestCase{
        .{ .value = 1, .encoded = &[_]u8{1} },
        .{ .value = 127, .encoded = &[_]u8{0x7f} },
        .{ .value = 128, .encoded = &[_]u8{ 0x80, 0x01 } },
        .{ .value = 255, .encoded = &[_]u8{ 0xff, 0x01 } },
        .{ .value = 300, .encoded = &[_]u8{ 0xac, 0x02 } },
        .{ .value = 16384, .encoded = &[_]u8{ 0x80, 0x80, 0x01 } },
    };

    for (test_cases) |case| {
        const decoded = try decode(u64, case.encoded);
        try testing.expectEqual(case.value, decoded.value);
    }
}

test "stream_identity" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(testing.allocator);

    const numbers = [_]u64{ 1, 127, 128, 255, 300, 16384 };

    for (numbers) |n| {
        // Encode to stream
        const written = try encodeStream(buf.writer(testing.allocator), u64, n);
        try testing.expectEqual(written, encode(u64, n, buf.items[0..]).len);

        // Decode from stream
        var stream = std.io.fixedBufferStream(buf.items);
        const decoded = try decodeStream(stream.reader(), u64);

        try testing.expectEqual(n, decoded);
        buf.clearRetainingCapacity();
    }
}

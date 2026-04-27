const std = @import("std");

/// DecodeError represents an error that occurred during decoding a multibase string.
pub const ParseError = error{
    InvalidChar,
    InvalidBaseString,
    InvalidPrefix,
};

/// MultiBaseCodec represents a multibase encoding.
/// It is used to decode a multibase string into a byte slice.
/// It is used to encode a byte slice into a multibase string.
/// It is used to get the code of a base.
pub const MultiBaseCodec = enum {
    Identity,
    Base2,
    Base8,
    Base10,
    Base16Lower,
    Base16Upper,
    Base32Lower,
    Base32Upper,
    Base32PadLower,
    Base32PadUpper,
    Base32HexLower,
    Base32HexUpper,
    Base32HexPadLower,
    Base32HexPadUpper,
    Base32Z,
    Base36Lower,
    Base36Upper,
    Base58Flickr,
    Base58Btc,
    Base64,
    Base64Pad,
    Base64Url,
    Base64UrlPad,
    Base256Emoji,

    /// Returns the code of the multibase encoding.
    /// The code is a byte slice that represents the multibase encoding.
    pub fn code(self: MultiBaseCodec) []const u8 {
        return switch (self) {
            .Identity => "\x00",
            .Base2 => "0",
            .Base8 => "7",
            .Base10 => "9",
            .Base16Lower => "f",
            .Base16Upper => "F",
            .Base32Lower => "b",
            .Base32Upper => "B",
            .Base32PadLower => "c",
            .Base32PadUpper => "C",
            .Base32HexLower => "v",
            .Base32HexUpper => "V",
            .Base32HexPadLower => "t",
            .Base32HexPadUpper => "T",
            .Base32Z => "h",
            .Base36Lower => "k",
            .Base36Upper => "K",
            .Base58Flickr => "Z",
            .Base58Btc => "z",
            .Base64 => "m",
            .Base64Pad => "M",
            .Base64Url => "u",
            .Base64UrlPad => "U",
            .Base256Emoji => "🚀",
        };
    }

    pub fn fromCode(source: []const u8) ParseError!MultiBaseCodec {
        if (source.len == 0) return ParseError.InvalidPrefix;

        // Handle multi-byte UTF-8 prefixes
        if (std.mem.startsWith(u8, source, "🚀")) return .Base256Emoji;

        return switch (source[0]) {
            0 => .Identity,
            '0' => .Base2,
            '7' => .Base8,
            '9' => .Base10,
            'f' => .Base16Lower,
            'F' => .Base16Upper,
            'b' => .Base32Lower,
            'B' => .Base32Upper,
            'c' => .Base32PadLower,
            'C' => .Base32PadUpper,
            'v' => .Base32HexLower,
            'V' => .Base32HexUpper,
            't' => .Base32HexPadLower,
            'T' => .Base32HexPadUpper,
            'h' => .Base32Z,
            'k' => .Base36Lower,
            'K' => .Base36Upper,
            'z' => .Base58Btc,
            'Z' => .Base58Flickr,
            'm' => .Base64,
            'M' => .Base64Pad,
            'u' => .Base64Url,
            'U' => .Base64UrlPad,
            else => return ParseError.InvalidBaseString,
        };
    }

    /// Returns the length of the code of the multibase encoding.
    pub fn codeLength(self: MultiBaseCodec) usize {
        return self.code().len;
    }

    /// Encodes a byte slice into a multibase string.
    /// The destination buffer must be large enough to hold the encoded string.
    /// Returns the encoded multibase string.
    pub fn encode(self: *const MultiBaseCodec, dest: []u8, source: []const u8) []const u8 {
        const code_str = self.code();
        @memcpy(dest[0..code_str.len], code_str);
        const encoded = switch (self.*) {
            .Identity => IdentityImpl.encode(dest[code_str.len..], source),
            .Base2 => Base2Impl.encode(dest[code_str.len..], source),
            .Base8 => Base8Impl.encode(dest[code_str.len..], source),
            .Base10 => Base10Impl.encode(dest[code_str.len..], source),
            .Base16Lower => Base16Impl.encodeLower(dest[code_str.len..], source),
            .Base16Upper => Base16Impl.encodeUpper(dest[code_str.len..], source),
            .Base32Lower => Base32Impl.encode(dest[code_str.len..], source, Base32Impl.ALPHABET_LOWER, false),
            .Base32Upper => Base32Impl.encode(dest[code_str.len..], source, Base32Impl.ALPHABET_UPPER, false),
            .Base32HexLower => Base32Impl.encode(dest[code_str.len..], source, Base32Impl.ALPHABET_HEX_LOWER, false),
            .Base32HexUpper => Base32Impl.encode(dest[code_str.len..], source, Base32Impl.ALPHABET_HEX_UPPER, false),
            .Base32PadLower => Base32Impl.encode(dest[code_str.len..], source, Base32Impl.ALPHABET_LOWER, true),
            .Base32PadUpper => Base32Impl.encode(dest[code_str.len..], source, Base32Impl.ALPHABET_UPPER, true),
            .Base32HexPadLower => Base32Impl.encode(dest[code_str.len..], source, Base32Impl.ALPHABET_HEX_LOWER, true),
            .Base32HexPadUpper => Base32Impl.encode(dest[code_str.len..], source, Base32Impl.ALPHABET_HEX_UPPER, true),
            .Base32Z => Base32Impl.encode(dest[code_str.len..], source, Base32Impl.ALPHABET_Z, false),
            .Base36Lower => Base36Impl.encodeLower(dest[code_str.len..], source),
            .Base36Upper => Base36Impl.encodeUpper(dest[code_str.len..], source),
            .Base58Flickr => Base58Impl.encodeFlickr(dest[code_str.len..], source),
            .Base58Btc => Base58Impl.encodeBtc(dest[code_str.len..], source),
            .Base64 => std.base64.standard_no_pad.Encoder.encode(dest[code_str.len..], source),
            .Base64Pad => std.base64.standard.Encoder.encode(dest[code_str.len..], source),
            .Base64Url => std.base64.url_safe_no_pad.Encoder.encode(dest[code_str.len..], source),
            .Base64UrlPad => std.base64.url_safe.Encoder.encode(dest[code_str.len..], source),
            .Base256Emoji => Base256emojiImpl.encode(dest[code_str.len..], source),
        };

        return dest[0 .. code_str.len + encoded.len];
    }

    /// Decodes a multibase string into a byte slice.
    /// The destination buffer must be large enough to hold the decoded byte slice.
    /// Returns the decoded byte slice.
    pub fn decode(self: *const MultiBaseCodec, dest: []u8, source: []const u8) ![]const u8 {
        return switch (self.*) {
            .Identity => IdentityImpl.decode(dest, source),
            .Base2 => Base2Impl.decode(dest, source),
            .Base8 => Base8Impl.decode(dest, source),
            .Base10 => Base10Impl.decode(dest, source),
            .Base16Lower => Base16Impl.decode(dest, source),
            .Base16Upper => Base16Impl.decode(dest, source),
            .Base32Lower => Base32Impl.decode(dest, source, &Base32Impl.DECODE_TABLE_LOWER),
            .Base32Upper => Base32Impl.decode(dest, source, &Base32Impl.DECODE_TABLE_UPPER),
            .Base32HexLower => Base32Impl.decode(dest, source, &Base32Impl.DECODE_TABLE_HEX_LOWER),
            .Base32HexUpper => Base32Impl.decode(dest, source, &Base32Impl.DECODE_TABLE_HEX_UPPER),
            .Base32PadLower => Base32Impl.decode(dest, source, &Base32Impl.DECODE_TABLE_LOWER),
            .Base32PadUpper => Base32Impl.decode(dest, source, &Base32Impl.DECODE_TABLE_UPPER),
            .Base32HexPadLower => Base32Impl.decode(dest, source, &Base32Impl.DECODE_TABLE_HEX_LOWER),
            .Base32HexPadUpper => Base32Impl.decode(dest, source, &Base32Impl.DECODE_TABLE_HEX_UPPER),
            .Base32Z => Base32Impl.decode(dest, source, &Base32Impl.DECODE_TABLE_Z),
            .Base36Lower => Base36Impl.decode(dest, source, Base36Impl.ALPHABET_LOWER),
            .Base36Upper => Base36Impl.decode(dest, source, Base36Impl.ALPHABET_UPPER),
            .Base58Flickr => Base58Impl.decodeFlickr(dest, source),
            .Base58Btc => Base58Impl.decodeBtc(dest, source),
            .Base64 => blk: {
                try std.base64.standard_no_pad.Decoder.decode(dest, source);
                break :blk dest[0..try std.base64.standard_no_pad.Decoder.calcSizeForSlice(source)];
            },
            .Base64Pad => blk: {
                try std.base64.standard.Decoder.decode(dest, source);
                break :blk dest[0..try std.base64.standard.Decoder.calcSizeForSlice(source)];
            },
            .Base64Url => blk: {
                try std.base64.url_safe_no_pad.Decoder.decode(dest, source);
                break :blk dest[0..try std.base64.url_safe_no_pad.Decoder.calcSizeForSlice(source)];
            },
            .Base64UrlPad => blk: {
                try std.base64.url_safe.Decoder.decode(dest, source);
                break :blk dest[0..try std.base64.url_safe.Decoder.calcSizeForSlice(source)];
            },
            .Base256Emoji => Base256emojiImpl.decode(dest, source),
        };
    }

    /// Calculates the size needed for encoding the given source bytes
    pub fn encodedLen(self: *const MultiBaseCodec, source: []const u8) usize {
        const code_len = self.code().len;
        return code_len + switch (self.*) {
            .Identity => source.len,
            .Base2 => source.len * 8,
            .Base8 => @divTrunc((source.len * 8 + 2), 3),
            .Base10 => blk: {
                if (source.len == 0) break :blk 1;
                var size: usize = 1;
                for (source) |byte| {
                    if (byte == 0) {
                        size += 1;
                        continue;
                    }
                    size += @as(usize, @intFromFloat(@ceil(@log10(@as(f64, @floatFromInt(byte))))));
                }
                break :blk size;
            },
            .Base16Lower, .Base16Upper => source.len * 2,
            .Base32Lower, .Base32Upper, .Base32HexLower, .Base32HexUpper, .Base32Z => @divTrunc((source.len * 8 + 4), 5),
            .Base32PadLower, .Base32PadUpper, .Base32HexPadLower, .Base32HexPadUpper => (@divTrunc((source.len + 4), 5)) * 8,
            .Base36Lower, .Base36Upper => blk: {
                if (source.len == 0) break :blk 1;
                var size: usize = 1;
                for (source) |byte| {
                    if (byte == 0) {
                        size += 1;
                        continue;
                    }
                    size += @as(usize, @intFromFloat(@ceil(@log(36.0) / @log(2.0) * 8.0)));
                }
                break :blk size;
            },
            .Base58Flickr, .Base58Btc => blk: {
                if (source.len == 0) break :blk 1;
                // Base58 expands at worst case by log(256)/log(58) ≈ 1.37 times
                const size = @as(usize, @intFromFloat(@ceil(@as(f64, @floatFromInt(source.len)) * 137 / 100)));
                break :blk size;
            },
            .Base64, .Base64Url => @divTrunc((source.len + 2), 3) * 4,
            .Base64Pad, .Base64UrlPad => @divTrunc((source.len + 2), 3) * 4,
            .Base256Emoji => source.len * 4, // Each emoji is up to 4 bytes in UTF-8
        };
    }

    /// Calculates the maximum size needed for source_size bytes when encoding
    pub fn encodedLenBySize(self: *const MultiBaseCodec, source_size: usize) usize {
        const code_len = self.code().len;
        return code_len + switch (self.*) {
            .Identity => source_size,
            .Base2 => source_size * 8,
            .Base8 => @divTrunc((source_size * 8 + 2), 3),
            .Base10 => blk: {
                if (source_size == 0) break :blk 1;
                var size: usize = 1;
                for (0..source_size) |i| {
                    const byte: u8 = @as(u8, 1) << @as(u3, @intCast(i % 8));
                    if (byte == 0) {
                        size += 1;
                        continue;
                    }
                    size += @as(usize, @intFromFloat(@ceil(@log10(@as(f64, @floatFromInt(byte))))));
                }
                break :blk size;
            },
            .Base16Lower, .Base16Upper => source_size * 2,
            .Base32Lower, .Base32Upper, .Base32HexLower, .Base32HexUpper, .Base32Z => @divTrunc((source_size * 8 + 4), 5),
            .Base32PadLower, .Base32PadUpper, .Base32HexPadLower, .Base32HexPadUpper => @divTrunc((source_size + 4), 5) * 8,
            .Base36Lower, .Base36Upper => blk: {
                if (source_size == 0) break :blk 1;
                var size: usize = 1;
                for (0..source_size) |i| {
                    const byte: u8 = @as(u8, 1) << @as(u3, @intCast(i % 8));
                    if (byte == 0) {
                        size += 1;
                        continue;
                    }
                    size += @as(usize, @intFromFloat(@ceil(@log(36.0) / @log(2.0) * 8.0)));
                }
                break :blk size;
            },
            .Base58Flickr, .Base58Btc => blk: {
                if (source_size == 0) break :blk 1;
                // Base58 expands at worst case by log(256)/log(58) ≈ 1.37 times
                const size = @as(usize, @intFromFloat(@ceil(@as(f64, @floatFromInt(source_size)) * 137 / 100)));
                break :blk size;
            },
            .Base64, .Base64Url => @divTrunc((source_size + 2), 3) * 4,
            .Base64Pad, .Base64UrlPad => @divTrunc((source_size + 2), 3) * 4,
            .Base256Emoji => source_size * 4, // Each emoji is up to 4 bytes in UTF-8
        };
    }
    /// Calculates the maximum size needed for decoding the given encoded string
    pub fn decodedLen(self: *const MultiBaseCodec, source: []const u8) usize {
        return switch (self.*) {
            .Identity => source.len,
            .Base2 => @divTrunc((source.len + 7), 8),
            .Base8 => @divTrunc((source.len * 3 + 7), 8),
            .Base10 => source.len,
            .Base16Lower, .Base16Upper => @divTrunc((source.len + 1), 2),
            .Base32Lower, .Base32Upper, .Base32HexLower, .Base32HexUpper, .Base32PadLower, .Base32PadUpper, .Base32HexPadLower, .Base32HexPadUpper, .Base32Z => @divTrunc((source.len * 5 + 7), 8),
            .Base36Lower, .Base36Upper => source.len,
            .Base58Flickr, .Base58Btc => source.len,
            .Base64, .Base64Url, .Base64Pad, .Base64UrlPad => @divTrunc((source.len * 3 + 3), 4),
            .Base256Emoji => @divTrunc((source.len + 3), 4),
        };
    }

    /// Calculates the maximum size needed for decoding the given encoded string
    pub fn decodedLenBySize(self: *const MultiBaseCodec, source_size: usize) usize {
        return switch (self.*) {
            .Identity => source_size,
            .Base2 => @divTrunc((source_size + 7), 8),
            .Base8 => @divTrunc((source_size * 3 + 7), 8),
            .Base10 => source_size,
            .Base16Lower, .Base16Upper => @divTrunc((source_size + 1), 2),
            .Base32Lower, .Base32Upper, .Base32HexLower, .Base32HexUpper, .Base32PadLower, .Base32PadUpper, .Base32HexPadLower, .Base32HexPadUpper, .Base32Z => @divTrunc((source_size * 5 + 7), 8),
            .Base36Lower, .Base36Upper => source_size,
            .Base58Flickr, .Base58Btc => source_size,
            .Base64, .Base64Url, .Base64Pad, .Base64UrlPad => @divTrunc((source_size * 3 + 3), 4),
            .Base256Emoji => @divTrunc((source_size + 3), 4),
        };
    }

    pub const IdentityImpl = struct {
        pub fn encode(dest: []u8, source: []const u8) []const u8 {
            @memcpy(dest[0..source.len], source);
            return dest[0..source.len];
        }

        pub fn decode(dest: []u8, source: []const u8) ![]const u8 {
            @memcpy(dest[0..source.len], source);
            return dest[0..source.len];
        }
    };

    pub const Base2Impl = struct {
        const alphabet_chars = "01".*;
        const mask = @Vector(8, u8){ 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01 };
        const Vec = @Vector(16, u8);
        const ascii_zero: Vec = @splat('0');
        const ascii_one: Vec = @splat('1');

        pub fn encode(dest: []u8, source: []const u8) []const u8 {
            var out_idx: usize = 0;
            const zero_char_vec: @Vector(8, u8) = @splat('0');
            const zero_vec: @Vector(8, u8) = @splat(0);
            for (source) |byte| {
                const broadcast: @Vector(8, u8) = @splat(byte);
                const bits: @Vector(8, u8) = zero_char_vec + @intFromBool((broadcast & mask) != zero_vec);
                @memcpy(dest[out_idx..][0..8], std.mem.asBytes(&bits));
                out_idx += 8;
            }
            return dest[0..out_idx];
        }

        pub fn decode(dest: []u8, source: []const u8) ![]const u8 {
            var dest_index: usize = 0;
            var i: usize = 0;

            // Validate input using SIMD
            while (i + 16 <= source.len) : (i += 16) {
                const chunk = @as(Vec, source[i..][0..16].*);
                const is_valid = @reduce(.And, chunk >= ascii_zero) and
                    @reduce(.And, chunk <= ascii_one);
                if (!is_valid) return ParseError.InvalidChar;
            }

            // Process 16 bits (2 bytes) at once
            i = 0;
            while (i + 16 <= source.len) : (i += 16) {
                var value: u16 = 0;
                inline for (0..16) |j| {
                    value = (value << 1) | (source[i + j] - '0');
                }
                dest[dest_index] = @truncate(value >> 8);
                dest[dest_index + 1] = @truncate(value);
                dest_index += 2;
            }

            // Handle remaining bits
            var current_byte: u8 = 0;
            var bits: u4 = 0;
            while (i < source.len) : (i += 1) {
                const c = source[i];
                if (c < '0' or c > '1') return ParseError.InvalidChar;

                current_byte = (current_byte << 1) | (c - '0');
                bits += 1;
                if (bits == 8) {
                    dest[dest_index] = current_byte;
                    dest_index += 1;
                    bits = 0;
                    current_byte = 0;
                }
            }

            if (bits > 0) {
                dest[dest_index] = current_byte << @as(u3, @intCast(8 - bits));
                dest_index += 1;
            }

            return dest[0..dest_index];
        }
    };

    pub const Base8Impl = struct {
        const Vec = @Vector(16, u8);
        const ascii_zero: Vec = @splat('0');
        const ascii_seven: Vec = @splat('7');

        pub fn encode(dest: []u8, source: []const u8) []const u8 {
            var dest_index: usize = 0;
            var i: usize = 0;

            // Process 3 bytes at once (8 octal digits)
            while (i + 3 <= source.len) : (i += 3) {
                const value = (@as(u32, source[i]) << 16) |
                    (@as(u32, source[i + 1]) << 8) |
                    source[i + 2];

                inline for (0..8) |j| {
                    const shift = 21 - (j * 3);
                    const index = (value >> shift) & 0x7;
                    dest[dest_index + j] = '0' + @as(u8, @truncate(index));
                }
                dest_index += 8;
            }

            // Handle remaining bytes
            var bits: u16 = 0;
            var bit_count: u4 = 0;

            while (i < source.len) : (i += 1) {
                bits = (bits << 8) | source[i];
                bit_count += 8;

                while (bit_count >= 3) {
                    bit_count -= 3;
                    const index = (bits >> bit_count) & 0x7;
                    dest[dest_index] = '0' + @as(u8, @truncate(index));
                    dest_index += 1;
                }
            }

            if (bit_count > 0) {
                const index = (bits << (3 - bit_count)) & 0x7;
                dest[dest_index] = '0' + @as(u8, @truncate(index));
                dest_index += 1;
            }

            return dest[0..dest_index];
        }

        pub fn decode(dest: []u8, source: []const u8) ParseError![]const u8 {
            var dest_index: usize = 0;
            var i: usize = 0;

            // Validate input using SIMD
            while (i + 16 <= source.len) : (i += 16) {
                const chunk = @as(Vec, source[i..][0..16].*);
                const is_valid = @reduce(.And, chunk >= ascii_zero) and
                    @reduce(.And, chunk <= ascii_seven);
                if (!is_valid) return ParseError.InvalidChar;
            }

            // Process 8 octal digits (3 bytes) at once
            i = 0;
            while (i + 8 <= source.len) : (i += 8) {
                var value: u32 = 0;
                inline for (0..8) |j| {
                    value = (value << 3) | (source[i + j] - '0');
                }
                dest[dest_index] = @truncate(value >> 16);
                dest[dest_index + 1] = @truncate(value >> 8);
                dest[dest_index + 2] = @truncate(value);
                dest_index += 3;
            }

            // Handle remaining digits
            var bits: u16 = 0;
            var bit_count: u4 = 0;

            while (i < source.len) : (i += 1) {
                const c = source[i];
                if (c < '0' or c > '7') return ParseError.InvalidChar;

                bits = (bits << 3) | (c - '0');
                bit_count += 3;

                if (bit_count >= 8) {
                    bit_count -= 8;
                    dest[dest_index] = @truncate(bits >> bit_count);
                    dest_index += 1;
                }
            }

            return dest[0..dest_index];
        }
    };

    pub const Base10Impl = struct {
        pub fn encode(dest: []u8, source: []const u8) []const u8 {
            if (source.len == 0) {
                dest[0] = '0';
                return dest[0..1];
            }

            var dest_index: usize = 0;
            var encode_allocator = std.heap.page_allocator;
            var num: []u8 = encode_allocator.alloc(u8, source.len * 242 / 100 + 1) catch |err| {
                std.debug.print("Allocation error: {}\n", .{err});
                return dest[0..1];
            };
            defer encode_allocator.free(num);
            var num_len: usize = 0;

            // Count leading zeros
            var leading_zeros: usize = 0;
            while (leading_zeros < source.len and source[leading_zeros] == 0) {
                leading_zeros += 1;
            }

            @memset(dest[0..leading_zeros], '0');
            dest_index += leading_zeros;

            // Convert bytes to decimal
            const num_10: u32 = 10;
            const num_256: u32 = 256;
            for (0..source.len) |i| {
                var carry: u32 = source[i];
                var j: usize = 0;
                while (j < num_len or carry > 0) : (j += 1) {
                    if (j < num_len) {
                        carry += @as(u32, num[j]) * num_256;
                    }
                    num[j] = @intCast(carry % num_10);
                    carry /= num_10;
                }
                num_len = j;
            }

            // for (source) |byte| {
            //     var carry: u16 = byte;
            //     var j: usize = 0;
            //     while (j < num_len or carry > 0) : (j += 1) {
            //         if (j < num_len) {
            //             carry += @as(u16, num[j]) << 8;
            //         }
            //         num[j] = @truncate(carry % 10);
            //         carry /= 10;
            //     }
            //     num_len = j;
            // }

            // Convert to ASCII and reverse
            var i: usize = num_len;
            while (i > 0) : (i -= 1) {
                dest[dest_index] = '0' + num[i - 1];
                dest_index += 1;
            }

            return dest[0..dest_index];
        }

        pub fn decode(dest: []u8, source: []const u8) ParseError![]const u8 {
            if (source.len == 0) return dest[0..0];

            var dest_index: usize = 0;
            var encode_allocator = std.heap.page_allocator;
            var num: []u8 = encode_allocator.alloc(u8, source.len * 43 / 100 + 1) catch |err| {
                std.debug.print("Allocation error: {}\n", .{err});
                return dest[0..1];
            };
            defer encode_allocator.free(num);
            var num_len: usize = 0;

            // Count leading zeros using SIMD
            const Vec = @Vector(16, u8);
            const ascii_zero: Vec = @splat('0');
            const ascii_nine: Vec = @splat('9');
            var leading_zeros: usize = 0;

            // Validate digits using SIMD
            var i: usize = 0;
            while (i + 16 <= source.len) : (i += 16) {
                const chunk = @as(Vec, source[i..][0..16].*);
                const valid_digits = @reduce(.And, chunk >= ascii_zero) and @reduce(.And, chunk <= ascii_nine);
                if (!valid_digits) {
                    return ParseError.InvalidChar;
                }
            }

            // Count leading zeros
            while (leading_zeros < source.len and source[leading_zeros] == '0') {
                leading_zeros += 1;
            }

            @memset(dest[0..leading_zeros], 0);
            dest_index += leading_zeros;

            // Convert decimal to bytes
            for (source) |c| {
                if (c < '0' or c > '9') return ParseError.InvalidChar;

                var carry: u16 = c - '0';
                var j: usize = 0;
                while (j < num_len or carry > 0) : (j += 1) {
                    if (j < num_len) {
                        carry += @as(u16, num[j]) * 10;
                    }
                    num[j] = @truncate(carry);
                    carry >>= 8;
                }
                num_len = j;
            }

            // Copy and reverse
            i = num_len;
            while (i > 0) : (i -= 1) {
                dest[dest_index] = num[i - 1];
                dest_index += 1;
            }

            return dest[0..dest_index];
        }
    };

    pub const Base16Impl = struct {
        const ALPHABET_LOWER = "0123456789abcdef";
        const ALPHABET_UPPER = "0123456789ABCDEF";
        const Vec = @Vector(16, u8);

        // Lookup tables for faster decoding
        const DECODE_TABLE = blk: {
            var table: [256]u8 = undefined;
            for (&table) |*v| v.* = 0xFF;
            for (0..16) |i| {
                table[ALPHABET_LOWER[i]] = @truncate(i);
                table[ALPHABET_UPPER[i]] = @truncate(i);
            }
            break :blk table;
        };

        pub fn encodeLower(dest: []u8, source: []const u8) []const u8 {
            var dest_index: usize = 0;
            var i: usize = 0;

            // Process 8 bytes (16 hex chars) at once
            while (i + 8 <= source.len) : (i += 8) {
                inline for (0..8) |j| {
                    const byte = source[i + j];
                    dest[dest_index + j * 2] = ALPHABET_LOWER[byte >> 4];
                    dest[dest_index + j * 2 + 1] = ALPHABET_LOWER[byte & 0x0F];
                }
                dest_index += 16;
            }

            // Handle remaining bytes
            while (i < source.len) : (i += 1) {
                const byte = source[i];
                dest[dest_index] = ALPHABET_LOWER[byte >> 4];
                dest[dest_index + 1] = ALPHABET_LOWER[byte & 0x0F];
                dest_index += 2;
            }

            return dest[0..dest_index];
        }

        pub fn encodeUpper(dest: []u8, source: []const u8) []const u8 {
            var dest_index: usize = 0;
            var i: usize = 0;

            // Process 8 bytes (16 hex chars) at once
            while (i + 8 <= source.len) : (i += 8) {
                inline for (0..8) |j| {
                    const byte = source[i + j];
                    dest[dest_index + j * 2] = ALPHABET_UPPER[byte >> 4];
                    dest[dest_index + j * 2 + 1] = ALPHABET_UPPER[byte & 0x0F];
                }
                dest_index += 16;
            }

            // Handle remaining bytes
            while (i < source.len) : (i += 1) {
                const byte = source[i];
                dest[dest_index] = ALPHABET_UPPER[byte >> 4];
                dest[dest_index + 1] = ALPHABET_UPPER[byte & 0x0F];
                dest_index += 2;
            }

            return dest[0..dest_index];
        }

        pub fn decode(dest: []u8, source: []const u8) ParseError![]const u8 {
            if (source.len % 2 != 0) return ParseError.InvalidChar;

            var dest_index: usize = 0;
            var i: usize = 0;

            // Process 16 hex chars (8 bytes) at once
            while (i + 16 <= source.len) : (i += 16) {
                inline for (0..8) |j| {
                    const high = DECODE_TABLE[source[i + j * 2]];
                    const low = DECODE_TABLE[source[i + j * 2 + 1]];
                    if (high == 0xFF or low == 0xFF) return ParseError.InvalidChar;
                    dest[dest_index + j] = (high << 4) | low;
                }
                dest_index += 8;
            }

            // Handle remaining chars
            while (i < source.len) : (i += 2) {
                const high = DECODE_TABLE[source[i]];
                const low = DECODE_TABLE[source[i + 1]];
                if (high == 0xFF or low == 0xFF) return ParseError.InvalidChar;
                dest[dest_index] = (high << 4) | low;
                dest_index += 1;
            }

            return dest[0..dest_index];
        }
    };

    pub const Base32Impl = struct {
        const ALPHABET_LOWER = "abcdefghijklmnopqrstuvwxyz234567";
        const ALPHABET_UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
        const ALPHABET_HEX_LOWER = "0123456789abcdefghijklmnopqrstuv";
        const ALPHABET_HEX_UPPER = "0123456789ABCDEFGHIJKLMNOPQRSTUV";
        const ALPHABET_Z = "ybndrfg8ejkmcpqxot1uwisza345h769";
        const PADDING = '=';

        // Pre-computed decode tables for each alphabet
        const DECODE_TABLE_LOWER = createDecodeTable(ALPHABET_LOWER);
        const DECODE_TABLE_UPPER = createDecodeTable(ALPHABET_UPPER);
        const DECODE_TABLE_HEX_LOWER = createDecodeTable(ALPHABET_HEX_LOWER);
        const DECODE_TABLE_HEX_UPPER = createDecodeTable(ALPHABET_HEX_UPPER);
        const DECODE_TABLE_Z = createDecodeTable(ALPHABET_Z);

        const DecodeTable = [256]u8;

        fn createDecodeTable(comptime alphabet: []const u8) DecodeTable {
            var table: DecodeTable = [_]u8{0xFF} ** 256;
            for (alphabet, 0..) |c, i| {
                table[c] = @truncate(i);
                // Also add lowercase variant for uppercase alphabets
                if (c >= 'A' and c <= 'Z') {
                    table[c + 32] = @truncate(i); // +32 converts to lowercase
                }
            }
            return table;
        }

        pub fn encode(dest: []u8, source: []const u8, alphabet: []const u8, pad: bool) []const u8 {
            var idx: usize = 0;
            var out_idx: usize = 0;
            // read 40 bits every loop
            var carry = [_]u8{0} ** 8;
            while (idx + 5 <= source.len) : (idx += 5) {
                // [0x01, 0x02, 0x03, 0x04, 0x05] => (0x01 << 32) (0x02 << 24) | (0x03 << 16) | (0x04 << 8) | 0x05
                @memcpy(carry[3..], source[idx..][0..5]);
                const bits = std.mem.readInt(u64, carry[0..], .big);
                inline for (0..8) |i| {
                    dest[out_idx + (7 - i)] = alphabet[(bits >> (i * 5)) & 0x1f];
                }
                out_idx += 8;
            }

            // handle remaining bytes, max 4 byte
            var bits: u16 = 0;
            var bit_count: u4 = 0;
            for (source[idx..]) |byte| {
                bits = (bits << 8) | byte;
                bit_count += 8;
                while (bit_count >= 5) {
                    bit_count -= 5;
                    const index = (bits >> bit_count) & 0x1F;
                    dest[out_idx] = alphabet[index];
                    out_idx += 1;
                }
            }
            if (bit_count > 0) {
                const index = (bits << (5 - bit_count)) & 0x1F;
                dest[out_idx] = alphabet[index];
                out_idx += 1;
            }
            if (pad) {
                const padding = (8 - out_idx % 8) % 8;
                @memset(dest[out_idx..][0..padding], PADDING);
                out_idx += padding;
            }

            return dest[0..out_idx];
        }

        pub fn decode(dest: []u8, source: []const u8, decode_table: *const [256]u8) ParseError![]const u8 {
            var dest_index: usize = 0;
            var bits: u16 = 0;
            var bit_count: u4 = 0;

            for (source) |c| {
                if (c == PADDING) continue;

                const value = decode_table[c];
                if (value == 0xFF) return ParseError.InvalidChar;

                bits = (bits << 5) | value;
                bit_count += 5;

                if (bit_count >= 8) {
                    bit_count -= 8;
                    dest[dest_index] = @truncate(bits >> bit_count);
                    dest_index += 1;
                }
            }

            return dest[0..dest_index];
        }
    };

    pub const Base36Impl = struct {
        const ALPHABET_LOWER = "0123456789abcdefghijklmnopqrstuvwxyz";
        const ALPHABET_UPPER = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        const Vec = @Vector(16, u8);

        // Lookup tables for faster decoding
        const DECODE_TABLE_LOWER = blk: {
            var table: [256]u8 = undefined;
            for (&table) |*v| v.* = 0xFF;
            for (0..36) |i| {
                table[ALPHABET_LOWER[i]] = @truncate(i);
            }
            break :blk table;
        };

        const DECODE_TABLE_UPPER = blk: {
            var table: [256]u8 = undefined;
            for (&table) |*v| v.* = 0xFF;
            for (0..36) |i| {
                table[ALPHABET_UPPER[i]] = @truncate(i);
            }
            break :blk table;
        };

        pub fn encodeLower(dest: []u8, source: []const u8) []const u8 {
            if (source.len == 0) {
                dest[0] = '0';
                return dest[0..1];
            }

            var dest_index: usize = 0;
            var encode_allocator = std.heap.page_allocator;
            var num: []u8 = encode_allocator.alloc(u8, source.len * 156 / 100 + 1) catch |err| {
                std.debug.print("Allocation error: {}\n", .{err});
                return dest[0..1];
            };
            defer encode_allocator.free(num);
            var num_len: usize = 0;

            var leading_zeros: usize = 0;
            while (leading_zeros < source.len and source[leading_zeros] == 0) {
                leading_zeros += 1;
            }

            @memset(dest[0..leading_zeros], '0');
            dest_index += leading_zeros;

            // Convert bytes to base36
            const num_36: u32 = 36;
            const num_256: u32 = 256;
            // Convert bytes to base58
            for (0..source.len) |i| {
                var carry: u32 = source[i];
                var j: usize = 0;
                while (j < num_len or carry > 0) : (j += 1) {
                    if (j < num_len) {
                        carry += @as(u32, num[j]) * num_256;
                    }
                    num[j] = @intCast(carry % num_36);
                    carry /= num_36;
                }
                num_len = j;
            }

            var i: usize = num_len;
            while (i > 0) : (i -= 1) {
                dest[dest_index] = ALPHABET_LOWER[num[i - 1]];
                dest_index += 1;
            }

            return dest[0..dest_index];
        }

        pub fn encodeUpper(dest: []u8, source: []const u8) []const u8 {
            if (source.len == 0) {
                dest[0] = '0';
                return dest[0..1];
            }

            var dest_index: usize = 0;
            // log(256)/log(36) ≈ 1.547 => 156%
            var encode_allocator = std.heap.page_allocator;
            var num: []u8 = encode_allocator.alloc(u8, source.len * 156 / 100 + 1) catch |err| {
                std.debug.print("Allocation error: {}\n", .{err});
                return dest[0..1];
            };
            defer encode_allocator.free(num);
            var num_len: usize = 0;

            // Count leading zeros using SIMD
            const zeros: Vec = @splat(0);
            var leading_zeros: usize = 0;

            while (leading_zeros + 16 <= source.len) {
                const chunk = @as(Vec, source[leading_zeros..][0..16].*);
                const is_zero = chunk == zeros;
                const zero_count = @popCount(@as(u16, @bitCast(is_zero)));
                if (zero_count != 16) break;
                leading_zeros += 16;
            }

            while (leading_zeros < source.len and source[leading_zeros] == 0) {
                leading_zeros += 1;
            }

            @memset(dest[0..leading_zeros], '0');
            dest_index += leading_zeros;

            // Convert bytes to base36
            for (source) |byte| {
                var carry: u16 = byte;
                var j: usize = 0;
                while (j < num_len or carry > 0) : (j += 1) {
                    if (j < num_len) {
                        carry += @as(u16, num[j]) << 8;
                    }
                    num[j] = @truncate(carry % 36);
                    carry /= 36;
                }
                num_len = j;
            }

            var i: usize = num_len;
            while (i > 0) : (i -= 1) {
                dest[dest_index] = ALPHABET_UPPER[num[i - 1]];
                dest_index += 1;
            }

            return dest[0..dest_index];
        }

        pub fn decode(dest: []u8, source: []const u8, alphabet: []const u8) ParseError![]const u8 {
            if (source.len == 0) return dest[0..0];

            const decode_table = if (alphabet.ptr == ALPHABET_LOWER.ptr)
                DECODE_TABLE_LOWER
            else
                DECODE_TABLE_UPPER;

            var dest_index: usize = 0;
            var encode_allocator = std.heap.page_allocator;
            var num: []u8 = encode_allocator.alloc(u8, source.len * 66 / 100 + 1) catch |err| {
                std.debug.print("Allocation error: {}\n", .{err});
                return dest[0..1];
            };
            defer encode_allocator.free(num);
            var num_len: usize = 0;

            // Count leading zeros
            var leading_zeros: usize = 0;
            while (leading_zeros < source.len and source[leading_zeros] == '0') {
                leading_zeros += 1;
            }

            @memset(dest[0..leading_zeros], 0);
            dest_index += leading_zeros;

            // Convert base36 to bytes using lookup table
            for (source[leading_zeros..]) |c| {
                const value = decode_table[c];
                if (value == 0xFF) return ParseError.InvalidChar;

                var carry: u16 = value;
                var j: usize = 0;
                while (j < num_len or carry > 0) : (j += 1) {
                    if (j < num_len) {
                        carry += @as(u16, num[j]) * 36;
                    }
                    num[j] = @truncate(carry);
                    carry >>= 8;
                }
                num_len = j;
            }

            var i: usize = num_len;
            while (i > 0) : (i -= 1) {
                dest[dest_index] = num[i - 1];
                dest_index += 1;
            }

            return dest[0..dest_index];
        }
    };

    pub const Base58Impl = struct {
        const ALPHABET_FLICKR = "123456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ";
        const ALPHABET_BTC = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
        const Vec = @Vector(16, u8);

        // Lookup tables for faster decoding
        const DECODE_TABLE_BTC = blk: {
            var table: [256]u8 = undefined;
            for (&table) |*v| v.* = 0xFF;
            for (0..58) |i| {
                table[ALPHABET_BTC[i]] = @truncate(i);
            }
            break :blk table;
        };

        const DECODE_TABLE_FLICKR = blk: {
            var table: [256]u8 = undefined;
            for (&table) |*v| v.* = 0xFF;
            for (0..58) |i| {
                table[ALPHABET_FLICKR[i]] = @truncate(i);
            }
            break :blk table;
        };

        pub fn encodeBtc(dest: []u8, source: []const u8) []const u8 {
            if (source.len == 0) {
                dest[0] = ALPHABET_BTC[0];
                return dest[0..1];
            }

            var dest_index: usize = 0;
            var encode_allocator = std.heap.page_allocator;
            var num: []u8 = encode_allocator.alloc(u8, source.len * 138 / 100 + 1) catch |err| {
                std.debug.print("Allocation error: {}\n", .{err});
                return dest[0..1];
            };
            defer encode_allocator.free(num);
            var num_len: usize = 0;

            var leading_zeros: usize = 0;
            while (leading_zeros < source.len and source[leading_zeros] == 0) {
                leading_zeros += 1;
            }

            @memset(dest[0..leading_zeros], ALPHABET_BTC[0]);
            dest_index += leading_zeros;

            const b58: u32 = 58;
            const num_256: u32 = 256;
            // Convert bytes to base58
            for (0..source.len) |i| {
                var carry: u32 = source[i];
                var j: usize = 0;
                while (j < num_len or carry > 0) : (j += 1) {
                    if (j < num_len) {
                        carry += @as(u32, num[j]) * num_256;
                    }
                    num[j] = @intCast(carry % b58);
                    carry /= b58;
                }
                num_len = j;
            }

            var i: usize = num_len;
            while (i > 0) : (i -= 1) {
                dest[dest_index] = ALPHABET_BTC[num[i - 1]];
                dest_index += 1;
            }

            return dest[0..dest_index];
        }

        pub fn encodeFlickr(dest: []u8, source: []const u8) []const u8 {
            if (source.len == 0) {
                dest[0] = ALPHABET_FLICKR[0];
                return dest[0..1];
            }

            var dest_index: usize = 0;
            var encode_allocator = std.heap.page_allocator;
            var num: []u8 = encode_allocator.alloc(u8, source.len * 138 / 100 + 1) catch |err| {
                std.debug.print("Allocation error: {}\n", .{err});
                return dest[0..1];
            };
            defer encode_allocator.free(num);
            var num_len: usize = 0;

            // Count leading zeros using SIMD
            const zeros: Vec = @splat(0);
            var leading_zeros: usize = 0;

            while (leading_zeros + 16 <= source.len) {
                const chunk = @as(Vec, source[leading_zeros..][0..16].*);
                const is_zero = chunk == zeros;
                const zero_count = @popCount(@as(u16, @bitCast(is_zero)));
                if (zero_count != 16) break;
                leading_zeros += 16;
            }

            while (leading_zeros < source.len and source[leading_zeros] == 0) {
                leading_zeros += 1;
            }

            @memset(dest[0..leading_zeros], ALPHABET_FLICKR[0]);
            dest_index += leading_zeros;

            // Convert bytes to base58
            for (source) |byte| {
                var carry: u16 = byte;
                var j: usize = 0;
                while (j < num_len or carry > 0) : (j += 1) {
                    if (j < num_len) {
                        carry += @as(u16, num[j]) << 8;
                    }
                    num[j] = @truncate(carry % 58);
                    carry /= 58;
                }
                num_len = j;
            }

            var i: usize = num_len;
            while (i > 0) : (i -= 1) {
                dest[dest_index] = ALPHABET_FLICKR[num[i - 1]];
                dest_index += 1;
            }

            return dest[0..dest_index];
        }

        pub fn decodeBtc(dest: []u8, source: []const u8) ParseError![]const u8 {
            if (source.len == 0) return dest[0..0];

            var dest_index: usize = 0;
            var encode_allocator = std.heap.page_allocator;
            var num: []u8 = encode_allocator.alloc(u8, source.len * 733 / 1000 + 1) catch |err| {
                std.debug.print("Allocation error: {}\n", .{err});
                return dest[0..1];
            };
            defer encode_allocator.free(num);
            var num_len: usize = 0;

            // Count leading zeros
            var leading_zeros: usize = 0;
            while (leading_zeros < source.len and source[leading_zeros] == ALPHABET_BTC[0]) {
                leading_zeros += 1;
            }

            @memset(dest[0..leading_zeros], 0);
            dest_index += leading_zeros;

            // Convert base58 to bytes using lookup table
            for (source[leading_zeros..]) |c| {
                const value = DECODE_TABLE_BTC[c];
                if (value == 0xFF) return ParseError.InvalidChar;

                var carry: u16 = value;
                var j: usize = 0;
                while (j < num_len or carry > 0) : (j += 1) {
                    if (j < num_len) {
                        carry += @as(u16, num[j]) * 58;
                    }
                    num[j] = @truncate(carry);
                    carry >>= 8;
                }
                num_len = j;
            }

            var i: usize = num_len;
            while (i > 0) : (i -= 1) {
                dest[dest_index] = num[i - 1];
                dest_index += 1;
            }

            return dest[0..dest_index];
        }

        pub fn decodeFlickr(dest: []u8, source: []const u8) ParseError![]const u8 {
            if (source.len == 0) return dest[0..0];

            var dest_index: usize = 0;
            var encode_allocator = std.heap.page_allocator;
            var num: []u8 = encode_allocator.alloc(u8, source.len * 733 / 1000 + 1) catch |err| {
                std.debug.print("Allocation error: {}\n", .{err});
                return dest[0..1];
            };
            defer encode_allocator.free(num);
            var num_len: usize = 0;

            // Count leading zeros
            var leading_zeros: usize = 0;
            while (leading_zeros < source.len and source[leading_zeros] == ALPHABET_FLICKR[0]) {
                leading_zeros += 1;
            }

            @memset(dest[0..leading_zeros], 0);
            dest_index += leading_zeros;

            // Convert base58 to bytes using lookup table
            for (source[leading_zeros..]) |c| {
                const value = DECODE_TABLE_FLICKR[c];
                if (value == 0xFF) return ParseError.InvalidChar;

                var carry: u16 = value;
                var j: usize = 0;
                while (j < num_len or carry > 0) : (j += 1) {
                    if (j < num_len) {
                        carry += @as(u16, num[j]) * 58;
                    }
                    num[j] = @truncate(carry);
                    carry >>= 8;
                }
                num_len = j;
            }

            var i: usize = num_len;
            while (i > 0) : (i -= 1) {
                dest[dest_index] = num[i - 1];
                dest_index += 1;
            }

            return dest[0..dest_index];
        }
    };

    pub const Base256emojiImpl = struct {
        const ALPHABET = "🚀🪐☄🛰🌌🌑🌒🌓🌔🌕🌖🌗🌘🌍🌏🌎🐉☀💻🖥💾💿😂❤😍🤣😊🙏💕😭😘👍😅👏😁🔥🥰💔💖💙😢🤔😆🙄💪😉☺👌🤗💜😔😎😇🌹🤦🎉💞✌✨🤷😱😌🌸🙌😋💗💚😏💛🙂💓🤩😄😀🖤😃💯🙈👇🎶😒🤭❣😜💋👀😪😑💥🙋😞😩😡🤪👊🥳😥🤤👉💃😳✋😚😝😴🌟😬🙃🍀🌷😻😓⭐✅🥺🌈😈🤘💦✔😣🏃💐☹🎊💘😠☝😕🌺🎂🌻😐🖕💝🙊😹🗣💫💀👑🎵🤞😛🔴😤🌼😫⚽🤙☕🏆🤫👈😮🙆🍻🍃🐶💁😲🌿🧡🎁⚡🌞🎈❌✊👋😰🤨😶🤝🚶💰🍓💢🤟🙁🚨💨🤬✈🎀🍺🤓😙💟🌱😖👶🥴▶➡❓💎💸⬇😨🌚🦋😷🕺⚠🙅😟😵👎🤲🤠🤧📌🔵💅🧐🐾🍒😗🤑🌊🤯🐷☎💧😯💆👆🎤🙇🍑❄🌴💣🐸💌📍🥀🤢👅💡💩👐📸👻🤐🤮🎼🥵🚩🍎🍊👼💍📣🥂";
        const Vec = @Vector(16, u8);

        // Keep existing lookup tables
        const EMOJI_POSITIONS = init: {
            var table: [256]usize = undefined;
            var pos: usize = 0;
            var i: usize = 0;
            while (i < ALPHABET.len) {
                table[pos] = i;
                pos += 1;
                const len = (std.unicode.utf8ByteSequenceLength(ALPHABET[i]) catch unreachable);
                i += @as(usize, len);
            }
            break :init table;
        };

        const EMOJI_LENGTHS = blk: {
            var table: [256]u8 = undefined;
            var pos: usize = 0;
            var i: usize = 0;
            while (i < ALPHABET.len) {
                const len = std.unicode.utf8ByteSequenceLength(ALPHABET[i]) catch unreachable;
                table[pos] = len; // Remove @truncate since len is already u8
                pos += 1;
                i += len;
            }
            break :blk table;
        };

        const REVERSE_LOOKUP = blk: {
            @setEvalBranchQuota(10000);
            var table: [0x10FFFF]u8 = [_]u8{0xFF} ** 0x10FFFF;
            var pos: usize = 0;
            var i: usize = 0;
            while (i < ALPHABET.len) {
                const len = (std.unicode.utf8ByteSequenceLength(ALPHABET[i]) catch unreachable);
                const codepoint = std.unicode.utf8Decode(ALPHABET[i..][0..@as(usize, len)]) catch unreachable;
                table[codepoint] = @truncate(pos);
                pos += 1;
                i += @as(usize, len);
            }
            break :blk table;
        };

        pub fn encode(dest: []u8, source: []const u8) []const u8 {
            var dest_index: usize = 0;
            var i: usize = 0;

            // Process 16 bytes at a time
            while (i + 16 <= source.len) : (i += 16) {
                const bytes = @as(Vec, source[i..][0..16].*);
                inline for (0..16) |j| {
                    const byte = bytes[j];
                    const emoji_start = EMOJI_POSITIONS[byte];
                    const emoji_len = EMOJI_LENGTHS[byte];
                    @memcpy(dest[dest_index..][0..emoji_len], ALPHABET[emoji_start..][0..emoji_len]);
                    dest_index += emoji_len;
                }
            }

            // Handle remaining bytes
            while (i < source.len) : (i += 1) {
                const byte = source[i];
                const emoji_start = EMOJI_POSITIONS[byte];
                const emoji_len = EMOJI_LENGTHS[byte];
                @memcpy(dest[dest_index..][0..emoji_len], ALPHABET[emoji_start..][0..emoji_len]);
                dest_index += emoji_len;
            }

            return dest[0..dest_index];
        }

        pub fn decode(dest: []u8, source: []const u8) ![]const u8 {
            var dest_index: usize = 0;
            var i: usize = 0;

            while (i < source.len) {
                const len = @as(usize, std.unicode.utf8ByteSequenceLength(source[i]) catch return ParseError.InvalidBaseString);
                const codepoint = std.unicode.utf8Decode(source[i..][0..len]) catch return ParseError.InvalidBaseString;
                const byte = REVERSE_LOOKUP[codepoint];
                if (byte == 0xFF) return ParseError.InvalidBaseString;
                dest[dest_index] = byte;
                dest_index += 1;
                i += len;
            }

            return dest[0..dest_index];
        }
    };
};

test "Base.encode/decode base2" {
    const testing = std.testing;
    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base2.encode(dest[0..], source);
        try testing.expectEqualStrings("0000000000000000001111001011001010111001100100000011011010110000101101110011010010010000000100001", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "0000000000000000001111001011001010111001100100000011011010110000101101110011010010010000000100001";
        const decoded = try MultiBaseCodec.Base2.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base2.encode(dest[0..], source);
        try testing.expectEqualStrings("00000000001111001011001010111001100100000011011010110000101101110011010010010000000100001", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "00000000001111001011001010111001100100000011011010110000101101110011010010010000000100001";
        const decoded = try MultiBaseCodec.Base2.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base2.encode(dest[0..], source);
        try testing.expectEqualStrings("001111001011001010111001100100000011011010110000101101110011010010010000000100001", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "001111001011001010111001100100000011011010110000101101110011010010010000000100001";
        const decoded = try MultiBaseCodec.Base2.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }
}

test "Base.encode/decode identity" {
    const testing = std.testing;

    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Identity.encode(dest[0..], source);
        try testing.expectEqualStrings("\x00yes mani !", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const decoded = try MultiBaseCodec.Identity.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Identity.encode(dest[0..], source);
        try testing.expectEqualStrings("\x00\x00yes mani !", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const decoded = try MultiBaseCodec.Identity.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Identity.encode(dest[0..], source);
        try testing.expectEqualStrings("\x00\x00\x00yes mani !", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00\x00yes mani !";
        const decoded = try MultiBaseCodec.Identity.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }
}

test "Base.encode/decode base8" {
    const testing = std.testing;
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base8.encode(dest[0..], source);
        try testing.expectEqualStrings("7362625631006654133464440102", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "7362625631006654133464440102";
        const decoded = try MultiBaseCodec.Base8.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base8.encode(dest[0..], source);
        try testing.expectEqualStrings("7000745453462015530267151100204", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "7000745453462015530267151100204";
        const decoded = try MultiBaseCodec.Base8.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base8.encode(dest[0..], source);
        try testing.expectEqualStrings("700000171312714403326055632220041", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "700000171312714403326055632220041";
        const decoded = try MultiBaseCodec.Base8.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }
}

test "Base.encode/decode base10" {
    const testing = std.testing;

    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base10.encode(dest[0..], source);
        try testing.expectEqualStrings("9573277761329450583662625", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "9573277761329450583662625";
        const decoded = try MultiBaseCodec.Base10.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base10.encode(dest[0..], source);
        try testing.expectEqualStrings("90573277761329450583662625", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "90573277761329450583662625";
        const decoded = try MultiBaseCodec.Base10.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base10.encode(dest[0..], source);
        try testing.expectEqualStrings("900573277761329450583662625", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "900573277761329450583662625";
        const decoded = try MultiBaseCodec.Base10.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }
}

test "Base.encode/decode base16" {
    const testing = std.testing;

    // Test Base16Lower
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base16Lower.encode(dest[0..], source);
        try testing.expectEqualStrings("f796573206d616e692021", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "f796573206d616e692021";
        const decoded = try MultiBaseCodec.Base16Lower.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base16Lower.encode(dest[0..], source);
        try testing.expectEqualStrings("f00796573206d616e692021", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "f00796573206d616e692021";
        const decoded = try MultiBaseCodec.Base16Lower.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base16Lower.encode(dest[0..], source);
        try testing.expectEqualStrings("f0000796573206d616e692021", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "f0000796573206d616e692021";
        const decoded = try MultiBaseCodec.Base16Lower.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }

    // Test Base16Upper
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base16Upper.encode(dest[0..], source);
        try testing.expectEqualStrings("F796573206D616E692021", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "F796573206D616E692021";
        const decoded = try MultiBaseCodec.Base16Upper.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base16Upper.encode(dest[0..], source);
        try testing.expectEqualStrings("F00796573206D616E692021", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "F00796573206D616E692021";
        const decoded = try MultiBaseCodec.Base16Upper.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base16Upper.encode(dest[0..], source);
        try testing.expectEqualStrings("F0000796573206D616E692021", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "F0000796573206D616E692021";
        const decoded = try MultiBaseCodec.Base16Upper.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }
}

test "Base.encode base32 lower pad" {
    const testing = std.testing;
    var dest: [257]u8 = undefined;
    const source = "\x00\x00yes mani !\x00\x00yes mani !\x00\x00yes mani !\x00\x00yes mani !\x00\x00yes mani !\x00\x00yes mani !\x00\x00yes mani !\x00\x00yes mani !\x00\x00yes mani !\x00\x00yes mani !\x00\x00yes mani !\x00\x00yes mani !\x00\x00yes mani !";
    const encoded = MultiBaseCodec.Base32PadLower.encode(dest[0..], source);
    try testing.expectEqualStrings("aaahszltebwwc3tjeaqqaadzmvzsa3lbnzusaiiaab4wk4zanvqw42jaeeaaa6lfomqg2yloneqccaaapfsxgidnmfxgsibbaaahszltebwwc3tjeaqqaadzmvzsa3lbnzusaiiaab4wk4zanvqw42jaeeaaa6lfomqg2yloneqccaaapfsxgidnmfxgsibbaaahszltebwwc3tjeaqqaadzmvzsa3lbnzusaiiaab4wk4zanvqw42jaee======", encoded[1..]);
}

test "Base.encode/decode base32" {
    const testing = std.testing;
    // Test Base32Lower
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base32Lower.encode(dest[0..], source);
        try testing.expectEqualStrings("bpfsxgidnmfxgsibb", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "bpfsxgidnmfxgsibb";
        const decoded = try MultiBaseCodec.Base32Lower.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base32Lower.encode(dest[0..], source);
        try testing.expectEqualStrings("bab4wk4zanvqw42jaee", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "bab4wk4zanvqw42jaee";
        const decoded = try MultiBaseCodec.Base32Lower.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base32Lower.encode(dest[0..], source);
        try testing.expectEqualStrings("baaahszltebwwc3tjeaqq", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "baaahszltebwwc3tjeaqq";
        const decoded = try MultiBaseCodec.Base32Lower.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }

    // Test Base32Upper
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base32Upper.encode(dest[0..], source);
        try testing.expectEqualStrings("BPFSXGIDNMFXGSIBB", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "BPFSXGIDNMFXGSIBB";
        const decoded = try MultiBaseCodec.Base32Upper.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base32Upper.encode(dest[0..], source);
        try testing.expectEqualStrings("BAB4WK4ZANVQW42JAEE", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "BAB4WK4ZANVQW42JAEE";
        const decoded = try MultiBaseCodec.Base32Upper.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base32Upper.encode(dest[0..], source);
        try testing.expectEqualStrings("BAAAHSZLTEBWWC3TJEAQQ", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "BAAAHSZLTEBWWC3TJEAQQ";
        const decoded = try MultiBaseCodec.Base32Upper.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }

    // Test Base32HexLower
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base32HexLower.encode(dest[0..], source);
        try testing.expectEqualStrings("vf5in683dc5n6i811", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "vf5in683dc5n6i811";
        const decoded = try MultiBaseCodec.Base32HexLower.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base32HexLower.encode(dest[0..], source);
        try testing.expectEqualStrings("v01smasp0dlgmsq9044", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "v01smasp0dlgmsq9044";
        const decoded = try MultiBaseCodec.Base32HexLower.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base32HexLower.encode(dest[0..], source);
        try testing.expectEqualStrings("v0007ipbj41mm2rj940gg", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "v0007ipbj41mm2rj940gg";
        const decoded = try MultiBaseCodec.Base32HexLower.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }

    // Test Base32HexUpper
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base32HexUpper.encode(dest[0..], source);
        try testing.expectEqualStrings("VF5IN683DC5N6I811", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "VF5IN683DC5N6I811";
        const decoded = try MultiBaseCodec.Base32HexUpper.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base32HexUpper.encode(dest[0..], source);
        try testing.expectEqualStrings("V01SMASP0DLGMSQ9044", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "V01SMASP0DLGMSQ9044";
        const decoded = try MultiBaseCodec.Base32HexUpper.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base32HexUpper.encode(dest[0..], source);
        try testing.expectEqualStrings("V0007IPBJ41MM2RJ940GG", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "V0007IPBJ41MM2RJ940GG";
        const decoded = try MultiBaseCodec.Base32HexUpper.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }

    // Test Base32PadLower
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base32PadLower.encode(dest[0..], source);
        try testing.expectEqualStrings("cpfsxgidnmfxgsibb", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "cpfsxgidnmfxgsibb";
        const decoded = try MultiBaseCodec.Base32PadLower.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base32PadLower.encode(dest[0..], source);
        try testing.expectEqualStrings("cab4wk4zanvqw42jaee======", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "cab4wk4zanvqw42jaee======";
        const decoded = try MultiBaseCodec.Base32PadLower.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base32PadLower.encode(dest[0..], source);
        try testing.expectEqualStrings("caaahszltebwwc3tjeaqq====", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "caaahszltebwwc3tjeaqq====";
        const decoded = try MultiBaseCodec.Base32PadLower.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }

    // Test Base32PadUpper
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base32PadUpper.encode(dest[0..], source);
        try testing.expectEqualStrings("CPFSXGIDNMFXGSIBB", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "CPFSXGIDNMFXGSIBB";
        const decoded = try MultiBaseCodec.Base32PadUpper.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base32PadUpper.encode(dest[0..], source);
        try testing.expectEqualStrings("CAB4WK4ZANVQW42JAEE======", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "CAB4WK4ZANVQW42JAEE======";
        const decoded = try MultiBaseCodec.Base32PadUpper.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base32PadUpper.encode(dest[0..], source);
        try testing.expectEqualStrings("CAAAHSZLTEBWWC3TJEAQQ====", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "CAAAHSZLTEBWWC3TJEAQQ====";
        const decoded = try MultiBaseCodec.Base32PadUpper.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }

    // Test Base32HexPadLower
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base32HexPadLower.encode(dest[0..], source);
        try testing.expectEqualStrings("tf5in683dc5n6i811", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "tf5in683dc5n6i811";
        const decoded = try MultiBaseCodec.Base32HexPadLower.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base32HexPadLower.encode(dest[0..], source);
        try testing.expectEqualStrings("t01smasp0dlgmsq9044======", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "t01smasp0dlgmsq9044======";
        const decoded = try MultiBaseCodec.Base32HexPadLower.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base32HexPadLower.encode(dest[0..], source);
        try testing.expectEqualStrings("t0007ipbj41mm2rj940gg====", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "t0007ipbj41mm2rj940gg====";
        const decoded = try MultiBaseCodec.Base32HexPadLower.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }

    // Test Base32HexPadUpper
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base32HexPadUpper.encode(dest[0..], source);
        try testing.expectEqualStrings("TF5IN683DC5N6I811", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "TF5IN683DC5N6I811";
        const decoded = try MultiBaseCodec.Base32HexPadUpper.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base32HexPadUpper.encode(dest[0..], source);
        try testing.expectEqualStrings("T01SMASP0DLGMSQ9044======", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "T01SMASP0DLGMSQ9044======";
        const decoded = try MultiBaseCodec.Base32HexPadUpper.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base32HexPadUpper.encode(dest[0..], source);
        try testing.expectEqualStrings("T0007IPBJ41MM2RJ940GG====", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "T0007IPBJ41MM2RJ940GG====";
        const decoded = try MultiBaseCodec.Base32HexPadUpper.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }

    // Test Base32Z
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base32Z.encode(dest[0..], source);
        try testing.expectEqualStrings("hxf1zgedpcfzg1ebb", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "hxf1zgedpcfzg1ebb";
        const decoded = try MultiBaseCodec.Base32Z.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base32Z.encode(dest[0..], source);
        try testing.expectEqualStrings("hybhskh3ypiosh4jyrr", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "hybhskh3ypiosh4jyrr";
        const decoded = try MultiBaseCodec.Base32Z.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base32Z.encode(dest[0..], source);
        try testing.expectEqualStrings("hyyy813murbssn5ujryoo", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "hyyy813murbssn5ujryoo";
        const decoded = try MultiBaseCodec.Base32Z.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }
}

test "Base.encode/decode base36" {
    const testing = std.testing;

    // Test Base36Lower
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base36Lower.encode(dest[0..], source);
        try testing.expectEqualStrings("k2lcpzo5yikidynfl", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "k2lcpzo5yikidynfl";
        const decoded = try MultiBaseCodec.Base36Lower.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base36Lower.encode(dest[0..], source);
        try testing.expectEqualStrings("k02lcpzo5yikidynfl", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "k02lcpzo5yikidynfl";
        const decoded = try MultiBaseCodec.Base36Lower.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base36Lower.encode(dest[0..], source);
        try testing.expectEqualStrings("k002lcpzo5yikidynfl", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "k002lcpzo5yikidynfl";
        const decoded = try MultiBaseCodec.Base36Lower.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }

    // Test Base36Upper
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base36Upper.encode(dest[0..], source);
        try testing.expectEqualStrings("K2LCPZO5YIKIDYNFL", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "K2LCPZO5YIKIDYNFL";
        const decoded = try MultiBaseCodec.Base36Upper.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base36Upper.encode(dest[0..], source);
        try testing.expectEqualStrings("K02LCPZO5YIKIDYNFL", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "K02LCPZO5YIKIDYNFL";
        const decoded = try MultiBaseCodec.Base36Upper.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base36Upper.encode(dest[0..], source);
        try testing.expectEqualStrings("K002LCPZO5YIKIDYNFL", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "K002LCPZO5YIKIDYNFL";
        const decoded = try MultiBaseCodec.Base36Upper.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }
}

test "Base.encode/decode base58" {
    const testing = std.testing;

    // Test Base58Btc
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base58Btc.encode(dest[0..], source);
        try testing.expectEqualStrings("z7paNL19xttacUY", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "z7paNL19xttacUY";
        const decoded = try MultiBaseCodec.Base58Btc.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base58Btc.encode(dest[0..], source);
        try testing.expectEqualStrings("z17paNL19xttacUY", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "z17paNL19xttacUY";
        const decoded = try MultiBaseCodec.Base58Btc.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base58Btc.encode(dest[0..], source);
        try testing.expectEqualStrings("z117paNL19xttacUY", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "z117paNL19xttacUY";
        const decoded = try MultiBaseCodec.Base58Btc.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }

    // Test Base58Flickr
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base58Flickr.encode(dest[0..], source);
        try testing.expectEqualStrings("Z7Pznk19XTTzBtx", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "Z7Pznk19XTTzBtx";
        const decoded = try MultiBaseCodec.Base58Flickr.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base58Flickr.encode(dest[0..], source);
        try testing.expectEqualStrings("Z17Pznk19XTTzBtx", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "Z17Pznk19XTTzBtx";
        const decoded = try MultiBaseCodec.Base58Flickr.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base58Flickr.encode(dest[0..], source);
        try testing.expectEqualStrings("Z117Pznk19XTTzBtx", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "Z117Pznk19XTTzBtx";
        const decoded = try MultiBaseCodec.Base58Flickr.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }
}

test "Base.encode/decode base64" {
    const testing = std.testing;

    // Test Base64 standard
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base64.encode(dest[0..], source);
        try testing.expectEqualStrings("meWVzIG1hbmkgIQ", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "meWVzIG1hbmkgIQ";
        const decoded = try MultiBaseCodec.Base64.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base64.encode(dest[0..], source);
        try testing.expectEqualStrings("mAHllcyBtYW5pICE", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "mAHllcyBtYW5pICE";
        const decoded = try MultiBaseCodec.Base64.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base64.encode(dest[0..], source);
        try testing.expectEqualStrings("mAAB5ZXMgbWFuaSAh", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "mAAB5ZXMgbWFuaSAh";
        const decoded = try MultiBaseCodec.Base64.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }

    // Test Base64Pad
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base64Pad.encode(dest[0..], source);
        try testing.expectEqualStrings("MeWVzIG1hbmkgIQ==", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "MeWVzIG1hbmkgIQ==";
        const decoded = try MultiBaseCodec.Base64Pad.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base64Pad.encode(dest[0..], source);
        try testing.expectEqualStrings("MAHllcyBtYW5pICE=", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "MAHllcyBtYW5pICE=";
        const decoded = try MultiBaseCodec.Base64Pad.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base64Pad.encode(dest[0..], source);
        try testing.expectEqualStrings("MAAB5ZXMgbWFuaSAh", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "MAAB5ZXMgbWFuaSAh";
        const decoded = try MultiBaseCodec.Base64Pad.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }

    // Test Base64Url
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base64Url.encode(dest[0..], source);
        try testing.expectEqualStrings("ueWVzIG1hbmkgIQ", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "ueWVzIG1hbmkgIQ";
        const decoded = try MultiBaseCodec.Base64Url.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base64Url.encode(dest[0..], source);
        try testing.expectEqualStrings("uAHllcyBtYW5pICE", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "uAHllcyBtYW5pICE";
        const decoded = try MultiBaseCodec.Base64Url.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base64Url.encode(dest[0..], source);
        try testing.expectEqualStrings("uAAB5ZXMgbWFuaSAh", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "uAAB5ZXMgbWFuaSAh";
        const decoded = try MultiBaseCodec.Base64Url.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }

    // Test Base64UrlPad
    {
        var dest: [256]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base64UrlPad.encode(dest[0..], source);
        try testing.expectEqualStrings("UeWVzIG1hbmkgIQ==", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "UeWVzIG1hbmkgIQ==";
        const decoded = try MultiBaseCodec.Base64UrlPad.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base64UrlPad.encode(dest[0..], source);
        try testing.expectEqualStrings("UAHllcyBtYW5pICE=", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "UAHllcyBtYW5pICE=";
        const decoded = try MultiBaseCodec.Base64UrlPad.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base64UrlPad.encode(dest[0..], source);
        try testing.expectEqualStrings("UAAB5ZXMgbWFuaSAh", encoded);
    }

    {
        var dest: [256]u8 = undefined;
        const source = "UAAB5ZXMgbWFuaSAh";
        const decoded = try MultiBaseCodec.Base64UrlPad.decode(dest[0..], source[1..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }
}

test "Base.encode/decode base256emoji" {
    const testing = std.testing;

    // Test with "yes mani !"
    {
        var dest: [1024]u8 = undefined;
        const source = "yes mani !";
        const encoded = MultiBaseCodec.Base256Emoji.encode(dest[0..], source);
        try testing.expectEqualStrings("🚀🏃✋🌈😅🌷🤤😻🌟😅👏", encoded);
    }

    {
        var dest: [1024]u8 = undefined;
        const source = "🚀🏃✋🌈😅🌷🤤😻🌟😅👏";
        const decoded = try MultiBaseCodec.Base256Emoji.decode(dest[0..], source[4..]);
        try testing.expectEqualStrings("yes mani !", decoded);
    }

    // Test with "\x00yes mani !"
    {
        var dest: [1024]u8 = undefined;
        const source = "\x00yes mani !";
        const encoded = MultiBaseCodec.Base256Emoji.encode(dest[0..], source);
        try testing.expectEqualStrings("🚀🚀🏃✋🌈😅🌷🤤😻🌟😅👏", encoded);
    }

    {
        var dest: [1024]u8 = undefined;
        const source = "🚀🚀🏃✋🌈😅🌷🤤😻🌟😅👏";
        const decoded = try MultiBaseCodec.Base256Emoji.decode(dest[0..], source[4..]);
        try testing.expectEqualStrings("\x00yes mani !", decoded);
    }

    // Test with "\x00\x00yes mani !"
    {
        var dest: [1024]u8 = undefined;
        const source = "\x00\x00yes mani !";
        const encoded = MultiBaseCodec.Base256Emoji.encode(dest[0..], source);
        try testing.expectEqualStrings("🚀🚀🚀🏃✋🌈😅🌷🤤😻🌟😅👏", encoded);
    }

    {
        var dest: [1024]u8 = undefined;
        const source = "🚀🚀🚀🏃✋🌈😅🌷🤤😻🌟😅👏";
        const decoded = try MultiBaseCodec.Base256Emoji.decode(dest[0..], source[4..]);
        try testing.expectEqualStrings("\x00\x00yes mani !", decoded);
    }
}

test "multibase encode/decode" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test basic encoding/decoding
    {
        const input = "hello world";
        const needed_size = MultiBaseCodec.Base58Btc.encodedLen(input);
        const dest = try allocator.alloc(u8, needed_size);
        const encoded = MultiBaseCodec.Base58Btc.encode(dest, input);
        defer allocator.free(dest);
        try testing.expectEqualStrings("zStV1DL6CwTryKyV", encoded);

        const base_codec = try MultiBaseCodec.fromCode(encoded);
        const base_source = encoded[base_codec.codeLength()..];
        const needed_decode_size = base_codec.decodedLen(base_source);
        const dest_decode = try allocator.alloc(u8, needed_decode_size);
        const decoded = try base_codec.decode(dest_decode, base_source);
        defer allocator.free(dest_decode);
        try testing.expectEqual(MultiBaseCodec.Base58Btc, base_codec);
        try testing.expectEqualStrings(input, decoded);
    }

    // Test with different bases
    {
        const input = "Hello World!";

        // Base32
        const needed_size = MultiBaseCodec.Base32Lower.encodedLen(input);
        const dest = try allocator.alloc(u8, needed_size);
        var encoded = MultiBaseCodec.Base32Lower.encode(dest, input);
        defer allocator.free(dest);
        try testing.expectEqualStrings("bjbswy3dpeblw64tmmqqq", encoded);

        var base_codec = try MultiBaseCodec.fromCode(encoded);
        const base_source = encoded[base_codec.codeLength()..];
        const needed_decode_size = base_codec.decodedLen(base_source);
        const dest_decode = try allocator.alloc(u8, needed_decode_size);
        const decoded = try base_codec.decode(dest_decode, base_source);
        defer allocator.free(dest_decode);
        try testing.expectEqual(MultiBaseCodec.Base32Lower, base_codec);
        try testing.expectEqualStrings(input, decoded);

        // Base64
        const needed_size2 = MultiBaseCodec.Base64.encodedLen(input);
        const dest2 = try allocator.alloc(u8, needed_size2);
        var encoded2 = MultiBaseCodec.Base64.encode(dest2, input);
        defer allocator.free(dest2);
        try testing.expectEqualStrings("mSGVsbG8gV29ybGQh", encoded2);

        base_codec = try MultiBaseCodec.fromCode(encoded2);
        const base_source2 = encoded2[base_codec.codeLength()..];
        const needed_decode_size2 = base_codec.decodedLen(base_source2);
        const dest_decode2 = try allocator.alloc(u8, needed_decode_size2);
        const decoded2 = try base_codec.decode(dest_decode2, base_source2);
        defer allocator.free(dest_decode2);
        try testing.expectEqual(MultiBaseCodec.Base64, base_codec);
        try testing.expectEqualStrings(input, decoded2);

        // Base256Emoji
        const needed_size3 = MultiBaseCodec.Base256Emoji.encodedLen(input);
        const dest3 = try allocator.alloc(u8, needed_size3);
        const encoded3 = MultiBaseCodec.Base256Emoji.encode(dest3, input);
        defer allocator.free(dest3);
        try testing.expectEqualStrings("🚀😄✋🍀🍀😓😅😑😓🥺🍀😳👏", encoded3);

        base_codec = try MultiBaseCodec.fromCode(encoded3);
        const base_source3 = encoded3[base_codec.codeLength()..];
        const needed_decode_size3 = base_codec.decodedLen(base_source3);
        const dest_decode3 = try allocator.alloc(u8, needed_decode_size3);
        const decoded3 = try base_codec.decode(dest_decode3, base_source3);
        defer allocator.free(dest_decode3);
        try testing.expectEqual(MultiBaseCodec.Base256Emoji, base_codec);
        try testing.expectEqualStrings(input, decoded3);
    }

    // Test error cases
    {
        const input = "😄✋🍀🍀😓😅😑😓🥺🍀😳👏";
        try testing.expectError(ParseError.InvalidBaseString, MultiBaseCodec.fromCode(input));
    }
}

test "Base36 and Base58 size calculations" {
    const testing = std.testing;

    const test_data = "Hello WorldHello World  Hello World";

    // Base36
    const base36_enc_size = MultiBaseCodec.Base36Upper.encodedLen(test_data);
    const base36_enc_size1 = MultiBaseCodec.Base36Upper.encodedLenBySize(test_data.len);
    try testing.expectEqual(base36_enc_size, base36_enc_size1);

    // Base58
    const base58_enc_size = MultiBaseCodec.Base58Btc.encodedLen(test_data);
    const base58_enc_size1 = MultiBaseCodec.Base58Btc.encodedLenBySize(test_data.len);
    try testing.expectEqual(base58_enc_size, base58_enc_size1);

    // decode size calculation
    const dest = try testing.allocator.alloc(u8, base36_enc_size);
    defer testing.allocator.free(dest);
    const encoded = MultiBaseCodec.Base36Upper.encode(dest, test_data);

    const base36_dec_size2 = MultiBaseCodec.Base36Upper.decodedLenBySize(encoded.len);
    const base36_dec_size = MultiBaseCodec.Base36Upper.decodedLen(encoded);
    try testing.expectEqual(base36_dec_size, base36_dec_size2);

    const dest2 = try testing.allocator.alloc(u8, base58_enc_size);
    defer testing.allocator.free(dest2);
    const encoded2 = MultiBaseCodec.Base58Btc.encode(dest2, test_data);

    const base58_dec_size2 = MultiBaseCodec.Base58Btc.decodedLenBySize(encoded2.len);
    const base58_dec_size = MultiBaseCodec.Base58Btc.decodedLen(encoded2);
    try testing.expectEqual(base58_dec_size, base58_dec_size2);
}

test "Base36Lower encode large data" {
    const testing = std.testing;
    const allocator = std.heap.page_allocator;
    const large_data = try loadTestData(allocator, "./test/data/encode_data");
    defer allocator.free(large_data);
    const encode_comparision_data = try loadTestData(allocator, "./test/data/encoded_result_base36_lower");
    defer allocator.free(encode_comparision_data);

    var dest: [17000]u8 = undefined;
    const encode_result = MultiBaseCodec.Base36Lower.encode(dest[0..], large_data);
    try testing.expectEqual(encode_comparision_data.len, encode_result.len);
    try testing.expectEqualStrings(encode_comparision_data, encode_result);
}

test "Base36Upper encode large data" {
    const testing = std.testing;
    const allocator = std.heap.page_allocator;
    const large_data = try loadTestData(allocator, "./test/data/encode_data");
    defer allocator.free(large_data);
    const encode_comparision_data = try loadTestData(allocator, "./test/data/encoded_result_base36_upper");
    defer allocator.free(encode_comparision_data);

    var dest: [17000]u8 = undefined;
    const encode_result = MultiBaseCodec.Base36Upper.encode(dest[0..], large_data);
    try testing.expectEqual(encode_comparision_data.len, encode_result.len);
    try testing.expectEqualStrings(encode_comparision_data, encode_result);
}

test "Base36Lower decode large data" {
    const testing = std.testing;
    const allocator = std.heap.page_allocator;
    const decode_comparision_data = try loadTestData(allocator, "./test/data/encode_data");
    defer allocator.free(decode_comparision_data);
    const decode_data = try loadTestData(allocator, "./test/data/encoded_result_base36_lower");
    defer allocator.free(decode_data);

    var dest: [17000]u8 = undefined;
    const decode_result = try MultiBaseCodec.Base36Lower.decode(dest[0..], decode_data[1..]);
    try testing.expectEqualStrings(decode_comparision_data, decode_result);
}

test "Base36Upper decode large data" {
    const testing = std.testing;
    const allocator = std.heap.page_allocator;
    const decode_comparision_data = try loadTestData(allocator, "./test/data/encode_data");
    defer allocator.free(decode_comparision_data);
    const decode_data = try loadTestData(allocator, "./test/data/encoded_result_base36_upper");
    defer allocator.free(decode_data);

    var dest: [17500]u8 = undefined;
    const decode_result = try MultiBaseCodec.Base36Upper.decode(dest[0..], decode_data[1..]);
    try testing.expectEqualStrings(decode_comparision_data, decode_result);
}

test "Base58BTC encode large data" {
    const testing = std.testing;
    const allocator = std.heap.page_allocator;
    const large_data = try loadTestData(allocator, "./test/data/encode_data");
    defer allocator.free(large_data);
    const encode_comparision_data = try loadTestData(allocator, "./test/data/encoded_result_base58_btc");
    defer allocator.free(encode_comparision_data);

    var dest: [17000]u8 = undefined;
    const encode_result = MultiBaseCodec.Base58Btc.encode(dest[0..], large_data);
    try testing.expectEqual(encode_comparision_data.len, encode_result.len);
    try testing.expectEqualStrings(encode_comparision_data, encode_result);
}

test "Base58BTC decode large data" {
    const testing = std.testing;
    const allocator = std.heap.page_allocator;
    const decode_comparision_data = try loadTestData(allocator, "./test/data/encode_data");
    defer allocator.free(decode_comparision_data);
    const decode_data = try loadTestData(allocator, "./test/data/encoded_result_base58_btc");
    defer allocator.free(decode_data);

    var dest: [17000]u8 = undefined;
    const decode_result = try MultiBaseCodec.Base58Btc.decode(dest[0..], decode_data[1..]);
    try testing.expectEqualStrings(decode_comparision_data, decode_result);
}
test "Base58Flickr encode large data" {
    const testing = std.testing;
    const allocator = std.heap.page_allocator;
    const large_data = try loadTestData(allocator, "./test/data/encode_data");
    defer allocator.free(large_data);
    const encode_comparision_data = try loadTestData(allocator, "./test/data/encoded_result_base58_flickr");
    defer allocator.free(encode_comparision_data);

    var dest: [17000]u8 = undefined;
    const encode_result = MultiBaseCodec.Base58Flickr.encode(dest[0..], large_data);
    try testing.expectEqual(encode_comparision_data.len, encode_result.len);
    try testing.expectEqualStrings(encode_comparision_data, encode_result);
}

test "Base58Flickr decode large data" {
    const testing = std.testing;
    const allocator = std.heap.page_allocator;
    const decode_comparision_data = try loadTestData(allocator, "./test/data/encode_data");
    defer allocator.free(decode_comparision_data);
    const decode_data = try loadTestData(allocator, "./test/data/encoded_result_base58_flickr");
    defer allocator.free(decode_data);

    var dest: [17000]u8 = undefined;
    const decode_result = try MultiBaseCodec.Base58Flickr.decode(dest[0..], decode_data[1..]);
    try testing.expectEqualStrings(decode_comparision_data, decode_result);
}

fn loadTestData(allocator: std.mem.Allocator, filePath: []const u8) ![]const u8 {
    var file = try std.fs.cwd().openFile(filePath, .{ .mode = std.fs.File.OpenMode.read_only });
    defer file.close();
    const fileSize = try file.getEndPos();
    const buffer = try allocator.alloc(u8, fileSize);
    _ = try file.readAll(buffer);
    const content: []const u8 = buffer;
    return content;
}

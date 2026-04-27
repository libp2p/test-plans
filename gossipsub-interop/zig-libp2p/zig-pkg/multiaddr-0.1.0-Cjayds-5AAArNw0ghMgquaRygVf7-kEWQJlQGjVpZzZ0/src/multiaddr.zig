const std = @import("std");
const testing = std.testing;
const multiformats = @import("multiformats");
const uvarint = multiformats.uvarint;
const PeerId = @import("peer-id").PeerId;

pub const Error = error{
    DataLessThanLen,
    InvalidMultiaddr,
    InvalidProtocolString,
    InvalidUvar,
    ParsingError,
    UnknownProtocolId,
    UnknownProtocolString,
};

// Protocol code constants
const DCCP: u32 = 33;
const DNS: u32 = 53;
const DNS4: u32 = 54;
const DNS6: u32 = 55;
const DNSADDR: u32 = 56;
const HTTP: u32 = 480;
const HTTPS: u32 = 443;
const IP4: u32 = 4;
const IP6: u32 = 41;
const TCP: u32 = 6;
const UDP: u32 = 273;
const UTP: u32 = 302;
const UNIX: u32 = 400;
const P2P: u32 = 421;
const ONION: u32 = 444;
const ONION3: u32 = 445;
const TLS: u32 = 448;
const QUIC: u32 = 460;
const WS: u32 = 477;
const WSS: u32 = 478;
const SCTP: u32 = 132;
const QUIC_V1: u32 = 461;
const P2P_CIRCUIT: u32 = 290;
const WEBTRANSPORT: u32 = 465;

pub const Protocol = union(enum) {
    Dccp: u16,
    Dns: []const u8,
    Dns4: []const u8,
    Dns6: []const u8,
    Dnsaddr: []const u8,
    Http,
    Https,
    Ip4: std.net.Ip4Address,
    Ip6: std.net.Ip6Address,
    Tcp: u16,
    Udp: u16, // Added UDP protocol
    Unix: []const u8,
    Ws,
    Wss,
    Sctp: u16,
    Tls,
    Quic,
    QuicV1,
    P2pCircuit,
    WebTransport,
    P2P: PeerId,

    pub fn tag(self: Protocol) []const u8 {
        return switch (self) {
            .Dccp => "dccp",
            .Dns => "dns",
            .Dns4 => "dns4",
            .Dns6 => "dns6",
            .Dnsaddr => "dnsaddr",
            .Http => "http",
            .Https => "https",
            .Ip4 => "ip4",
            .Ip6 => "ip6",
            .Tcp => "tcp",
            .Udp => "udp",
            .Ws => "ws",
            .Wss => "wss",
            .Unix => "unix",
            .Sctp => "sctp",
            .Tls => "tls",
            .Quic => "quic",
            .QuicV1 => "quic-v1",
            .P2pCircuit => "p2p-circuit",
            .WebTransport => "webtransport",
            .P2P => "p2p",
        };
    }

    pub fn fromBytes(bytes: []const u8) !struct { proto: Protocol, rest: []const u8 } {
        if (bytes.len < 1) return Error.DataLessThanLen;

        const decoded = try uvarint.decode(u32, bytes);
        const id = decoded.value;
        var rest = decoded.remaining;

        return switch (id) {
            IP4 => { // IP4
                if (rest.len < 4) return Error.DataLessThanLen;
                const addr = std.net.Ip4Address.init(rest[0..4].*, 0);
                return .{ .proto = .{ .Ip4 = addr }, .rest = rest[4..] };
            },
            IP6 => { // IP6
                if (rest.len < 16) return Error.DataLessThanLen;
                const addr = std.net.Ip6Address.init(rest[0..16].*, 0, 0, 0);
                return .{ .proto = .{ .Ip6 = addr }, .rest = rest[16..] };
            },
            TCP => { // TCP
                if (rest.len < 2) return Error.DataLessThanLen;
                const port = std.mem.readInt(u16, rest[0..2], .big);
                return .{ .proto = .{ .Tcp = port }, .rest = rest[2..] };
            },
            UDP => { // UDP
                if (rest.len < 2) return Error.DataLessThanLen;
                const port = std.mem.readInt(u16, rest[0..2], .big);
                return .{ .proto = .{ .Udp = port }, .rest = rest[2..] };
            },
            WS => { // WS
                return .{ .proto = .Ws, .rest = rest };
            },
            WSS => { // WSS
                return .{ .proto = .Wss, .rest = rest };
            },
            HTTP => { // HTTP
                return .{ .proto = .Http, .rest = rest };
            },
            HTTPS => { // HTTPS
                return .{ .proto = .Https, .rest = rest };
            },
            DNS => {
                const size_decoded = try uvarint.decode(usize, rest);
                const size = size_decoded.value;
                rest = size_decoded.remaining;
                if (rest.len < size) return Error.DataLessThanLen;
                const dns_name = rest[0..size];
                return .{
                    .proto = .{ .Dns = dns_name },
                    .rest = rest[size..],
                };
            },
            UNIX => { // UNIX
                const size_decoded = try uvarint.decode(usize, rest);
                const size = size_decoded.value;
                rest = size_decoded.remaining;
                if (rest.len < size) return Error.DataLessThanLen;
                const path = rest[0..size];
                return .{
                    .proto = .{ .Unix = path },
                    .rest = rest[size..],
                };
            },
            DNS4 => {
                const size_decoded = try uvarint.decode(usize, rest);
                const size = size_decoded.value;
                rest = size_decoded.remaining;
                if (rest.len < size) return Error.DataLessThanLen;
                const dns_name = rest[0..size];
                return .{ .proto = .{ .Dns4 = dns_name }, .rest = rest[size..] };
            },
            DNS6 => {
                const size_decoded = try uvarint.decode(usize, rest);
                const size = size_decoded.value;
                rest = size_decoded.remaining;
                if (rest.len < size) return Error.DataLessThanLen;
                const dns_name = rest[0..size];
                return .{ .proto = .{ .Dns6 = dns_name }, .rest = rest[size..] };
            },
            DNSADDR => {
                const size_decoded = try uvarint.decode(usize, rest);
                const size = size_decoded.value;
                rest = size_decoded.remaining;
                if (rest.len < size) return Error.DataLessThanLen;
                const dns_name = rest[0..size];
                return .{ .proto = .{ .Dnsaddr = dns_name }, .rest = rest[size..] };
            },
            DCCP => {
                if (rest.len < 2) return Error.DataLessThanLen;
                const port = std.mem.readInt(u16, rest[0..2], .big);
                return .{ .proto = .{ .Dccp = port }, .rest = rest[2..] };
            },
            SCTP => {
                if (rest.len < 2) return Error.DataLessThanLen;
                const port = std.mem.readInt(u16, rest[0..2], .big);
                return .{ .proto = .{ .Sctp = port }, .rest = rest[2..] };
            },
            QUIC => return .{ .proto = .Quic, .rest = rest },
            QUIC_V1 => return .{ .proto = .QuicV1, .rest = rest },
            P2P_CIRCUIT => return .{ .proto = .P2pCircuit, .rest = rest },
            WEBTRANSPORT => return .{ .proto = .WebTransport, .rest = rest },
            TLS => return .{ .proto = .Tls, .rest = rest },
            P2P => {
                const size_decoded = try uvarint.decode(usize, rest);
                const size = size_decoded.value;
                rest = size_decoded.remaining;
                if (rest.len < size) return Error.DataLessThanLen;
                const peer_id = try PeerId.fromBytes(rest[0..size]);
                return .{ .proto = .{ .P2P = peer_id }, .rest = rest[size..] };
            },
            else => Error.UnknownProtocolId,
        };
    }

    pub fn writeBytes(self: Protocol, writer: anytype) !void {
        switch (self) {
            .Ip4 => |addr| {
                _ = try uvarint.encodeStream(writer, u32, IP4);
                const bytes = std.mem.asBytes(&addr.sa.addr);
                try writer.writeAll(bytes);
            },
            .Ip6 => |addr| {
                _ = try uvarint.encodeStream(writer, u32, IP6);
                const bytes = std.mem.asBytes(&addr.sa.addr);
                try writer.writeAll(bytes);
            },
            .Tcp => |port| {
                _ = try uvarint.encodeStream(writer, u32, TCP);
                var port_bytes: [2]u8 = undefined;
                std.mem.writeInt(u16, &port_bytes, port, .big);
                try writer.writeAll(&port_bytes);
            },
            .Udp => |port| {
                _ = try uvarint.encodeStream(writer, u32, UDP);
                var port_bytes: [2]u8 = undefined;
                std.mem.writeInt(u16, &port_bytes, port, .big);
                try writer.writeAll(&port_bytes);
            },
            .Ws => {
                _ = try uvarint.encodeStream(writer, u32, WS);
            },
            .Wss => {
                _ = try uvarint.encodeStream(writer, u32, WSS);
            },
            .Dns => |name| {
                _ = try uvarint.encodeStream(writer, u32, DNS);
                _ = try uvarint.encodeStream(writer, usize, name.len);
                try writer.writeAll(name);
            },
            .Unix => |path| {
                _ = try uvarint.encodeStream(writer, u32, UNIX);
                _ = try uvarint.encodeStream(writer, usize, path.len);
                try writer.writeAll(path);
            },
            .Http => {
                _ = try uvarint.encodeStream(writer, u32, HTTP);
            },
            .Https => {
                _ = try uvarint.encodeStream(writer, u32, HTTPS);
            },
            .Dns4 => |name| {
                _ = try uvarint.encodeStream(writer, u32, DNS4);
                _ = try uvarint.encodeStream(writer, usize, name.len);
                try writer.writeAll(name);
            },
            .Dns6 => |name| {
                _ = try uvarint.encodeStream(writer, u32, DNS6);
                _ = try uvarint.encodeStream(writer, usize, name.len);
                try writer.writeAll(name);
            },
            .Dnsaddr => |name| {
                _ = try uvarint.encodeStream(writer, u32, DNSADDR);
                _ = try uvarint.encodeStream(writer, usize, name.len);
                try writer.writeAll(name);
            },
            .Dccp => |port| {
                _ = try uvarint.encodeStream(writer, u32, DCCP);
                var port_bytes: [2]u8 = undefined;
                std.mem.writeInt(u16, &port_bytes, port, .big);
                try writer.writeAll(&port_bytes);
            },
            .Sctp => |port| {
                _ = try uvarint.encodeStream(writer, u32, SCTP);
                var port_bytes: [2]u8 = undefined;
                std.mem.writeInt(u16, &port_bytes, port, .big);
                try writer.writeAll(&port_bytes);
            },
            .Tls => {
                _ = try uvarint.encodeStream(writer, u32, TLS);
            },
            .Quic => {
                _ = try uvarint.encodeStream(writer, u32, QUIC);
            },
            .QuicV1 => {
                _ = try uvarint.encodeStream(writer, u32, QUIC_V1);
            },
            .P2pCircuit => {
                _ = try uvarint.encodeStream(writer, u32, P2P_CIRCUIT);
            },
            .WebTransport => {
                _ = try uvarint.encodeStream(writer, u32, WEBTRANSPORT);
            },
            .P2P => |peer_id| {
                _ = try uvarint.encodeStream(writer, u32, P2P);
                var bytes_buffer: [128]u8 = undefined;
                const bytes = try peer_id.toBytes(&bytes_buffer);
                _ = try uvarint.encodeStream(writer, usize, bytes.len);
                try writer.writeAll(bytes);
            },
        }
    }
};

pub const Onion3Addr = struct {
    hash: [35]u8,
    port: u16,

    pub fn init(hash: [35]u8, port: u16) Onion3Addr {
        return .{
            .hash = hash,
            .port = port,
        };
    }
};

pub const Multiaddr = struct {
    bytes: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Multiaddr {
        return .{
            .bytes = .{},
            .allocator = allocator,
        };
    }

    pub fn withCapacity(allocator: std.mem.Allocator, capacity: usize) Multiaddr {
        var ma = Multiaddr.init(allocator);
        ma.bytes.ensureTotalCapacity(allocator, capacity) catch unreachable;
        return ma;
    }

    // Create from slice of protocols
    pub fn fromProtocols(allocator: std.mem.Allocator, protocols: []const Protocol) !Multiaddr {
        var ma = Multiaddr.init(allocator);
        for (protocols) |p| {
            try ma.push(p);
        }
        return ma;
    }

    pub fn deinit(self: *const Multiaddr) void {
        var bytes = self.bytes;
        bytes.deinit(self.allocator);
    }

    pub fn iterator(self: Multiaddr) ProtocolIterator {
        return .{ .bytes = self.bytes.items };
    }

    pub fn protocolStack(self: Multiaddr) ProtocolStackIterator {
        return .{ .iter = self.iterator() };
    }

    pub fn with(self: Multiaddr, allocator: std.mem.Allocator, p: Protocol) !Multiaddr {
        var new_ma = Multiaddr.init(allocator);
        try new_ma.bytes.appendSlice(allocator, self.bytes.items);
        try new_ma.push(p);
        return new_ma;
    }

    // Add PeerId if not present at end
    pub fn withP2p(self: Multiaddr, allocator: std.mem.Allocator, peer_id: PeerId) !Multiaddr {
        var iter = self.iterator();
        if (try iter.last()) |last| {
            if (last == .P2P) {
                if (last.P2P.eql(&peer_id)) {
                    return self;
                }
                return error.DifferentPeerId;
            }
        }
        return try self.with(allocator, .{ .P2P = peer_id });
    }

    pub fn len(self: Multiaddr) usize {
        return self.bytes.items.len;
    }

    pub fn isEmpty(self: Multiaddr) bool {
        return self.bytes.items.len == 0;
    }

    pub fn toSlice(self: Multiaddr) []const u8 {
        return self.bytes.items;
    }

    pub fn startsWith(self: Multiaddr, other: Multiaddr) bool {
        if (self.bytes.items.len < other.bytes.items.len) return false;
        return std.mem.eql(u8, self.bytes.items[0..other.bytes.items.len], other.bytes.items);
    }

    pub fn endsWith(self: Multiaddr, other: Multiaddr) bool {
        if (self.bytes.items.len < other.bytes.items.len) return false;
        const start = self.bytes.items.len - other.bytes.items.len;
        return std.mem.eql(u8, self.bytes.items[start..], other.bytes.items);
    }

    pub fn push(self: *Multiaddr, p: Protocol) !void {
        try p.writeBytes(self.bytes.writer(self.allocator));
    }

    pub fn pop(self: *Multiaddr) !?Protocol {
        if (self.bytes.items.len == 0) return null;

        // Find the start of the last protocol
        var offset: usize = 0;
        var last_start: usize = 0;
        var rest: []const u8 = self.bytes.items;

        while (rest.len > 0) {
            const decoded = try Protocol.fromBytes(rest);
            if (decoded.rest.len == 0) {
                // This is the last protocol
                const result = decoded.proto;
                self.bytes.shrinkRetainingCapacity(last_start);
                return result;
            }
            last_start = offset + (rest.len - decoded.rest.len);
            offset += rest.len - decoded.rest.len;
            rest = decoded.rest;
        }

        return Error.InvalidMultiaddr;
    }

    pub fn fromUrl(allocator: std.mem.Allocator, url_str: []const u8) !Multiaddr {
        var ma = Multiaddr.init(allocator);
        errdefer ma.deinit();

        const uri = std.Uri.parse(url_str) catch |err| switch (err) {
            error.InvalidFormat => return FromUrlError.BadUrl,
            else => return err,
        };

        const path = switch (uri.path) {
            .raw => |raw| raw,
            .percent_encoded => |encoded| encoded,
        };

        // Skip path check for Unix sockets
        if (!std.mem.eql(u8, uri.scheme, "unix") and
            (uri.user != null or
                uri.password != null or
                (path.len > 0 and !std.mem.eql(u8, path, "/")) or
                uri.query != null or
                uri.fragment != null))
        {
            return FromUrlError.InformationLoss;
        }

        // Handle different schemes
        if (std.mem.eql(u8, uri.scheme, "ws") or std.mem.eql(u8, uri.scheme, "wss")) {
            try handleWebsocketUrl(&ma, uri);
        } else if (std.mem.eql(u8, uri.scheme, "http") or std.mem.eql(u8, uri.scheme, "https")) {
            try handleHttpUrl(&ma, uri);
        } else if (std.mem.eql(u8, uri.scheme, "unix")) {
            try handleUnixUrl(&ma, uri);
        } else {
            return FromUrlError.UnsupportedScheme;
        }

        return ma;
    }

    pub fn fromUrlLossy(allocator: std.mem.Allocator, url_str: []const u8) !Multiaddr {
        var ma = Multiaddr.init(allocator);
        errdefer ma.deinit();

        const uri = std.Uri.parse(url_str) catch |err| switch (err) {
            error.InvalidFormat => return FromUrlError.BadUrl,
            else => return err,
        };

        // Handle different schemes without checking for information loss
        if (std.mem.eql(u8, uri.scheme, "ws") or std.mem.eql(u8, uri.scheme, "wss")) {
            try handleWebsocketUrl(&ma, uri);
        } else if (std.mem.eql(u8, uri.scheme, "http") or std.mem.eql(u8, uri.scheme, "https")) {
            try handleHttpUrl(&ma, uri);
        } else if (std.mem.eql(u8, uri.scheme, "unix")) {
            try handleUnixUrl(&ma, uri);
        } else {
            return FromUrlError.UnsupportedScheme;
        }

        return ma;
    }

    fn handleWebsocketUrl(ma: *Multiaddr, uri: std.Uri) !void {
        if (uri.host) |host_component| {
            const host = switch (host_component) {
                .raw => |raw| raw,
                .percent_encoded => |encoded| encoded,
            };

            if (std.net.Address.parseIp(host, 0)) |ip| {
                if (ip.any.family == std.posix.AF.INET) {
                    const addr = @as([4]u8, @bitCast(ip.in.sa.addr));
                    try ma.push(.{ .Ip4 = std.net.Ip4Address.init(addr, 0) });
                } else if (ip.any.family == std.posix.AF.INET6) {
                    const addr = @as([16]u8, @bitCast(ip.in6.sa.addr));
                    try ma.push(.{ .Ip6 = std.net.Ip6Address.init(addr, 0, 0, 0) });
                }
            } else |_| {
                try ma.push(.{ .Dns = host });
            }
        }

        const port = uri.port orelse if (std.mem.eql(u8, uri.scheme, "ws")) @as(u16, 80) else @as(u16, 443);
        try ma.push(.{ .Tcp = port });

        if (std.mem.eql(u8, uri.scheme, "ws")) {
            try ma.push(.Ws);
        } else {
            try ma.push(.Wss);
        }
    }

    fn handleHttpUrl(ma: *Multiaddr, uri: std.Uri) !void {
        if (uri.host) |host_component| {
            const host = switch (host_component) {
                .raw => |raw| raw,
                .percent_encoded => |encoded| encoded,
            };

            if (std.net.Address.parseIp(host, 0)) |ip| {
                if (ip.any.family == std.posix.AF.INET) {
                    const addr = @as([4]u8, @bitCast(ip.in.sa.addr));
                    try ma.push(.{ .Ip4 = std.net.Ip4Address.init(addr, 0) });
                } else if (ip.any.family == std.posix.AF.INET6) {
                    const addr = @as([16]u8, @bitCast(ip.in6.sa.addr));
                    try ma.push(.{ .Ip6 = std.net.Ip6Address.init(addr, 0, 0, 0) });
                }
            } else |_| {
                try ma.push(.{ .Dns = host });
            }
        }

        const port = uri.port orelse if (std.mem.eql(u8, uri.scheme, "http")) @as(u16, 80) else @as(u16, 443);
        try ma.push(.{ .Tcp = port });

        if (std.mem.eql(u8, uri.scheme, "http")) {
            try ma.push(.Http);
        } else {
            try ma.push(.Https);
        }
    }

    fn handleUnixUrl(ma: *Multiaddr, uri: std.Uri) !void {
        const path = switch (uri.path) {
            .raw => |raw| raw,
            .percent_encoded => |encoded| encoded,
        };
        try ma.push(.{ .Unix = path });
    }

    pub fn replace(self: Multiaddr, allocator: std.mem.Allocator, at: usize, new_proto: Protocol) !?Multiaddr {
        var new_ma = Multiaddr.init(allocator);
        errdefer new_ma.deinit();

        var count: usize = 0;
        var replaced = false;

        var iter = self.iterator();
        while (try iter.next()) |p| {
            if (count == at) {
                try new_ma.push(new_proto);
                replaced = true;
            } else {
                try new_ma.push(p);
            }
            count += 1;
        }

        if (!replaced) {
            new_ma.deinit();
            return null;
        }
        return new_ma;
    }

    pub fn toString(self: Multiaddr, allocator: std.mem.Allocator) ![]u8 {
        var result: std.ArrayList(u8) = .{};
        errdefer result.deinit(allocator);

        var rest_bytes: []const u8 = self.bytes.items;
        while (rest_bytes.len > 0) {
            const decoded = try Protocol.fromBytes(rest_bytes);
            switch (decoded.proto) {
                .Ip4 => |addr| {
                    const bytes = @as([4]u8, @bitCast(addr.sa.addr));
                    try result.writer(allocator).print("/ip4/{}.{}.{}.{}", .{ bytes[0], bytes[1], bytes[2], bytes[3] });
                },
                .Ip6 => |addr| {
                    const bytes = @as([16]u8, @bitCast(addr.sa.addr));
                    try result.writer(allocator).print("/ip6/{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}", .{
                        bytes[0],  bytes[1],  bytes[2],  bytes[3],
                        bytes[4],  bytes[5],  bytes[6],  bytes[7],
                        bytes[8],  bytes[9],  bytes[10], bytes[11],
                        bytes[12], bytes[13], bytes[14], bytes[15],
                    });
                },
                .Tcp => |port| try result.writer(allocator).print("/tcp/{}", .{port}),
                .Udp => |port| try result.writer(allocator).print("/udp/{}", .{port}),
                .Ws => try result.writer(allocator).print("/ws", .{}),
                .Wss => try result.writer(allocator).print("/wss", .{}),
                .Http => try result.writer(allocator).print("/http", .{}),
                .Https => try result.writer(allocator).print("/https", .{}),
                .Dns => |host| try result.writer(allocator).print("/dns/{s}", .{host}),
                .Unix => |path| try result.writer(allocator).print("/unix/{s}", .{path}),
                .Dns4 => |host| try result.writer(allocator).print("/dns4/{s}", .{host}),
                .Dns6 => |host| try result.writer(allocator).print("/dns6/{s}", .{host}),
                .Dnsaddr => |host| try result.writer(allocator).print("/dnsaddr/{s}", .{host}),
                .Dccp => |port| try result.writer(allocator).print("/dccp/{}", .{port}),
                .Sctp => |port| try result.writer(allocator).print("/sctp/{}", .{port}),
                .Tls => try result.writer(allocator).print("/tls", .{}),
                .Quic => try result.writer(allocator).print("/quic", .{}),
                .QuicV1 => try result.writer(allocator).print("/quic-v1", .{}),
                .P2pCircuit => try result.writer(allocator).print("/p2p-circuit", .{}),
                .WebTransport => try result.writer(allocator).print("/webtransport", .{}),
                .P2P => |peer_id| {
                    const peerid_len = peer_id.toBase58Len();
                    const buffer = try allocator.alloc(u8, peerid_len);
                    defer allocator.free(buffer);
                    const bytes = try peer_id.toBase58(buffer);
                    try result.writer(allocator).print("/p2p/{s}", .{bytes});
                },
            }
            rest_bytes = decoded.rest;
        }

        return result.toOwnedSlice(allocator);
    }

    pub fn fromString(allocator: std.mem.Allocator, s: []const u8) !Multiaddr {
        var ma = Multiaddr.init(allocator);
        errdefer ma.deinit();

        var parts = std.mem.splitScalar(u8, s, '/');
        const first = parts.first();
        if (first.len != 0) return Error.InvalidMultiaddr;

        while (parts.next()) |part| {
            if (part.len == 0) continue;

            const proto = try parseProtocol(allocator, &parts, part);
            try ma.push(proto);
        }

        return ma;
    }

    fn parseProtocol(allocator: std.mem.Allocator, parts: *std.mem.SplitIterator(u8, .scalar), proto_name: []const u8) !Protocol {
        return switch (std.meta.stringToEnum(enum { ip4, tcp, udp, dns, dns4, dns6, http, https, ws, wss, p2p, unix, quic, @"quic-v1", tls }, proto_name) orelse return Error.UnknownProtocolString) {
            .ip4 => blk: {
                const addr_str = parts.next() orelse return Error.InvalidProtocolString;
                var addr: [4]u8 = undefined;
                try parseIp4(addr_str, &addr);
                break :blk Protocol{ .Ip4 = std.net.Ip4Address.init(addr, 0) };
            },
            .tcp, .udp => blk: {
                const port_str = parts.next() orelse return Error.InvalidProtocolString;
                const port = try std.fmt.parseInt(u16, port_str, 10);
                break :blk if (proto_name[0] == 't')
                    Protocol{ .Tcp = port }
                else
                    Protocol{ .Udp = port };
            },
            .dns => blk: {
                const host = parts.next() orelse return Error.InvalidProtocolString;
                break :blk Protocol{ .Dns = host };
            },
            .dns4 => blk: {
                const host = parts.next() orelse return Error.InvalidProtocolString;
                break :blk Protocol{ .Dns4 = host };
            },
            .dns6 => blk: {
                const host = parts.next() orelse return Error.InvalidProtocolString;
                break :blk Protocol{ .Dns6 = host };
            },
            .p2p => blk: {
                const peer_id_str = parts.next() orelse return Error.InvalidProtocolString;
                const peer_id = try PeerId.fromString(allocator, peer_id_str);
                break :blk Protocol{ .P2P = peer_id };
            },
            .quic => Protocol.Quic,
            .@"quic-v1" => Protocol.QuicV1,
            .tls => Protocol.Tls,
            // Add other protocol parsing as needed
            else => Error.UnknownProtocolString,
        };
    }

    fn parseIp4(s: []const u8, out: *[4]u8) !void {
        var it = std.mem.splitScalar(u8, s, '.');
        var i: usize = 0;
        while (it.next()) |num_str| : (i += 1) {
            if (i >= 4) return Error.InvalidProtocolString;
            out[i] = try std.fmt.parseInt(u8, num_str, 10);
        }
        if (i != 4) return Error.InvalidProtocolString;
    }
};

test "multiaddr push and pop" {
    var ma = Multiaddr.init(testing.allocator);
    defer ma.deinit();

    const ip4 = Protocol{ .Ip4 = std.net.Ip4Address.init([4]u8{ 127, 0, 0, 1 }, 0) };
    const tcp = Protocol{ .Tcp = 8080 };

    try ma.push(ip4);
    std.debug.print("\nAfter IP4 push, buffer: ", .{});
    for (ma.bytes.items) |b| {
        std.debug.print("{x:0>2} ", .{b});
    }

    try ma.push(tcp);
    std.debug.print("\nAfter TCP push, buffer: ", .{});
    for (ma.bytes.items) |b| {
        std.debug.print("{x:0>2} ", .{b});
    }

    const popped_tcp = try ma.pop();
    std.debug.print("\nAfter TCP pop, buffer: ", .{});
    for (ma.bytes.items) |b| {
        std.debug.print("{x:0>2} ", .{b});
    }
    std.debug.print("\nPopped TCP: {any}", .{popped_tcp});

    const popped_ip4 = try ma.pop();
    std.debug.print("\nAfter IP4 pop, buffer: ", .{});
    for (ma.bytes.items) |b| {
        std.debug.print("{x:0>2} ", .{b});
    }
    std.debug.print("\nPopped IP4: {any}", .{popped_ip4});

    try testing.expectEqual(tcp, popped_tcp.?);
    try testing.expectEqual(ip4, popped_ip4.?);
    try testing.expectEqual(@as(?Protocol, null), try ma.pop());
}

test "basic multiaddr creation" {
    var ma = Multiaddr.init(testing.allocator);
    defer ma.deinit();

    try testing.expect(ma.bytes.items.len == 0);
}

test "onion3addr basics" {
    const hash = [_]u8{1} ** 35;
    const addr = Onion3Addr.init(hash, 1234);

    try testing.expectEqual(@as(u16, 1234), addr.port);
    try testing.expectEqualSlices(u8, &hash, &addr.hash);
}

test "multiaddr empty" {
    var ma = Multiaddr.init(testing.allocator);
    defer ma.deinit();

    try testing.expect(ma.bytes.items.len == 0);
}

test "protocol encoding/decoding" {
    var buf: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const ip4 = Protocol{ .Ip4 = std.net.Ip4Address.init([4]u8{ 127, 0, 0, 1 }, 0) };
    try ip4.writeBytes(writer);

    const decoded = try Protocol.fromBytes(fbs.getWritten());
    try testing.expect(decoded.proto == .Ip4);
}

test "multiaddr from string" {
    const cases = .{
        "/ip4/127.0.0.1/tcp/8080",
        "/ip4/127.0.0.1",
        "/tcp/8080",
        "/ip4/198.51.100.0/tcp/4242/p2p/QmYyQSo1c1Ym7orWxLYvCrM2EmxFTANf8wXmmE7DWjhx5N",
        "/dns/example.com",
        "/dns4/example.com",
        "/dns6/example.com",
        "/tls",
        "/quic",
        "/quic-v1",
    };

    inline for (cases) |case| {
        var ma = try Multiaddr.fromString(testing.allocator, case);
        defer ma.deinit();

        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);

        try testing.expectEqualStrings(case, str);
    }
}

test "multiaddr basic operations" {
    var ma = Multiaddr.init(testing.allocator);
    defer ma.deinit();
    try testing.expect(ma.isEmpty());
    try testing.expectEqual(@as(usize, 0), ma.len());

    var ma_cap = Multiaddr.withCapacity(testing.allocator, 32);
    defer ma_cap.deinit();
    try testing.expect(ma_cap.isEmpty());

    const ip4 = Protocol{ .Ip4 = std.net.Ip4Address.init([4]u8{ 127, 0, 0, 1 }, 0) };
    try ma_cap.push(ip4);
    try testing.expect(!ma_cap.isEmpty());

    const vec = ma_cap.toSlice();
    try testing.expectEqualSlices(u8, ma_cap.bytes.items, vec);
}

test "multiaddr starts and ends with" {
    var ma1 = Multiaddr.init(testing.allocator);
    defer ma1.deinit();
    var ma2 = Multiaddr.init(testing.allocator);
    defer ma2.deinit();

    const ip4 = Protocol{ .Ip4 = std.net.Ip4Address.init([4]u8{ 127, 0, 0, 1 }, 0) };
    const tcp = Protocol{ .Tcp = 8080 };

    try ma1.push(ip4);
    try ma1.push(tcp);
    try ma2.push(ip4);

    try testing.expect(ma1.startsWith(ma2));
    try ma2.push(tcp);
    try testing.expect(ma1.endsWith(ma2));
}

test "protocol tag strings" {
    const p1 = Protocol{ .Dccp = 1234 };
    try testing.expectEqualStrings("Dccp", @tagName(@as(@TypeOf(p1), p1)));

    const p2 = Protocol.Http;
    try testing.expectEqualStrings("Http", @tagName(@as(@TypeOf(p2), p2)));
}

// Iterator over protocols
pub const ProtocolIterator = struct {
    bytes: []const u8,

    pub fn next(self: *ProtocolIterator) !?Protocol {
        if (self.bytes.len == 0) return null;
        const decoded = try Protocol.fromBytes(self.bytes);
        self.bytes = decoded.rest;
        return decoded.proto;
    }

    pub fn last(self: *ProtocolIterator) !?Protocol {
        if (self.bytes.len == 0) return null;

        // Find the last protocol by iterating to the end
        var last_proto: ?Protocol = null;
        while (self.bytes.len > 0) {
            const decoded = try Protocol.fromBytes(self.bytes);
            last_proto = decoded.proto;
            self.bytes = decoded.rest;
        }
        return last_proto;
    }
};

test "multiaddr iterator" {
    var ma = Multiaddr.init(testing.allocator);
    defer ma.deinit();

    const ip4 = Protocol{ .Ip4 = std.net.Ip4Address.init([4]u8{ 127, 0, 0, 1 }, 0) };
    const tcp = Protocol{ .Tcp = 8080 };
    try ma.push(ip4);
    try ma.push(tcp);

    var iter = ma.iterator();
    const first = try iter.next();
    try testing.expect(first != null);
    try testing.expectEqual(ip4, first.?);

    const second = try iter.next();
    try testing.expect(second != null);
    try testing.expectEqual(tcp, second.?);

    try testing.expectEqual(@as(?Protocol, null), try iter.next());
}

test "multiaddr with" {
    var ma = Multiaddr.init(testing.allocator);
    defer ma.deinit();

    const ip4 = Protocol{ .Ip4 = std.net.Ip4Address.init([4]u8{ 127, 0, 0, 1 }, 0) };
    const tcp = Protocol{ .Tcp = 8080 };

    var ma2 = try ma.with(testing.allocator, ip4);
    defer ma2.deinit();
    var ma3 = try ma2.with(testing.allocator, tcp);
    defer ma3.deinit();

    var iter = ma3.iterator();
    try testing.expectEqual(ip4, (try iter.next()).?);
    try testing.expectEqual(tcp, (try iter.next()).?);
}

pub const ProtocolStackIterator = struct {
    iter: ProtocolIterator,

    pub fn next(self: *ProtocolStackIterator) !?[]const u8 {
        if (try self.iter.next()) |proto| {
            return proto.tag();
        }
        return null;
    }
};

test "multiaddr protocol stack" {
    var ma = Multiaddr.init(testing.allocator);
    defer ma.deinit();

    const ip4 = Protocol{ .Ip4 = std.net.Ip4Address.init([4]u8{ 127, 0, 0, 1 }, 0) };
    const tcp = Protocol{ .Tcp = 8080 };
    try ma.push(ip4);
    try ma.push(tcp);

    var stack = ma.protocolStack();
    const first = try stack.next();
    try testing.expect(first != null);
    try testing.expectEqualStrings("ip4", first.?);

    const second = try stack.next();
    try testing.expect(second != null);
    try testing.expectEqualStrings("tcp", second.?);

    try testing.expectEqual(@as(?[]const u8, null), try stack.next());
}

test "multiaddr as bytes" {
    var ma = Multiaddr.init(testing.allocator);
    defer ma.deinit();

    const ip4 = Protocol{ .Ip4 = std.net.Ip4Address.init([4]u8{ 127, 0, 0, 1 }, 0) };
    const tcp = Protocol{ .Tcp = 8080 };
    try ma.push(ip4);
    try ma.push(tcp);

    const bytes = ma.toSlice();
    try testing.expectEqualSlices(u8, ma.bytes.items, bytes);
}

test "multiaddr from protocols" {
    const protocols = [_]Protocol{
        .{ .Ip4 = std.net.Ip4Address.init([4]u8{ 127, 0, 0, 1 }, 0) },
        .{ .Tcp = 8080 },
    };

    var ma = try Multiaddr.fromProtocols(testing.allocator, &protocols);
    defer ma.deinit();

    var iter = ma.iterator();
    try testing.expectEqual(protocols[0], (try iter.next()).?);
    try testing.expectEqual(protocols[1], (try iter.next()).?);
    try testing.expectEqual(@as(?Protocol, null), try iter.next());
}

test "multiaddr replace" {
    var ma = Multiaddr.init(testing.allocator);
    defer ma.deinit();

    const ip4 = Protocol{ .Ip4 = std.net.Ip4Address.init([4]u8{ 127, 0, 0, 1 }, 0) };
    const tcp = Protocol{ .Tcp = 8080 };
    const new_tcp = Protocol{ .Tcp = 9090 };

    try ma.push(ip4);
    try ma.push(tcp);

    // Replace TCP port
    if (try ma.replace(testing.allocator, 1, new_tcp)) |*replaced| {
        defer replaced.deinit();
        var iter = replaced.iterator();
        try testing.expectEqual(ip4, (try iter.next()).?);
        try testing.expectEqual(new_tcp, (try iter.next()).?);
    } else {
        try testing.expect(false);
    }

    // Try replace at invalid index
    if (try ma.replace(testing.allocator, 5, new_tcp)) |*replaced| {
        defer replaced.deinit();
        try testing.expect(false);
    }
}

test "multiaddr deinit mutable and const" {
    // Test mutable instance
    var ma_mut = Multiaddr.init(testing.allocator);
    const ip4 = Protocol{ .Ip4 = std.net.Ip4Address.init([4]u8{ 127, 0, 0, 1 }, 0) };
    try ma_mut.push(ip4);
    ma_mut.deinit();

    // Test const instance
    var ma = Multiaddr.init(testing.allocator);
    try ma.push(ip4);
    const ma_const = ma;
    ma_const.deinit();
}

pub const FromUrlError = error{
    BadUrl,
    UnsupportedScheme,
    InformationLoss,
};

test "multiaddr from url - websocket" {
    // Test ws://
    {
        var ma = try Multiaddr.fromUrl(testing.allocator, "ws://127.0.0.1:8000");
        defer ma.deinit();
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/ip4/127.0.0.1/tcp/8000/ws", str);
    }

    // Test wss:// with default port
    {
        var ma = try Multiaddr.fromUrl(testing.allocator, "wss://127.0.0.1");
        defer ma.deinit();
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/ip4/127.0.0.1/tcp/443/wss", str);
    }

    // Test with DNS hostname
    {
        var ma = try Multiaddr.fromUrl(testing.allocator, "wss://example.com");
        defer ma.deinit();
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/dns/example.com/tcp/443/wss", str);
    }
}

test "multiaddr from url - http" {
    // Test http://
    {
        var ma = try Multiaddr.fromUrl(testing.allocator, "http://127.0.0.1:8080");
        defer ma.deinit();
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/ip4/127.0.0.1/tcp/8080/http", str);
    }

    // Test https:// with DNS
    {
        var ma = try Multiaddr.fromUrl(testing.allocator, "https://example.com");
        defer ma.deinit();
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/dns/example.com/tcp/443/https", str);
    }
}

test "multiaddr from url - unix" {
    var ma = try Multiaddr.fromUrl(testing.allocator, "unix:/tmp/test.sock");
    defer ma.deinit();
    const str = try ma.toString(testing.allocator);
    defer testing.allocator.free(str);
    try testing.expectEqualStrings("/unix//tmp/test.sock", str);
}

test "multiaddr from url - information loss" {
    // Basic information loss cases
    try testing.expectError(FromUrlError.InformationLoss, Multiaddr.fromUrl(testing.allocator, "http://user@example.com"));
    try testing.expectError(FromUrlError.InformationLoss, Multiaddr.fromUrl(testing.allocator, "http://user:pass@example.com"));
    try testing.expectError(FromUrlError.InformationLoss, Multiaddr.fromUrl(testing.allocator, "http://example.com/path/to/resource"));
    try testing.expectError(FromUrlError.InformationLoss, Multiaddr.fromUrl(testing.allocator, "http://example.com?query=value"));
    try testing.expectError(FromUrlError.InformationLoss, Multiaddr.fromUrl(testing.allocator, "http://example.com#fragment"));

    // Valid cases that should not trigger information loss
    {
        var ma = try Multiaddr.fromUrl(testing.allocator, "http://example.com/");
        defer ma.deinit();
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/dns/example.com/tcp/80/http", str);
    }

    // Unix socket paths should not trigger information loss
    {
        var ma = try Multiaddr.fromUrl(testing.allocator, "unix:/path/to/socket");
        defer ma.deinit();
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/unix//path/to/socket", str);
    }
}

test "multiaddr from url lossy" {
    // These should work with lossy conversion
    {
        var ma = try Multiaddr.fromUrlLossy(testing.allocator, "http://example.com/ignored/path?query=value#fragment");
        defer ma.deinit();
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/dns/example.com/tcp/80/http", str);
    }
}

test "multiaddr dns protocols" {
    // DNS4
    {
        var ma = Multiaddr.init(testing.allocator);
        defer ma.deinit();
        try ma.push(.{ .Dns4 = "example.com" });
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/dns4/example.com", str);
    }

    // DNS6
    {
        var ma = Multiaddr.init(testing.allocator);
        defer ma.deinit();
        try ma.push(.{ .Dns6 = "example.com" });
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/dns6/example.com", str);
    }

    // DNSADDR
    {
        var ma = Multiaddr.init(testing.allocator);
        defer ma.deinit();
        try ma.push(.{ .Dnsaddr = "example.com" });
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/dnsaddr/example.com", str);
    }

    // Test encoding/decoding roundtrip
    {
        var ma = Multiaddr.init(testing.allocator);
        defer ma.deinit();
        try ma.push(.{ .Dns4 = "example.com" });
        try ma.push(.{ .Tcp = 80 });

        var iter = ma.iterator();
        const first = try iter.next();
        try testing.expect(first != null);
        try testing.expectEqualStrings("example.com", first.?.Dns4);

        const second = try iter.next();
        try testing.expect(second != null);
        try testing.expectEqual(@as(u16, 80), second.?.Tcp);
    }
}

test "multiaddr protocol - dccp and sctp" {
    // Test DCCP
    {
        var ma = Multiaddr.init(testing.allocator);
        defer ma.deinit();
        try ma.push(.{ .Dccp = 1234 });
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/dccp/1234", str);
    }

    // Test SCTP
    {
        var ma = Multiaddr.init(testing.allocator);
        defer ma.deinit();
        try ma.push(.{ .Sctp = 5678 });
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/sctp/5678", str);
    }
}

test "multiaddr protocol - tls and quic variants" {
    // Test TLS
    {
        var ma = Multiaddr.init(testing.allocator);
        defer ma.deinit();
        try ma.push(.Tls);
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/tls", str);
    }

    // Test QUIC
    {
        var ma = Multiaddr.init(testing.allocator);
        defer ma.deinit();
        try ma.push(.Quic);
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/quic", str);
    }

    // Test QUIC-V1
    {
        var ma = Multiaddr.init(testing.allocator);
        defer ma.deinit();
        try ma.push(.QuicV1);
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/quic-v1", str);
    }
}

test "multiaddr protocol - p2p-circuit and webtransport" {
    // Test P2P-Circuit
    {
        var ma = Multiaddr.init(testing.allocator);
        defer ma.deinit();
        try ma.push(.P2pCircuit);
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/p2p-circuit", str);
    }

    // Test WebTransport
    {
        var ma = Multiaddr.init(testing.allocator);
        defer ma.deinit();
        try ma.push(.WebTransport);
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/webtransport", str);
    }
}

test "multiaddr protocol p2p" {
    // Test P2P with PeerId
    {
        var ma = Multiaddr.init(testing.allocator);
        defer ma.deinit();
        const peer_id = try PeerId.fromString(testing.allocator, "QmYyQSo1c1Ym7orWxLYvCrM2EmxFTANf8wXmmE7DWjhx5N");
        try ma.push(.{ .P2P = peer_id });
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/p2p/QmYyQSo1c1Ym7orWxLYvCrM2EmxFTANf8wXmmE7DWjhx5N", str);
    }

    // Test P2P with different PeerId
    {
        var ma = Multiaddr.init(testing.allocator);
        defer ma.deinit();
        const peer_id1 = try PeerId.fromString(testing.allocator, "QmYyQSo1c1Ym7orWxLYvCrM2EmxFTANf8wXmmE7DWjhx5N");
        const peer_id2 = try PeerId.fromString(testing.allocator, "QmZzZSo1c1Ym7orWxLYvCrM2EmxFTANf8wXmmE7DWjhx5N");
        try ma.push(.{ .P2P = peer_id1 });
        try testing.expectError(error.DifferentPeerId, ma.withP2p(testing.allocator, peer_id2));
    }

    // Test P2P pop and push
    {
        var ma = Multiaddr.init(testing.allocator);
        defer ma.deinit();
        const peer_id = try PeerId.fromString(testing.allocator, "QmYyQSo1c1Ym7orWxLYvCrM2EmxFTANf8wXmmE7DWjhx5N");
        try ma.push(.{ .P2P = peer_id });
        const str = try ma.toString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("/p2p/QmYyQSo1c1Ym7orWxLYvCrM2EmxFTANf8wXmmE7DWjhx5N", str);
        const p = try ma.pop();
        try testing.expectEqual(p.?, Protocol{ .P2P = peer_id });
        const new_ma = try ma.withP2p(testing.allocator, peer_id);
        defer new_ma.deinit();
        try testing.expect(&ma != &new_ma);
    }
}

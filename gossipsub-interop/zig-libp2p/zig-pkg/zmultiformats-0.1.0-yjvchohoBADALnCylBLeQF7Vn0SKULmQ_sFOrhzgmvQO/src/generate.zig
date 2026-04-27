const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const Allocator = std.mem.Allocator;

const Codec = struct {
    name: []u8,
    tag: []u8,
    code: i32,
    status: []u8,
    description: []u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read CSV file
    const csv_content = try fs.cwd().readFileAlloc(allocator, "src/spec/multicodec/table.csv", 1024 * 1024);
    defer allocator.free(csv_content);

    var codecs: std.ArrayList(Codec) = .{};
    defer codecs.deinit(allocator);

    // Parse CSV
    var lines = std.mem.splitSequence(u8, csv_content, "\n");
    _ = lines.next(); // Skip header

    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitSequence(u8, line, ",");

        const name = try allocator.dupe(u8, fields.next() orelse continue);
        const tag = try allocator.dupe(u8, fields.next() orelse continue);
        const code_str = fields.next() orelse continue;
        const status = try allocator.dupe(u8, fields.next() orelse continue);
        const description = try allocator.dupe(u8, fields.next() orelse continue);

        const code = try std.fmt.parseInt(i32, std.mem.trim(u8, code_str, " "), 0);

        try codecs.append(allocator, .{
            .name = name,
            .tag = tag,
            .code = code,
            .status = status,
            .description = description,
        });
    }

    defer {
        for (codecs.items) |codec| {
            allocator.free(codec.name);
            allocator.free(codec.tag);
            allocator.free(codec.status);
            allocator.free(codec.description);
        }
    }

    // Generate combined file
    {
        const combined_file = try fs.cwd().createFile("src/multicodec.zig", .{});
        defer combined_file.close();

        const writer = combined_file.writer();
        try writer.writeAll(
            \\// Generated file - DO NOT EDIT
            \\
            \\const std = @import("std");
            \\
            \\pub const MulticodecTag = enum {
            \\
        );

        // Write unique sorted tags
        var tags = std.StringHashMap(void).init(allocator);
        defer tags.deinit();

        // First collect unique tags with proper trimming
        for (codecs.items) |codec| {
            const trimmed_tag = std.mem.trim(u8, codec.tag, " ");
            try tags.put(trimmed_tag, {});
        }

        // Convert to sorted array
        var tag_keys: std.ArrayList([]const u8) = .{};
        defer tag_keys.deinit(allocator);

        var tag_iter = tags.keyIterator();
        while (tag_iter.next()) |tag| {
            try tag_keys.append(allocator, tag.*);
        }

        // Sort tags alphabetically
        std.mem.sort([]const u8, tag_keys.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        // Write unique sorted tags
        for (tag_keys.items) |tag| {
            try writer.print("    {s},\n", .{tag});
        }
        try writer.writeAll("};\n\n");

        // Write Multicodec enum
        try writer.writeAll("pub const Multicodec = enum(u64) {\n");

        // Write enum fields
        for (codecs.items) |codec| {
            const name = try std.ascii.allocUpperString(allocator, codec.name);
            defer allocator.free(name);
            for (name) |*c| {
                if (c.* == '-') c.* = '_';
            }
            try writer.print("    {s} = 0x{x:0>2},\n", .{ name, @as(u64, @intCast(codec.code)) });
        }

        // Write toString function
        try writer.writeAll("\n    pub fn toString(self: Multicodec) []const u8 {\n        return switch (self) {\n");
        for (codecs.items) |codec| {
            const name = try std.ascii.allocUpperString(allocator, codec.name);
            defer allocator.free(name);
            for (name) |*c| {
                if (c.* == '-') c.* = '_';
            }
            try writer.print("            .{s} => \"{s}\",\n", .{ name, codec.name });
        }
        try writer.writeAll("        };\n    }\n\n");

        // Write fromString function
        try writer.writeAll("    pub fn fromString(name: []const u8) !Multicodec {\n        const name_map = std.StaticStringMap(Multicodec).initComptime(.{\n");
        for (codecs.items) |codec| {
            const name = try std.ascii.allocUpperString(allocator, codec.name);
            defer allocator.free(name);
            for (name) |*c| {
                if (c.* == '-') c.* = '_';
            }
            try writer.print("            .{{ \"{s}\", .{s} }},\n", .{ codec.name, name });
        }
        try writer.writeAll("        });\n        return name_map.get(name) orelse error.UnknownMulticodec;\n    }\n\n");

        // Write fromCode function
        try writer.writeAll("    pub fn fromCode(code: u64) !Multicodec {\n        return switch (code) {\n");
        for (codecs.items) |codec| {
            const name = try std.ascii.allocUpperString(allocator, codec.name);
            defer allocator.free(name);
            for (name) |*c| {
                if (c.* == '-') c.* = '_';
            }
            try writer.print("            0x{x:0>2} => .{s},\n", .{ @as(u64, @intCast(codec.code)), name });
        }
        try writer.writeAll("            else => error.UnknownMulticodec,\n        };\n    }\n\n");

        // Write getTag function
        try writer.writeAll("    pub fn getTag(self: Multicodec) MulticodecTag {\n        return switch (self) {\n");
        for (codecs.items) |codec| {
            const name = try std.ascii.allocUpperString(allocator, codec.name);
            defer allocator.free(name);
            for (name) |*c| {
                if (c.* == '-') c.* = '_';
            }
            const trimmed_tag = std.mem.trim(u8, codec.tag, " ");
            try writer.print("            .{s} => .{s},\n", .{ name, trimmed_tag });
        }
        try writer.writeAll("        };\n    }\n\n");

        // Write getCode function
        try writer.writeAll("    pub fn getCode(self: Multicodec) u64 {\n        return @intFromEnum(self);\n    }\n};\n");
    }
}

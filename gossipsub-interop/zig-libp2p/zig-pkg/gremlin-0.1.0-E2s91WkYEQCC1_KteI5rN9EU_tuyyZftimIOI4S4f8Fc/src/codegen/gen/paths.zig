//! Provides functionality for handling file paths in the Protocol Buffer to Zig code generator.
//! This module handles path transformations between source proto files and their corresponding
//! generated Zig output files.

//               .'\   /`.
//             .'.-.`-'.-.`.
//        ..._:   .-. .-.   :_...
//      .'    '-.(o ) (o ).-'    `.
//     :  _    _ _`~(_)~`_ _    _  :
//    :  /:   ' .-=_   _=-. `   ;\  :
//    :   :|-.._  '     `  _..-|:   :
//     :   `:| |`:-:-.-:-:'| |:'   :
//      `.   `.| | | | | | |.'   .'
//        `.   `-:_| | |_:-'   .'
//          `-._   ````    _.-'
//              ``-------''
//
// Created by ab, 03.09.2024

const std = @import("std");

/// PathError enumerates possible errors that can occur during path operations
pub const PathError = error{
    /// Standard allocation failure
    OutOfMemory,
    /// Invalid input path structure
    InvalidPath,
};

/// Generates the output path for a Zig file based on the input proto file path.
/// Maintains the directory structure relative to the output folder while
/// adding the .zig extension to the filename.
///
/// Given an input path like "path/to/file.proto" and output folder "out",
/// generates a path like "out/path/to/file.proto.zig"
///
/// Parameters:
///   - allocator: Memory allocator for string operations
///   - rel_path: Relative path of the input proto file
///   - out_folder: Base output directory for generated files
///
/// Returns: Allocated string containing the complete output path
/// Error: OutOfMemory if allocation fails
///        InvalidPath if the input path structure is invalid
pub fn outputPath(
    allocator: std.mem.Allocator,
    rel_path: []const u8,
    out_folder: []const u8,
) PathError![]const u8 {
    const components = try extractPathComponents(rel_path);

    // Generate output filename with .zig extension
    const output_filename = try generateOutputFilename(allocator, components.filename);
    defer allocator.free(output_filename);

    // Combine components into final path
    return try joinOutputPath(
        allocator,
        out_folder,
        components.directory,
        output_filename,
    );
}

/// Extracts filename and directory components from a path
fn extractPathComponents(path: []const u8) PathError!struct {
    filename: []const u8,
    directory: []const u8,
} {
    const filename = std.fs.path.basename(path);
    const directory = std.fs.path.dirname(path) orelse "";

    return .{
        .filename = filename,
        .directory = directory,
    };
}

/// Generates the output filename by appending .zig extension
fn generateOutputFilename(
    allocator: std.mem.Allocator,
    input_filename: []const u8,
) PathError![]const u8 {
    return std.mem.concat(allocator, u8, &[_][]const u8{
        input_filename,
        ".zig",
    });
}

/// Joins path components to create the final output path
fn joinOutputPath(
    allocator: std.mem.Allocator,
    out_folder: []const u8,
    directory: []const u8,
    filename: []const u8,
) PathError![]const u8 {
    return std.fs.path.join(allocator, &[_][]const u8{
        out_folder,
        directory,
        filename,
    });
}

test "output path" {
    const allocator = std.testing.allocator;

    const rel_path = "path/to/file.proto";
    const out_folder = "out";

    const out_path = try outputPath(allocator, rel_path, out_folder);
    defer allocator.free(out_path);
    const expected = "out/path/to/file.proto.zig";
    try std.testing.expectEqualStrings(expected, out_path);
}

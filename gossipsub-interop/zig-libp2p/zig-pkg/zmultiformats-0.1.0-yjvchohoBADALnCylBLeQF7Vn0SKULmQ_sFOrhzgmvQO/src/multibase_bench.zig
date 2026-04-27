const std = @import("std");
const multibase = @import("multibase.zig");

const period_arg = "--period";
const times_arg_prefix = "--times";
const code_arg = "--code";
const method_arg = "--method";

const Error = error{
    InvalidTimesValue,
    InvalidPeriodValue,
    InvalidMethodValue,
    MissingTimes,
    MissingCode,
    MissingMethod,
};

const BenchConfig = struct {
    period: u64,
    times: u64,
    code: multibase.MultiBaseCodec,
    method: []const u8,
};

const BenchResult = struct {
    name: []const u8,
    method: []const u8,
    period: u64,
    times: u64,
    max_time: i128,
    min_time: i128,
    avg_time: i128,
    data_len: u64,
    pub fn format(self: @This(), writer: anytype) !void {
        // print formated benchmark result
        try writer.print(
            \\Benchmark {s} Results:
            \\=========================================
            \\Name          : {s}
            \\Period        : {d}
            \\Times         : {d}
            \\Max Time (ns) : {d}
            \\Min Time (ns) : {d}
            \\Avg Time (ns) : {d}
            \\Data Length   : {d}
            \\=========================================
            \\
        ,
            .{
                self.method,
                self.name,
                self.period,
                self.times,
                self.max_time,
                self.min_time,
                self.avg_time,
                self.data_len,
            },
        );
    }
};

const Func = struct {
    fn_ptr: *const fn (codec: multibase.MultiBaseCodec, dest: []u8, data: []const u8) void,
    codec: multibase.MultiBaseCodec,
    fn call(self: @This(), dest: []u8, data: []const u8) void {
        self.fn_ptr(self.codec, dest, data);
    }
};

fn call_encode(codec: multibase.MultiBaseCodec, dest: []u8, data: []const u8) void {
    _ = codec.encode(dest, data);
}

fn call_decode(codec: multibase.MultiBaseCodec, dest: []u8, data: []const u8) void {
    _ = codec.decode(dest, data) catch |err| {
        std.debug.print("Error: {}\n", .{err});
    };
}

const bench_data_path = "./test/data/bench_data";

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const bench_data = try loadBenchData(allocator, bench_data_path);
    const config = try parse_args();
    var bench_res = try run_bench(bench_data, config);
    try bench_res.format(std.io.getStdOut().writer());
}

fn parse_args() !BenchConfig {
    var period: u64 = 10;
    var times: u64 = 1_000_000;
    var code: ?multibase.MultiBaseCodec = null;
    var method: []const u8 = "encode";

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const args = try std.process.argsAlloc(arena);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, times_arg_prefix)) {
            i += 1;
            const value = args[i];
            times = try handle_times(value);
        } else if (std.mem.startsWith(u8, arg, times_arg_prefix)) {
            const value = arg[times_arg_prefix.len + 1 ..];
            times = try handle_times(value);
        } else if (std.mem.eql(u8, arg, period_arg)) {
            i += 1;
            const value = args[i];
            period = try handle_period(value);
        } else if (std.mem.startsWith(u8, arg, period_arg)) {
            const value = arg[period_arg.len + 1 ..];
            period = try handle_period(value);
        } else if (std.mem.eql(u8, arg, code_arg)) {
            i += 1;
            code = try multibase.MultiBaseCodec.fromCode(args[i]);
        } else if (std.mem.startsWith(u8, arg, code_arg)) {
            code = try multibase.MultiBaseCodec.fromCode(arg[code_arg.len + 1 ..]);
        } else if (std.mem.eql(u8, arg, method_arg)) {
            i += 1;
            method = try handle_method(args[i]);
        } else if (std.mem.startsWith(u8, arg, method_arg)) {
            method = try handle_method(arg[method_arg.len + 1 ..]);
        }
    }

    if (code == null) return Error.MissingCode;

    return .{
        .period = period,
        .times = times,
        .code = code.?,
        .method = method,
    };
}

fn handle_period(value: []const u8) !u64 {
    const period = try std.fmt.parseUnsigned(u64, value, 10);
    if (period == 0) {
        return Error.InvalidPeriodValue;
    }
    return period;
}

fn handle_times(value: []const u8) !u64 {
    const times = try std.fmt.parseUnsigned(u64, value, 10);
    if (times == 0) {
        return Error.InvalidTimesValue;
    }
    return times;
}

fn handle_method(value: []const u8) ![]const u8 {
    if (std.mem.eql(u8, "encode", value)) {
        return "encode";
    } else if (std.mem.eql(u8, "decode", value)) {
        return "decode";
    } else {
        return Error.InvalidMethodValue;
    }
}

fn run_bench(bench_data: []const u8, config: BenchConfig) !BenchResult {
    var dest_len = config.code.encodedLen(bench_data);
    var action = Func{
        .fn_ptr = call_encode,
        .codec = config.code,
    };
    var data: []const u8 = bench_data;
    if (std.mem.eql(u8, "decode", config.method)) {
        const encoded_data = try std.heap.page_allocator.alloc(u8, config.code.encodedLen(bench_data));
        data = config.code.encode(encoded_data, bench_data)[1..];
        dest_len = config.code.decodedLen(data);
        action = Func{
            .fn_ptr = call_decode,
            .codec = config.code,
        };
    }
    const dest = try std.heap.page_allocator.alloc(u8, dest_len);
    defer std.heap.page_allocator.free(dest);
    var i: u64 = 0;
    var max_time: i128 = 0;
    var min_time: i128 = 0;
    var time_records = try std.heap.page_allocator.alloc(i128, config.period);
    defer std.heap.page_allocator.free(time_records);
    while (i < config.period) : (i += 1) {
        const start_time = std.time.nanoTimestamp();
        for (0..config.times) |_| {
            action.call(dest, data);
            // _ = config.code.encode(dest, bench_data);
        }
        const end_time = std.time.nanoTimestamp();
        const elapsed_time = end_time - start_time;
        time_records[i] = elapsed_time;
        if (elapsed_time > max_time) {
            max_time = elapsed_time;
        }
        if (min_time == 0 or elapsed_time < min_time) {
            min_time = elapsed_time;
        }
    }

    var sum_time: i128 = 0;
    for (time_records) |time| {
        sum_time += time;
    }
    const avg_time = @divFloor(sum_time, config.period);
    return .{
        .name = config.code.code(),
        .method = config.method,
        .period = config.period,
        .times = config.times,
        .max_time = max_time,
        .min_time = min_time,
        .avg_time = avg_time,
        .data_len = bench_data.len,
    };
}

fn loadBenchData(allocator: std.mem.Allocator, filePath: []const u8) ![]const u8 {
    var file = try std.fs.cwd().openFile(filePath, .{ .mode = std.fs.File.OpenMode.read_only });
    defer file.close();
    const fileSize = try file.getEndPos();
    const buffer = try allocator.alloc(u8, fileSize);
    _ = try file.readAll(buffer);
    const content: []const u8 = buffer;
    return content;
}

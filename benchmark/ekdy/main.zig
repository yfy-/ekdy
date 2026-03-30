const std = @import("std");
const ekdy = @import("ekdy");
const html = ekdy.html;
const policy = ekdy.policy;

const usage =
    \\Usage: benchmark_ekdy HTMLBIN_PATH [--repeats N]
    \\
    \\Benchmark ekdy on a prepared .htmlbin.gz corpus.
    \\
    \\Positional arguments:
    \\  HTMLBIN_PATH   Path to the input .htmlbin.gz benchmark corpus
    \\
    \\Options:
    \\  --repeats N    Number of benchmark repetitions (default: 5)
    \\
;

fn load_docs(allocator: std.mem.Allocator, htmlbin_path: []const u8) !struct { [][]const u8, usize } {
    const htmlbin_file = try std.fs.cwd().openFile(htmlbin_path, .{});
    defer htmlbin_file.close();

    var htmlbin_file_buf: [4096]u8 = undefined;
    var htmlbin_reader = htmlbin_file.reader(&htmlbin_file_buf);
    const reader = &htmlbin_reader.interface;

    var decompress_buf: [std.compress.flate.max_window_len]u8 = undefined;
    var decompress = std.compress.flate.Decompress.init(reader, .gzip, &decompress_buf);
    var docs = std.ArrayList([]const u8){};
    errdefer {
        for (docs.items) |d| {
            allocator.free(d);
        }
        docs.deinit(allocator);
    }

    var total_size: usize = 0;
    while (decompress.reader.takeInt(usize, .little)) |html_size| {
        const html_doc = try decompress.reader.readAlloc(allocator, html_size);
        errdefer allocator.free(html_doc);
        try docs.append(allocator, html_doc);
        total_size += html_size;
    } else |err| {
        if (err == error.ReadFailed) return err;
    }

    return .{ try docs.toOwnedSlice(allocator), total_size };
}

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer if (gpa.deinit() == .leak) @panic("mem leak");

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    _ = args.skip();

    const htmlbin_path = args.next() orelse {
        std.debug.print(usage, .{});
        return error.CLIError;
    };

    var repeats: u32 = 5;
    if (args.next()) |arg3| {
        if (!std.mem.eql(u8, arg3, "--repeats")) {
            std.debug.print("Unknown arg: {s}\n", .{arg3});
            std.debug.print(usage, .{});
            return error.CLIError;
        }

        const arg4 = args.next() orelse {
            std.debug.print("Missing value for --repeats\n", .{});
            std.debug.print(usage, .{});
            return error.CLIError;
        };

        repeats = std.fmt.parseUnsigned(u32, arg4, 10) catch |err| {
            if (err == error.InvalidCharacter) {
                std.debug.print("Invalid value: '{s}' for --repeats\n", .{arg4});
                std.debug.print(usage, .{});
                return error.CLIError;
            }

            return err;
        };

        if (repeats == 0) {
            std.debug.print("--repeats cannot be 0\n", .{});
            return error.CLIError;
        }
    }

    const docs, const total_size = try load_docs(alloc, htmlbin_path);
    defer {
        for (docs) |d| {
            alloc.free(d);
        }
        alloc.free(docs);
    }

    std.debug.print("docs={}\n", .{docs.len});
    std.debug.print("total_in_bytes={}\n", .{total_size});
    var total_out_bytes: usize = 0;
    var times = try alloc.alloc(f64, docs.len);
    defer alloc.free(times);

    for (0..repeats) |run| {
        var alloc_writer = std.io.Writer.Allocating.init(alloc);
        defer alloc_writer.deinit();
        std.debug.print("Running iter: {}\n", .{run});
        for (docs, 0..) |d, i| {
            var p = policy.InnerText{};
            var extractor = try html.TextExtractor(policy.InnerText).init(
                alloc,
                &alloc_writer.writer,
                &p,
            );
            defer extractor.deinit(alloc);

            var timer = try std.time.Timer.start();
            try extractor.convert(alloc, d);
            try extractor.eos();
            const elapsed = timer.read();
            const second = @as(f64, @floatFromInt(elapsed)) /
                @as(f64, @floatFromInt(std.time.ns_per_s));

            if (run == 0) {
                times[i] = second;
                total_out_bytes = alloc_writer.written().len;
            } else {
                times[i] = @min(times[i], second);
            }
        }
    }

    var total_s: f64 = 0;
    for (times) |t| {
        total_s += t;
    }

    std.debug.print("B/s={d:.3}\n", .{
        @as(f64, @floatFromInt(total_size)) / total_s,
    });
    std.debug.print("total_out_bytes={}\n", .{total_out_bytes});
    return 0;
}

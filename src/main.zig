const std = @import("std");
const ekdy = @import("ekdy");
const InnerText = ekdy.policy.InnerText;

pub fn main(init: std.process.Init) !void {
    const buf_size = 32 * 1024;

    const allocator = init.gpa;

    const reader_buffer = try allocator.alloc(u8, buf_size);
    defer allocator.free(reader_buffer);
    var stdin_reader = std.Io.File.stdin().reader(init.io, reader_buffer);

    const writer_buffer = try allocator.alloc(u8, buf_size);
    defer allocator.free(writer_buffer);
    var stdout_writer = std.Io.File.stdout().writer(init.io, writer_buffer);

    const stdin = &stdin_reader.interface;
    const stdout = &stdout_writer.interface;

    var policy = InnerText{ .writer = stdout };
    var extractor = try ekdy.html.TextExtractor(InnerText).init(&policy);
    defer extractor.deinit(allocator);

    while (stdin.fillMore()) {
        const chunk = stdin.buffered();
        defer stdin.tossBuffered();
        if (chunk.len == 0) continue;
        try extractor.feed(allocator, chunk);
    } else |err| if (err == error.ReadFailed) return err;

    try extractor.finish();
    try stdout.flush();
}

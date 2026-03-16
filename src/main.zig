const std = @import("std");
const ekdy = @import("ekdy");
const InnerText = ekdy.policy.InnerText;

pub fn main() !void {
    const buf_size = 32 * 1024;
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();
    defer {
        if (gpa.deinit() == .leak) @panic("memory leak!");
    }

    const reader_buffer = try allocator.alloc(u8, buf_size);
    defer allocator.free(reader_buffer);
    var stdin_reader = std.fs.File.stdin().reader(reader_buffer);

    const writer_buffer = try allocator.alloc(u8, buf_size);
    defer allocator.free(writer_buffer);
    var stdout_writer = std.fs.File.stdout().writer(writer_buffer);

    const stdin = &stdin_reader.interface;
    const stdout = &stdout_writer.interface;

    var policy = InnerText{};
    var extractor = try ekdy.html.TextExtractor(InnerText).init(allocator, stdout, &policy);
    defer extractor.deinit(allocator);

    while (stdin.fillMore()) {
        const chunk = stdin.buffered();
        defer stdin.tossBuffered();
        if (chunk.len == 0) continue;
        try extractor.convert(allocator, chunk);
    } else |err| if (err == error.ReadFailed) return err;

    try extractor.eos();
    try stdout.flush();
}

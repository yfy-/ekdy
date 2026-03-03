const std = @import("std");
const decoding = @import("decoding.zig");
const ascii = std.ascii;
const fs = std.fs;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const Error = Allocator.Error || std.io.Writer.Error;

/// Tags that can end without the associated closing tag.
pub const VoidTags = std.StaticStringMap(void).initComptime(.{
    .{"area"},  .{"base"}, .{"br"},    .{"col"},    .{"command"},
    .{"embed"}, .{"hr"},   .{"img"},   .{"input"},  .{"keygen"},
    .{"link"},  .{"meta"}, .{"param"}, .{"source"}, .{"track"},
    .{"wbr"},   .{"!--"},
});

/// Tags that don't interest humans.
pub const IgnoreTags = std.StaticStringMap(void).initComptime(.{
    .{"script"}, .{"style"},
});

/// Tags that < and > can appear.
pub const AngleBracketTags = std.StaticStringMap(void).initComptime(.{
    .{"title"}, .{"textarea"}, .{"script"}, .{"style"},
});

/// Tags that start a new line. 'br' is actually inline but since
/// it specially inserts a new line to the rendered output we
/// store it here.
pub const BlockLevelTags = std.StaticStringMap(void).initComptime(.{
    .{"address"}, .{"article"},  .{"aside"},      .{"blockquote"},
    .{"canvas"},  .{"dd"},       .{"div"},        .{"dl"},
    .{"dt"},      .{"fieldset"}, .{"figcaption"}, .{"figure"},
    .{"footer"},  .{"form"},     .{"header"},     .{"hr"},
    .{"li"},      .{"main"},     .{"nav"},        .{"noscript"},
    .{"ol"},      .{"p"},        .{"pre"},        .{"section"},
    .{"table"},   .{"tfoot"},    .{"ul"},         .{"video"},
    .{"h1"},      .{"h2"},       .{"h3"},         .{"h4"},
    .{"h5"},      .{"h6"},       .{"br"},
});

pub const TextExtractor = struct {
    const Self = @This();

    stack: ArrayList([]const u8) = ArrayList([]const u8){},

    // Buffer for current tag.
    tag_buffer: []const u8 = &.{},

    // Last whitespace character, either ' ' or '\n'.
    last_whitespace: ?u8 = null,

    // Flag to check if we have emitted any text.
    any_text: bool = false,

    // Quote character used in attribute values.
    attr_val_quote: ?u8 = null,

    // Flag to check if attribute value has started.
    attr_val_start: bool = false,

    // Parser state.
    state: State = .text,

    const State = enum {
        text,
        tag,
        tag_start,
        tag_start_found,
        tag_end,
        tag_end_found,
        attr_key,
        attr_val,
        comment,
    };

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.stack.deinit(allocator);
    }

    pub fn convert(
        self: *Self,
        allocator: Allocator,
        html: []const u8,
        writer: *std.io.Writer,
    ) !void {
        var i: usize = 0;
        while (i < html.len) {
            const skip_len = switch (self.state) {
                .text => self.handleText(html[i..], writer),
                .tag => self.handleTag(html[i..], writer),
                .tag_start => self.handleTagStart(allocator, html[i..]),
                .tag_start_found => self.handleTagStartFound(html[i..]),
                .tag_end => self.handleTagEnd(html[i..]),
                .tag_end_found => self.handleTagEndFound(html[i..]),
                .attr_key => self.handleAttrKey(html[i..]),
                .attr_val => self.handleAttrVal(html[i..]),
                .comment => self.handleComment(html[i..]),
            } catch |err| {
                std.log.err(
                    "Error {} at {s}>{c}<{s} at index '{d}'",
                    .{
                        err,
                        html[@max(0, i -| 100)..i],
                        html[i],
                        html[i + 1 .. @min(i +| 101, html.len - 1)],
                        i,
                    },
                );
                return err;
            };

            i += skip_len;
        }
    }

    fn handleText(self: *Self, html: []const u8, writer: *std.io.Writer) Error!usize {
        const c = html[0];
        const tag = self.stack.getLastOrNull();

        if (c == '<') {
            if (tag == null or !AngleBracketTags.has(tag.?)) {
                self.state = State.tag;
                return 1;
            }

            const tag_end_size = tag.?.len + 2;
            if (html.len >= tag_end_size and html[1] == '/' and
                std.mem.eql(u8, tag.?, html[2..tag_end_size]))
            {
                self.tag_buffer = tag.?;
                self.state = State.tag_end_found;
                return tag_end_size;
            }
        }

        if (tag != null and IgnoreTags.has(tag.?)) return 1;

        if (ascii.isWhitespace(c)) {
            if (self.last_whitespace == null or self.last_whitespace.? != '\n') {
                self.last_whitespace = ' ';
            }
        } else {
            if (self.last_whitespace) |lw| {
                if (self.any_text) try writer.writeByte(lw);
            }
            try writer.writeByte(c);
            self.any_text = true;
            self.last_whitespace = null;
        }

        return 1;
    }

    fn handleTag(self: *Self, html: []const u8, writer: *std.io.Writer) Error!usize {
        const c = html[0];
        if (ascii.isWhitespace(c)) {
	    try writer.print("<{c}", .{c});
	    self.state = State.text;
	    return 1;
	}

        if (c == '/') {
            self.state = State.tag_end;
            return 1;
        }

        self.state = State.tag_start;
        return 0;
    }

    fn handleTagStart(self: *Self, allocator: Allocator, html: []const u8) Error!usize {
        _ = handleText;
        const c = html[0];
        // Handle comments below
        if (html.len > 2 and std.mem.eql(u8, html[0..3], "!--")) {
            self.tag_buffer.len = 0;
            self.state = State.comment;
            return 3;
        }

        if (ascii.isWhitespace(c) or c == '>' or c == '/') {
            try self.stack.append(allocator, self.tag_buffer);
            self.tag_buffer.len = 0;
            self.state = State.tag_start_found;
            return if (ascii.isWhitespace(c)) 1 else 0;
        }

        if (self.tag_buffer.len == 0) {
            self.tag_buffer.ptr = html.ptr;
        }

        self.tag_buffer.len += 1;
        return 1;
    }

    fn handleTagStartFound(self: *Self, html: []const u8) Error!usize {
        if (BlockLevelTags.has(self.stack.getLast())) {
            self.last_whitespace = '\n';
        }

        const c = html[0];
        if (ascii.isWhitespace(c)) return 1;
        if (c == '/') {
            self.state = State.tag_end_found;
            return 1;
        }

        if (c == '>') {
            if (VoidTags.has(self.stack.getLast())) {
                self.state = State.tag_end_found;
                return 0;
            }

            self.state = State.text;
            return 1;
        }

        self.state = State.attr_key;
        return 0;
    }

    fn handleTagEnd(self: *Self, html: []const u8) Error!usize {
        const c = html[0];
        if (ascii.isWhitespace(c) or c == '>') {
            self.state = State.tag_end_found;
            return if (c == '>') 0 else 1;
        }

        if (self.tag_buffer.len == 0) {
            self.tag_buffer.ptr = html.ptr;
        }

        self.tag_buffer.len += 1;
        return 1;
    }

    fn handleUnmatchedTag(self: *Self) void {
        var found_idx = self.stack.items.len;
        while (found_idx > 0) : (found_idx -= 1) {
            if (std.mem.eql(
                u8,
                self.tag_buffer,
                self.stack.items[found_idx - 1],
            )) {
                _ = self.stack.orderedRemove(found_idx - 1);
                return;
            }
        }
    }

    fn handleTagEndFound(self: *Self, html: []const u8) Error!usize {
        const c = html[0];
        if (ascii.isWhitespace(c)) return 1;
        if (c == '>') {
            defer self.tag_buffer.len = 0;
            if (self.stack.getLastOrNull()) |tag| {
		if (BlockLevelTags.has(tag)) {
		    self.last_whitespace = '\n';
		}

		if (self.tag_buffer.len > 0 and !std.mem.eql(u8, tag, self.tag_buffer)) {
                    self.handleUnmatchedTag();
                } else {
                    _ = self.stack.pop();
                }
            }

	    self.state = State.text;
        }

	return 1;
    }

    fn handleAttrKey(self: *Self, html: []const u8) Error!usize {
        const c = html[0];
        if (c == '=') {
            self.state = State.attr_val;
            return 1;
        }

        if (c == '>') {
            self.state = State.tag_start_found;
            return 0;
        }

        return 1;
    }

    fn handleAttrVal(self: *Self, html: []const u8) Error!usize {
        const c = html[0];
        self.state = State.attr_val;
        if (self.attr_val_quote) |qc| {
            if (c == qc) {
                self.state = State.tag_start_found;
                self.attr_val_quote = null;
                self.attr_val_start = false;
            }
        } else {
            if (ascii.isWhitespace(c)) {
                if (self.attr_val_start) {
                    self.state = State.tag_start_found;
                    self.attr_val_start = false;
                }
            } else if (c == '"' or c == '\'') {
                self.attr_val_quote = c;
                self.attr_val_start = true;
            } else if (c == '>') {
                self.attr_val_start = false;
                self.state = State.tag_start_found;
                return 0;
            } else {
                self.attr_val_start = true;
            }
        }

        return 1;
    }

    fn handleComment(self: *Self, html: []const u8) Error!usize {
        // Immediately exit when '--' is seen. Process 3 chars because
        // '--' cannot occur without the final '>'.
        if (html.len > 1 and std.mem.eql(u8, html[0..2], "--")) {
            self.state = State.text;
            return 3;
        }

        return 1;
    }
};

const talloc = std.testing.allocator;

/// Check if html to text works as expected.
fn expectConvert(expected: []const u8, html_text: []const u8) !void {
    var allocating = std.io.Writer.Allocating.init(talloc);
    defer allocating.deinit();
    var extractor = TextExtractor{};
    defer extractor.deinit(talloc);
    try extractor.convert(talloc, html_text, &allocating.writer);
    try std.testing.expectEqualStrings(expected, allocating.written());
}

/// Check if html to text (with entity decoding) works as expected.
fn expectConvertDecoded(expected: []const u8, html_text: []const u8) !void {
    var allocating = std.io.Writer.Allocating.init(talloc);
    defer allocating.deinit();
    var decoder = decoding.EntityDecoder.init(&allocating.writer);
    var extractor = TextExtractor{};
    defer extractor.deinit(talloc);
    try extractor.convert(talloc, html_text, &decoder.writer);
    try std.testing.expectEqualStrings(expected, allocating.written());
}

test "strip_html_very_simple" {
    try expectConvert("erman", "<p> erman </p>");
}

test "strip_html_nested_simple" {
    try expectConvert(
        "This is a simple example.",
        "<p>This is a <strong>simple</strong> example.</p>",
    );
}

test "strip_html_nested_link" {
    try expectConvert(
        "Title\nParagraph with link.",
        \\<div><h1>Title</h1><p>Paragraph with <a href="http://wiki">link</a>.
        \\</p></div>
        ,
    );
}

test "strip_html_nested_list" {
    try expectConvert(
        "Item 1\nItem 2 with emphasis\nItem 3",
        \\<ul>
        \\  <li>Item 1</li>
        \\  <li>Item 2 with <em>emphasis</em></li>
        \\  <li>Item 3</li>
        \\</ul>
        ,
    );
}

test "strip_html_link_with_entity" {
    try expectConvert(
        "Title\nParagraph with link.",
        \\<div><h1>Title</h1><p>Paragraph with <a href="http://wiki&amp;">
        \\link</a>.</p></div>
        ,
    );
}

test "strip_html_void_tags" {
    const html =
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\<meta charset="UTF-8">
        \\<title>Simple HTML Example</title>
        \\</head>
        \\<body>
        \\<div>
        \\<h1>Welcome</h1>
        \\<p>This paragraph contains an image:
        \\<img src="example.jpg" alt="Example Image">
        \\</p>
        \\<div>
        \\<p>
        \\Here is a line break after this sentence:<br>
        \\And here is the next line.
        \\</p>
        \\<hr>
        \\<p>Enter your name:
        \\<input type="text" placeholder="Name">
        \\</p>
        \\</div>
        \\</div>
        \\</body>
        \\</html>
    ;
    const exp = "Simple HTML Example\nWelcome\nThis paragraph contains an " ++
        "image:\nHere is a line break after this sentence:\nAnd here is the " ++
        "next line.\nEnter your name:";
    try expectConvert(exp, html);
}

test "strip_html_ignore_tags_comment" {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\<meta charset="UTF-8">
        \\<title>Short &lt; &gt;</title>
        \\<style>
        \\body { font-family: Arial; }
        \\</style>
        \\</head>
        \\<body>
        \\<!-- A simple comment -->
        \\<!-- <p>This is a valid HTML snippet inside a comment.</p> -->
        \\<h1>Hi! &#x00A8; </h1>
        \\<script>
        \\alert('Hello!');
        \\</script>
        \\</body>
        \\</html>
    ;
    const exp = "Short &lt; &gt;\nHi! &#x00A8;";
    try expectConvert(exp, html);
}

test "strip_html_weird_unmatching" {
    try expectConvert(
        "12345",
        "<p>1<b>2<i>3</b>4</i>5</p>",
    );
}

fn expectConvertFile(comptime file_base: []const u8) !void {
    const src_dir = fs.path.dirname(@src().file) orelse "";
    const resource_dir = try fs.path.join(
        talloc,
        &[_][]const u8{ src_dir, "test-resource" },
    );
    defer talloc.free(resource_dir);

    // Read html file
    const html_path = try fs.path.join(
        talloc,
        &[_][]const u8{ resource_dir, file_base ++ ".html" },
    );
    defer talloc.free(html_path);

    const html_file = try fs.cwd().openFile(html_path, .{});
    defer html_file.close();

    const html = try html_file.readToEndAlloc(
        talloc,
        5 * 1024 * 1024,
    );
    defer talloc.free(html);

    // Read text file
    const text_path = try fs.path.join(
        talloc,
        &[_][]const u8{ resource_dir, file_base ++ ".txt" },
    );
    defer talloc.free(text_path);

    const text_file = try fs.cwd().openFile(text_path, .{});
    defer text_file.close();

    const text = try text_file.readToEndAlloc(
        talloc,
        5 * 1024 * 1024,
    );
    defer talloc.free(text);

    try expectConvertDecoded(text, html);
}

test "integration_mygithub" {
    try expectConvertFile("mygithub");
}

test "integration_w3c" {
    try expectConvertFile("w3c");
}

test "integration_vertex_cover" {
    try expectConvertFile("vertex_cover");
}

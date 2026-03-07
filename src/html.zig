const std = @import("std");
const decoding = @import("decoding.zig");
const ascii = std.ascii;
const fs = std.fs;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const Error = Allocator.Error || std.io.Writer.Error;

pub const Tag = enum(u8) {
    // Unknown tags
    unknown,

    // Main root.
    html,

    // Document metadata.
    base,
    head,
    link,
    meta,
    style,
    title,

    // Sectioning root.
    body,

    // Content sectioning.
    address,
    article,
    aside,
    footer,
    header,
    h1,
    h2,
    h3,
    h4,
    h5,
    h6,
    hgroup,
    main,
    nav,
    section,
    search,

    // Text content
    blockquote,
    dd,
    div,
    dl,
    dt,
    figcaption,
    figure,
    hr,
    li,
    menu,
    ol,
    p,
    pre,
    ul,

    // Inline text semantics
    a,
    abbr,
    b,
    bdi,
    bdo,
    br,
    cite,
    code,
    data,
    dfn,
    em,
    i,
    kbd,
    mark,
    q,
    rp,
    rt,
    ruby,
    s,
    samp,
    small,
    span,
    strong,
    sub,
    sup,
    time,
    u,
    wbr,

    // Image and multimedia
    area,
    audio,
    img,
    map,
    track,
    video,

    // Embedded content
    embed,
    fencedframe,
    iframe,
    object,
    picture,
    source,

    // SVG and MathML
    svg,
    math,

    // Scripting
    canvas,
    noscript,
    script,

    // Demarcating edits
    del,
    ins,

    // Table content
    caption,
    col,
    colgroup,
    table,
    tbody,
    td,
    tfoot,
    th,
    thead,
    tr,

    // Forms
    button,
    datalist,
    fieldset,
    form,
    input,
    label,
    legend,
    meter,
    optgroup,
    option,
    output,
    progress,
    select,
    selectedcontent,
    textarea,

    // Interactive elements
    details,
    dialog,
    geolocation,
    summary,

    // Web components
    slot,
    template,

    // Obsolete and deprecated elements
    acronym,
    big,
    center,
    content,
    dir,
    font,
    frame,
    frameset,
    image,
    marquee,
    menuitem,
    nobr,
    noembed,
    noframes,
    param,
    plaintext,
    rb,
    rtc,
    shadow,
    strike,
    tt,
    xmp,
};

/// Obtain Tag from string.
/// Returning 'unknown' if such Tag does not exist.
pub fn tag_from_str(tag_str: []const u8) Tag {
    return tag_to_enum.get(tag_str) orelse Tag.unknown;
}

pub const Whitespace = enum(u2) {
    space,
    single_break,
    double_break,
};

pub const TagProperty = struct {
    is_void: bool = false,
    is_ignore: bool = false,
    is_raw_text: bool = false,
    whitespace: ?Whitespace = null,
};

pub const tag_properties = std.EnumArray(Tag, TagProperty).initDefault(.{}, .{
    .area = .{ .is_void = true },
    .base = .{ .is_void = true },
    .br = .{ .is_void = true },
    .col = .{ .is_void = true },
    .embed = .{ .is_void = true },
    .frame = .{ .is_void = true },
    .hr = .{ .is_void = true, .whitespace = .double_break },
    .image = .{ .is_void = true },
    .img = .{ .is_void = true },
    .input = .{ .is_void = true },
    .link = .{ .is_void = true },
    .meta = .{ .is_void = true },
    .param = .{ .is_void = true },
    .source = .{ .is_void = true },
    .track = .{ .is_void = true },
    .wbr = .{ .is_void = true },
    .audio = .{ .is_ignore = true },
    .canvas = .{ .is_ignore = true },
    .fencedframe = .{ .is_ignore = true },
    .frameset = .{ .is_ignore = true },
    .head = .{ .is_ignore = true },
    .iframe = .{ .is_ignore = true, .is_raw_text = true },
    .map = .{ .is_ignore = true },
    .math = .{ .is_ignore = true },
    .noembed = .{ .is_ignore = true, .is_raw_text = true },
    .noframes = .{ .is_ignore = true, .is_raw_text = true },
    .noscript = .{ .is_ignore = true, .is_raw_text = true },
    .object = .{ .is_ignore = true },
    .picture = .{ .is_ignore = true },
    .script = .{ .is_ignore = true, .is_raw_text = true },
    .style = .{ .is_ignore = true, .is_raw_text = true },
    .svg = .{ .is_ignore = true },
    .template = .{ .is_ignore = true },
    .video = .{ .is_ignore = true },
    .plaintext = .{ .is_raw_text = true },
    .textarea = .{ .is_raw_text = true },
    .title = .{ .is_raw_text = true },
    .xmp = .{ .is_raw_text = true },
    .body = .{ .whitespace = .single_break },
    .caption = .{ .whitespace = .single_break },
    .colgroup = .{ .whitespace = .single_break },
    .datalist = .{ .whitespace = .single_break },
    .dd = .{ .whitespace = .single_break },
    .div = .{ .whitespace = .single_break },
    .dt = .{ .whitespace = .single_break },
    .fieldset = .{ .whitespace = .single_break },
    .figcaption = .{ .whitespace = .single_break },
    .footer = .{ .whitespace = .single_break },
    .form = .{ .whitespace = .single_break },
    .header = .{ .whitespace = .single_break },
    .html = .{ .whitespace = .single_break },
    .legend = .{ .whitespace = .single_break },
    .li = .{ .whitespace = .single_break },
    .menu = .{ .whitespace = .single_break },
    .menuitem = .{ .whitespace = .single_break },
    .optgroup = .{ .whitespace = .single_break },
    .option = .{ .whitespace = .single_break },
    .summary = .{ .whitespace = .single_break },
    .tbody = .{ .whitespace = .single_break },
    .td = .{ .whitespace = .single_break },
    .tfoot = .{ .whitespace = .single_break },
    .th = .{ .whitespace = .single_break },
    .thead = .{ .whitespace = .single_break },
    .tr = .{ .whitespace = .single_break },
    .address = .{ .whitespace = .double_break },
    .article = .{ .whitespace = .double_break },
    .aside = .{ .whitespace = .double_break },
    .blockquote = .{ .whitespace = .double_break },
    .center = .{ .whitespace = .double_break },
    .details = .{ .whitespace = .double_break },
    .dialog = .{ .whitespace = .double_break },
    .dir = .{ .whitespace = .double_break },
    .dl = .{ .whitespace = .double_break },
    .figure = .{ .whitespace = .double_break },
    .h1 = .{ .whitespace = .double_break },
    .h2 = .{ .whitespace = .double_break },
    .h3 = .{ .whitespace = .double_break },
    .h4 = .{ .whitespace = .double_break },
    .h5 = .{ .whitespace = .double_break },
    .h6 = .{ .whitespace = .double_break },
    .hgroup = .{ .whitespace = .double_break },
    .main = .{ .whitespace = .double_break },
    .nav = .{ .whitespace = .double_break },
    .ol = .{ .whitespace = .double_break },
    .p = .{ .whitespace = .double_break },
    .pre = .{ .whitespace = .double_break },
    .search = .{ .whitespace = .double_break },
    .section = .{ .whitespace = .double_break },
    .table = .{ .whitespace = .double_break },
    .ul = .{ .whitespace = .double_break },
});

pub const tag_to_enum = std.StaticStringMap(Tag).initComptime(blk: {
    const fields = std.meta.fields(Tag);
    var init_vals: [fields.len]struct { []const u8, Tag } = undefined;
    for (fields, 0..) |f, i| {
        init_vals[i] = .{ f.name, @field(Tag, f.name) };
    }

    break :blk init_vals;
});

pub const TextExtractor = struct {
    const Self = @This();

    stack: ArrayList(Tag) = ArrayList(Tag){},

    // Buffer for current tag.
    tag_buffer: []const u8 = &.{},
    // tag_buffer: ArrayList(u8),

    // Whitespace type to emit.
    pending_whitespace: ?Whitespace = null,

    // Flag to indicate last written character is a <br>.
    last_br: bool = false,

    // Flag to check if we have emitted any text.
    any_text: bool = false,

    // Quote character used in attribute values.
    attr_val_quote: ?u8 = null,

    // Flag to check if attribute value has started.
    attr_val_start: bool = false,

    // Parser state.
    state: State = .text,

    cursor: usize = 0,

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
        while (self.cursor < html.len) {
	    const curr_html = html[self.cursor..];
            self.cursor += try switch (self.state) {
                .text => self.handleText(curr_html, writer),
                .tag => self.handleTag(curr_html, writer),
                .tag_start => self.handleTagStart(allocator, curr_html),
                .tag_start_found => self.handleTagStartFound(curr_html, writer),
                .tag_end => self.handleTagEnd(curr_html),
                .tag_end_found => self.handleTagEndFound(curr_html),
                .attr_key => self.handleAttrKey(curr_html),
                .attr_val => self.handleAttrVal(curr_html),
                .comment => self.handleComment(curr_html),
            };
        }
	self.cursor -= html.len;
    }

    //<p>ekdy...</p>
    //   ^~~~~~~
    fn handleText(self: *Self, html: []const u8, writer: *std.io.Writer) Error!usize {
        const c = html[0];
        const tag = self.stack.getLastOrNull();
        const tag_prop = if (tag) |t| tag_properties.get(t) else null;

        if (c == '<') {
            if (tag == null or !tag_prop.?.is_raw_text) {
                self.state = State.tag;
                return 1;
            }

            const tag_str = @tagName(tag.?);
            const tag_end_size = tag_str.len + 2;
            if (html.len >= tag_end_size and html[1] == '/' and
                tag.? == tag_from_str(html[2..tag_end_size]))
            {
                self.tag_buffer = tag_str;
                self.state = State.tag_end_found;
                return tag_end_size;
            }
        }

        if (tag != null and tag_prop.?.is_ignore) return 1;

        if (ascii.isWhitespace(c)) {
            // When last processed tag was br and it inserted a new line,
            // we do not queue a new space.
            if (self.pending_whitespace == null and !self.last_br) {
                self.pending_whitespace = .space;
            }
        } else {
            if (self.pending_whitespace) |pw| {
                if (self.any_text) {
                    const ws = switch (pw) {
                        .space => " ",
                        .single_break => "\n",
                        .double_break => "\n\n",
                    };
                    try writer.writeAll(ws);
                }
            }

            try writer.writeByte(c);
            self.any_text = true;
            self.pending_whitespace = null;
            self.last_br = false;
        }

        return 1;
    }

    //<p>ekdy...</p>
    //^
    //
    //<p>ekdy...</p>
    //          ^
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

    //<strong>ekdy...</strong>
    // ^~~~~
    fn handleTagStart(self: *Self, allocator: Allocator, html: []const u8) Error!usize {
        const c = html[0];
        // Handle comments below
        if (html.len > 2 and std.mem.eql(u8, html[0..3], "!--")) {
            self.tag_buffer.len = 0;
            self.state = State.comment;
            return 3;
        }

        if (ascii.isWhitespace(c) or c == '>' or c == '/') {
            try self.stack.append(allocator, tag_from_str(self.tag_buffer));
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

    /// Queue the tag's whitespace if it exists.
    fn queueWhitespace(self: *Self, tag: Tag) Error!void {
        if (tag_properties.get(tag).whitespace) |tag_ws| {
            if (self.pending_whitespace) |*pw| {
                pw.* = @enumFromInt(@max(@intFromEnum(pw.*), @intFromEnum(tag_ws)));
            } else {
                self.pending_whitespace = tag_ws;
            }
        }
    }

    //<strong >ekdy...</strong>
    //       ^~
    fn handleTagStartFound(
        self: *Self,
        html: []const u8,
        writer: *std.io.Writer,
    ) Error!usize {
        const tag = self.stack.getLast();

        // br is forced line break..
        if (tag == .br) {
            try writer.writeByte('\n');
            self.last_br = true;
        }

        try self.queueWhitespace(tag);

        const c = html[0];
        if (ascii.isWhitespace(c)) return 1;
        if (c == '/') {
            self.state = State.tag_end_found;
            return 1;
        }

        if (c == '>') {
            if (tag_properties.get(tag).is_void) {
                self.state = State.tag_end_found;
                return 0;
            }

            self.state = State.text;
            return 1;
        }

        self.state = State.attr_key;
        return 0;
    }

    //<strong >ekdy...</strong>
    //                 ^
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

    fn handleUnmatchedTag(self: *Self, end_tag: Tag) void {
        var found_idx = self.stack.items.len;
        while (found_idx > 0) : (found_idx -= 1) {
            if (end_tag == self.stack.items[found_idx - 1]) {
                _ = self.stack.orderedRemove(found_idx - 1);
                return;
            }
        }
    }

    //<strong >ekdy...</strong >
    //                        ^~
    fn handleTagEndFound(self: *Self, html: []const u8) Error!usize {
        const c = html[0];
        if (ascii.isWhitespace(c)) return 1;
        if (c == '>') {
            defer self.tag_buffer.len = 0;
            if (self.stack.getLastOrNull()) |tag| {
                try self.queueWhitespace(self.stack.getLast());
                const end_tag = tag_from_str(self.tag_buffer);
                if (self.tag_buffer.len > 0 and tag != end_tag) {
                    self.handleUnmatchedTag(end_tag);
                } else {
                    _ = self.stack.pop();
                }
            }

            self.state = State.text;
        }

        return 1;
    }

    //<a href="http://...">ekdy</a>
    //   ^~~~
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

    //<a href="http://...">ekdy</a>
    //        ^~~~~~~~~~~~
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

    //<!-- ekdy -->
    //    ^~~~~~
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

test "paragraph_single" {
    try expectConvert("foo", "<p> foo </p>");
}

test "paragraph_double" {
    try expectConvert("foo\n\nbar", "<p> foo </p><p>bar </p>");
}

test "paragraph_nested" {
    try expectConvert(
        "This is a simple example.",
        "<p>This is a <strong>simple</strong> example.</p>",
    );
}

test "nested_link" {
    try expectConvert(
        "Title\n\nParagraph with link.",
        \\<div><h1>Title</h1><p>Paragraph with <a href="http://wiki">link</a>.
        \\</p></div>
        ,
    );
}

test "nested_list" {
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

test "link_with_entity" {
    try expectConvert(
        "Title\n\nParagraph with link.",
        \\<div><h1>Title</h1><p>Paragraph with <a href="http://wiki&amp;">
        \\link</a>.</p></div>
        ,
    );
}

test "void_tags_with_br" {
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
    const exp = "Simple HTML Example\n\nWelcome\n\nThis paragraph contains an " ++
        "image:\n\nHere is a line break after this sentence:\nAnd here is the " ++
        "next line.\n\nEnter your name:";
    try expectConvert(exp, html);
}

test "ignore_tags_comment" {
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
    const exp = "Short &lt; &gt;\n\nHi! &#x00A8;";
    try expectConvert(exp, html);
}

test "unmatching" {
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

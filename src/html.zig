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
    is_rawtext: bool = false,
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
    .iframe = .{ .is_ignore = true, .is_rawtext = true },
    .map = .{ .is_ignore = true },
    .math = .{ .is_ignore = true },
    .noembed = .{ .is_ignore = true, .is_rawtext = true },
    .noframes = .{ .is_ignore = true, .is_rawtext = true },
    .noscript = .{ .is_ignore = true, .is_rawtext = true },
    .object = .{ .is_ignore = true },
    .picture = .{ .is_ignore = true },
    .script = .{ .is_ignore = true, .is_rawtext = true },
    .style = .{ .is_ignore = true, .is_rawtext = true },
    .svg = .{ .is_ignore = true },
    .template = .{ .is_ignore = true },
    .video = .{ .is_ignore = true },
    .plaintext = .{ .is_rawtext = true, .is_void = true },
    .textarea = .{ .is_rawtext = true },
    .title = .{ .is_rawtext = true },
    .xmp = .{ .is_rawtext = true },
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

pub fn is_valid_fs_tag_char(c: u8) bool {
    return ascii.isAlphabetic(c) or c == '!' or c == '?' or c == '/';
}

pub const TextExtractor = struct {
    const Self = @This();

    stack: ArrayList(Tag) = ArrayList(Tag){},

    // Buffer for current tag.
    tag_buffer: ArrayList(u8),

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
	plaintext,
    };

    pub fn init(allocator: Allocator) !Self {
        return Self{ .tag_buffer = try std.ArrayList(u8).initCapacity(allocator, 32) };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.stack.deinit(allocator);
        self.tag_buffer.deinit(allocator);
    }

    /// Convert a chunk of html to text.
    /// Can be repeteadly called for consecutive html chunks.
    /// When all the chunks are transformed eos must be called.
    pub fn convert(
        self: *Self,
        allocator: Allocator,
        html: []const u8,
        writer: *std.io.Writer,
    ) !void {
        while (self.cursor < html.len) {
            const curr_html = html[self.cursor..];
            self.cursor += try switch (self.state) {
                .text => self.handleText(allocator, curr_html, writer),
                .tag => self.handleTag(curr_html, writer),
                .tag_start => self.handleTagStart(allocator, curr_html),
                .tag_start_found => self.handleTagStartFound(curr_html, writer),
                .tag_end => self.handleTagEnd(allocator, curr_html),
                .tag_end_found => self.handleTagEndFound(curr_html),
                .attr_key => self.handleAttrKey(curr_html),
                .attr_val => self.handleAttrVal(curr_html),
                .comment => self.handleComment(curr_html),
		.plaintext => self.handlePlaintext(curr_html, writer),
            };
        }
        self.cursor -= html.len;
    }

    /// Writes any text remaining. Should be called after all html
    /// chunks are processed with convert.
    pub fn eos(self: *Self, writer: *std.io.Writer) !void {
        if (self.state == .tag) try writer.writeByte('<');
    }

    //<p>ekdy...</p>
    //   ^~~~~~~
    fn handleText(
        self: *Self,
        allocator: Allocator,
        html: []const u8,
        writer: *std.io.Writer,
    ) Error!usize {
        const c = html[0];
        const tag = self.stack.getLastOrNull();
        const tag_prop = if (tag) |t| tag_properties.get(t) else null;

        if (c == '<') {
            if (tag == null or !tag_prop.?.is_rawtext) {
                self.state = State.tag;
                return 1;
            }

	    // Rawtext state handled here.
            const tag_str = @tagName(tag.?);
            const tag_end_size = tag_str.len + 2;
            if (html.len >= tag_end_size and html[1] == '/') {
                const case_ins_tag = try std.ascii.allocLowerString(
                    allocator,
                    html[2..tag_end_size],
                );
                defer allocator.free(case_ins_tag);
                if (tag.? == tag_from_str(case_ins_tag)) {
                    try self.tag_buffer.appendSlice(allocator, tag_str);
                    self.state = State.tag_end_found;
                    return tag_end_size;
                }
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
    // ^
    //
    //<p>ekdy...</p>
    //           ^
    fn handleTag(self: *Self, html: []const u8, writer: *std.io.Writer) Error!usize {
        const c = html[0];
        if (!is_valid_fs_tag_char(c)) {
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
            self.tag_buffer.clearRetainingCapacity();
            self.state = State.comment;

            // Do not consume all 3, because it can abruptly finish
            // with: <!-->
            return 1;
        }

        if (ascii.isWhitespace(c) or c == '>' or c == '/') {
            try self.stack.append(allocator, tag_from_str(self.tag_buffer.items));
            self.tag_buffer.clearRetainingCapacity();
            self.state = State.tag_start_found;
            return if (ascii.isWhitespace(c)) 1 else 0;
        }

        try self.tag_buffer.append(allocator, ascii.toLower(c));
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
    fn handleTagEnd(self: *Self, allocator: Allocator, html: []const u8) Error!usize {
        const c = html[0];
        if (ascii.isWhitespace(c) or c == '>') {
            self.state = State.tag_end_found;
            return if (c == '>') 0 else 1;
        }

        try self.tag_buffer.append(allocator, ascii.toLower(c));
        return 1;
    }

    fn popMatching(self: *Self, end_tag: Tag) void {
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
        if (c != '>') return 1;

        defer self.tag_buffer.clearRetainingCapacity();
        if (self.stack.getLastOrNull()) |tag| {
	    // plaintext is a special tag.
	    if (tag == .plaintext) {
		self.state = .plaintext;
		return 1;
	    }

	    // Non void tag, or tag that does not end with /.
	    if (self.tag_buffer.items.len > 0) {
		const end_tag = tag_from_str(self.tag_buffer.items);
		try self.queueWhitespace(end_tag);
		self.popMatching(end_tag);
	    } else {
		// Tag buffer is empty if it's void tag, just pop it.
		_ = self.stack.pop();
	    }
        }

        self.state = State.text;
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
        if (html.len > 2 and std.mem.eql(u8, html[0..3], "-->")) {
            self.state = State.text;
            return 3;
        }

        return 1;
    }

    //<plaintext>ekdy...
    //           ^~~~~~~
    fn handlePlaintext(self: *Self, html: []const u8, writer: *std.io.Writer) Error!usize {
	_ = self;
	try writer.writeAll(html);
	return html.len;
    }
};

const talloc = std.testing.allocator;

/// Check if html to text works as expected.
fn expectConvert(expected: []const u8, html_text: []const u8) !void {
    var allocating = std.io.Writer.Allocating.init(talloc);
    defer allocating.deinit();
    var extractor = try TextExtractor.init(talloc);
    defer extractor.deinit(talloc);
    try extractor.convert(talloc, html_text, &allocating.writer);
    try extractor.eos(&allocating.writer);
    try std.testing.expectEqualStrings(expected, allocating.written());
}

/// Check if html to text (with entity decoding) works as expected.
fn expectConvertDe(expected: []const u8, html_text: []const u8) !void {
    var allocating = std.io.Writer.Allocating.init(talloc);
    defer allocating.deinit();
    var decoder = decoding.EntityDecoder.init(&allocating.writer);
    var extractor = try TextExtractor.init(talloc);
    defer extractor.deinit(talloc);
    try extractor.convert(talloc, html_text, &decoder.writer);
    try extractor.eos(&allocating.writer);
    try decoder.writer.flush();
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

    try expectConvertDe(text, html);
}

// Tests from the wild!
test "integration_mygithub" {
    try expectConvertFile("mygithub");
}

test "integration_w3c" {
    try expectConvertFile("w3c");
}

test "integration_vertex_cover" {
    try expectConvertFile("vertex_cover");
}

// Tests from:
// https://github.com/html5lib/html5lib-tests/tree/master/tree-construction.
// Expected strings obtained partially from python beautifulsoup package.

test "html5lib_tests1" {
    try expectConvertDe("Test", "Test");
    try expectConvertDe("One\n\nTwo", "<p>One<p>Two");
    try expectConvertDe("Line1\nLine2\nLine3\nLine4", "Line1<br>Line2<br>Line3<br>Line4");
    try expectConvertDe("", "<html>");
    try expectConvertDe("", "<head>");
    try expectConvertDe("", "<body>");
    try expectConvertDe("", "<html><head>");
    try expectConvertDe("", "<html><head></head>");
    try expectConvertDe("", "<html><head></head><body>");
    try expectConvertDe("", "<html><head></head><body></body>");
    try expectConvertDe("", "<html><head><body></body></html>");
    try expectConvertDe("", "<html><head></body></html>");
    try expectConvertDe("", "<html><head><body></html>");
    try expectConvertDe("", "<html><body></html>");
    try expectConvertDe("", "<body></html>");
    try expectConvertDe("", "<head></html>");
    try expectConvertDe("", "</head>");
    try expectConvertDe("", "</body>");
    try expectConvertDe("", "</html>");
    try expectConvertDe("", "<b><table><td><i></table>");
    try expectConvertDe("X", "<b><table><td></b><i></table>X");
    try expectConvertDe("Hello\n\nWorld", "<h1>Hello<h2>World");
    try expectConvertDe("XYZ", "<a><p>X<a>Y</a>Z</p></a>");
    try expectConvertDe("foobar", "<b><button>foo</b>bar");
    try expectConvertDe("foobar", "<!DOCTYPE html><span><button>foo</span>bar");
    try expectConvertDe("X", "<p><b><div><marquee></p></b></div>X");
    try expectConvertDe("<p>", "<script><div></script></div><title><p></title><p><p>");
    try expectConvertDe("--", "<!--><div>--<!-->");
    try expectConvertDe("", "<p><hr></p>");
    try expectConvertDe("X", "<select><b><option><select><option></b></select>X");
    try expectConvertDe(
        "XCY",
        "<a><table><td><a><table></table><a></tr><a></table><b>X</b>C<a>Y",
    );
    try expectConvertDe("012", "<a X>0<b>1<a Y>2");
    try expectConvertDe(
        "hello\n\nexcite!me!\nplease!",
        "<!-----><font><div>hello<table>excite!<b>me!<th><i>please!</tr><!--X-->",
    );
    try expectConvertDe(
        "hello\nworld\n\nhow\ndo\n\nyou",
        "<!DOCTYPE html><li>hello<li>world<ul>how<li>do</ul>you</body><!--do-->",
    );
    try expectConvertDe(
        "A\nB\nCD\nE",
        "<!DOCTYPE html>A<option>B<optgroup>C<select>D</option>E",
    );
    try expectConvertDe("<", "<");
    try expectConvertDe("<#", "<#");
    try expectConvertDe("", "</");
    try expectConvertDe("", "</#");
    try expectConvertDe("", "<?");
    try expectConvertDe("", "<?#");
    try expectConvertDe("", "<!");
    try expectConvertDe("", "<!#");
    try expectConvertDe("", "<?COMMENT?>");
    try expectConvertDe("", "<!COMMENT>");
    try expectConvertDe("", "</ COMMENT >");
    try expectConvertDe("", "<?COM--MENT?>");
    try expectConvertDe("", "<!COM--MENT>");
    try expectConvertDe("", "</ COM--MENT >");
    try expectConvertDe("", "<!DOCTYPE html><style> EOF");
    try expectConvertDe(
        "--> EOF",
        "<!DOCTYPE html><script> <!-- </script> --> </script> EOF",
    );
    try expectConvertDe("TEST", "<b><p></b>TEST");
    try expectConvertDe("TEST", "<p id=a><b><p id=b></b>TEST");
    try expectConvertDe("TEST", "<b id=a><p><b id=b></p></b>TEST");
    try expectConvertDe(
        "U-test\n\nTest",
        "<!DOCTYPE html><title>U-test</title><body><div><p>Test<u></p></div></body>",
    );
    try expectConvertDe("", "<!DOCTYPE html><font><table></font></table></font>");
    try expectConvertDe("hellocruelworld", "<font><p>hello<b>cruel</font>world");
    try expectConvertDe("TestTest", "<b>Test</i>Test");
    try expectConvertDe("AB\nC", "<b>A<cite>B<div>C");
    try expectConvertDe("AB\nCD", "<b>A<cite>B<div>C</cite>D");
    try expectConvertDe("AB\nCD", "<b>A<cite>B<div>C</b>D");
    try expectConvertDe("", "");
    try expectConvertDe("", "<DIV>");
    try expectConvertDe("abc", "<DIV> abc");
    try expectConvertDe("abc", "<DIV> abc <B>");
    try expectConvertDe("abc def", "<DIV> abc <B> def");
    try expectConvertDe("abc def", "<DIV> abc <B> def <I>");
    try expectConvertDe("abc def ghi", "<DIV> abc <B> def <I> ghi");
    try expectConvertDe("abc def ghi", "<DIV> abc <B> def <I> ghi <P>");
    try expectConvertDe("abc def ghi\n\njkl", "<DIV> abc <B> def <I> ghi <P> jkl");
    try expectConvertDe("abc def ghi\n\njkl", "<DIV> abc <B> def <I> ghi <P> jkl </B>");
    try expectConvertDe(
        "abc def ghi\n\njkl mno",
        "<DIV> abc <B> def <I> ghi <P> jkl </B> mno",
    );
    try expectConvertDe(
        "abc def ghi\n\njkl mno",
        "<DIV> abc <B> def <I> ghi <P> jkl </B> mno </I>",
    );
    try expectConvertDe(
        "abc def ghi\n\njkl mno pqr",
        "<DIV> abc <B> def <I> ghi <P> jkl </B> mno </I> pqr",
    );
    try expectConvertDe(
        "abc def ghi\n\njkl mno pqr",
        "<DIV> abc <B> def <I> ghi <P> jkl </B> mno </I> pqr </P>",
    );
    try expectConvertDe(
        "abc def ghi\n\njkl mno pqr\n\nstu",
        "<DIV> abc <B> def <I> ghi <P> jkl </B> mno </I> pqr </P> stu",
    );
    try expectConvertDe("", "<test attribute" ++ "-" ** 1024 ++ ">");
    try expectConvertDe(
        "aba\n\nbr\nx\n\naoe",
        "<a href=\"blah\">aba<table><a href=\"foo\">br<tr><td></td></tr>x</table>aoe",
    );
    try expectConvertDe(
        "aba\n\nbr\nx\n\naoe",
        "<a href=\"blah\">aba<table><tr><td><a href=\"foo\">br</td></tr>x</table>aoe",
    );
    try expectConvertDe(
        "aba\nbr\nx\n\naoe",
        "<table><a href=\"blah\">aba<tr><td><a href=\"foo\">br</td></tr>x</table>aoe",
    );
    try expectConvertDe("aaaabbaa", "<a href=a>aa<marquee>aa<a href=b>bb</marquee>aa");
    try expectConvertDe("", "<wbr><strike><code></strike><code><strike></code>");
    try expectConvertDe("foo", "<!DOCTYPE html><spacer>foo");
    try expectConvertDe("<meta><meta>", "<title><meta></title><link><title><meta></title>");
    try expectConvertDe("", "<style><!--</style><meta><script>--><link></script>");
    try expectConvertDe("", "<head><meta></head><link>");
    try expectConvertDe("X", "<table><tr><tr><td><td><span><th><span>X</table>");
    try expectConvertDe(
        "<p>",
        "<body><body><base><link><meta><title><p></title><body><p></body>",
    );
    try expectConvertDe("<p>", "<textarea><p></textarea>");
    try expectConvertDe("", "<p><image></p>");
    try expectConvertDe("", "<a><table><a></table><p><a><div><a>");
    try expectConvertDe("", "<head></p><meta><p>");
    try expectConvertDe("", "<head></html><meta><p>");
    try expectConvertDe("", "<b><table><td></b><i></table>");
    try expectConvertDe("", "<h1><h2>");
    try expectConvertDe("", "<a><p><a></a></p></a>");
    try expectConvertDe("", "<b><button></b></button></b>");
    try expectConvertDe("", "<p><b><div><marquee></p></b></div>");
    try expectConvertDe("", "<script></script></div><title></title><p><p>");
    try expectConvertDe("", "<select><b><option><select><option></b></select>");
    try expectConvertDe("", "<html><head><title></title><body></body></html>");
    try expectConvertDe("", "<a><table><td><a><table></table><a></tr><a></table><a>");
    try expectConvertDe(
        "",
        "<ul><li></li><div><li></div><li><li><div><li><address><li><b><em></b><li></ul>",
    );
    try expectConvertDe("a", "<ul><li><ul></li><li>a</li></ul></li></ul>");
    try expectConvertDe(
        "",
        "<frameset><frame><frameset><frame></frameset><noframes></noframes></frameset>",
    );
    try expectConvertDe("", "<h1><table><td><h3></table><h3></h1>");
    try expectConvertDe(
        "",
        "<table><colgroup><col><colgroup><col><col><col><colgroup><col><col><thead><tr>" ++
            "<td></table>",
    );
    try expectConvertDe("", "<table><col><tbody><col><tr><col><td><col></table><col>");
    try expectConvertDe(
        "",
        "<table><colgroup><tbody><colgroup><tr><colgroup><td><colgroup></table><colgroup>",
    );
    try expectConvertDe(
        "",
        "</strong></b></em></i></u></strike></s></blink></tt></pre></big></small></font>" ++
            "</select></h1></h2></h3></h4></h5></h6></body></br></a></img></title></span>" ++
            "</style></script></table></th></td></tr></frame></area></link></param></hr>" ++
            "</input></col></base></meta></basefont></bgsound></embed></spacer></p></dd>" ++
            "</dt></caption></colgroup></tbody></tfoot></thead></address></blockquote>" ++
            "</center></dir></div></dl></fieldset></listing></menu></ol></ul></li></nobr>" ++
            "</wbr></form></button></marquee></object></html></frameset></head></iframe>" ++
            "</image></isindex></noembed></noframes></noscript></optgroup></option>" ++
            "</plaintext></textarea>",
    );
    try expectConvertDe(
        "",
        "<table><tr></strong></b></em></i></u></strike></s></blink></tt></pre></big>" ++
            "</small></font></select></h1></h2></h3></h4></h5></h6></body></br></a>" ++
            "</img></title></span></style></script></table></th></td></tr></frame>" ++
            "</area></link></param></hr></input></col></base></meta></basefont>" ++
            "</bgsound></embed></spacer></p></dd></dt></caption></colgroup></tbody>" ++
            "</tfoot></thead></address></blockquote></center></dir></div></dl>" ++
            "</fieldset></listing></menu></ol></ul></li></nobr></wbr></form></button>" ++
            "</marquee></object></html></frameset></head></iframe></image></isindex>" ++
            "</noembed></noframes></noscript></optgroup></option></plaintext></textarea>",
    );
    try expectConvertDe("", "<frameset>");
}

test "html5lib_tests2" {
    try expectConvertDe("Test", "<!DOCTYPE html>Test");
    try expectConvertDe("test</div>test", "<textarea>test</div>test");
    try expectConvertDe("", "<table><td>");
    try expectConvertDe("test", "<table><td>test</tbody></table>");
    try expectConvertDe("test", "<frame>test");
    try expectConvertDe("", "<!DOCTYPE html><frameset>test");
    try expectConvertDe("", "<!DOCTYPE html><frameset> te st");
    try expectConvertDe("te st", "<!DOCTYPE html><frameset></frameset> te st");
    try expectConvertDe("", "<!DOCTYPE html><frameset><!DOCTYPE html>");
    try expectConvertDe("test", "<!DOCTYPE html><font><p><b>test</font>");
    try expectConvertDe("", "<!DOCTYPE html><dt><div><dd>");
    try expectConvertDe("", "<script></x");
    try expectConvertDe("<td>", "<table><plaintext><td>");
    try expectConvertDe("</plaintext>", "<plaintext></plaintext>");
    try expectConvertDe("TEST", "<!DOCTYPE html><table><tr>TEST");
    try expectConvertDe("", "<!DOCTYPE html><body t1=1><body t2=2><body t3=3 t4=4>");
    try expectConvertDe("", "</b test");
    try expectConvertDe("X", "<!DOCTYPE html></b test<b &=&amp>X");
    try expectConvertDe("", "<!doctypehtml><scrIPt type=text/x-foobar;baz>X</SCRipt");
    try expectConvertDe("&", "&");
    try expectConvertDe("&#", "&#");
    try expectConvertDe("&#X", "&#X");
    try expectConvertDe("&#x", "&#x");
    try expectConvertDe("&#45", "&#45");
    try expectConvertDe("&x-test", "&x-test");
    try expectConvertDe("", "<!doctypehtml><p><li>");
    try expectConvertDe("", "<!doctypehtml><p><dt>");
    try expectConvertDe("", "<!doctypehtml><p><dd>");
    try expectConvertDe("", "<!doctypehtml><p><form>");
    try expectConvertDe("X", "<!DOCTYPE html><p></P>X");
    try expectConvertDe("&AMP", "&AMP");
    try expectConvertDe("&AMp;", "&AMp;");
    try expectConvertDe(
        "",
        "<!DOCTYPE html><html><head></head><body>" ++
            "<thisISasillyTESTelementNameToMakeSureCrazyTagNamesArePARSEDcorrectLY>",
    );
    try expectConvertDe("XX", "<!DOCTYPE html>X</body>X");
    try expectConvertDe("", "<!DOCTYPE html><!-- X");
    try expectConvertDe(
        "test TEST\ntest",
        "<!DOCTYPE html><table><caption>test TEST</caption><td>test",
    );
    try expectConvertDe("", "<!DOCTYPE html><select><option><optgroup>");
    try expectConvertDe(
        "",
        "<!DOCTYPE html><select><optgroup><option></optgroup><option><select><option>",
    );
    try expectConvertDe("", "<!DOCTYPE html><select><optgroup><option><optgroup>");
    try expectConvertDe("foo\nbar", "<!DOCTYPE html><datalist><option>foo</datalist>bar");
    try expectConvertDe("", "<!DOCTYPE html><font><input><input></font>");
    try expectConvertDe("", "<!DOCTYPE html><!-- XXX - XXX -->");
    try expectConvertDe("", "<!DOCTYPE html><!-- XXX - XXX");
    try expectConvertDe("", "<!DOCTYPE html><!-- XXX - XXX - XXX -->");
    try expectConvertDe("", "<!DOCTYPE html> <!DOCTYPE html>");
    try expectConvertDe("test test", "test\ntest");
    try expectConvertDe("test</body>", "<!DOCTYPE html><body><title>test</body></title>");
    try expectConvertDe(
        "X",
        "<!DOCTYPE html><body><title>X</title><meta name=z><link rel=foo>" ++
            "<style>\nx { content:\"</style\" } </style>",
    );
    try expectConvertDe("", "<!DOCTYPE html><select><optgroup></optgroup></select>");
    try expectConvertDe("", "\n");
    try expectConvertDe("", "<!DOCTYPE html>  <html>");
    try expectConvertDe(
        "x",
        "<!DOCTYPE html><script>\n</script>  <title>x</title>  </head>",
    );
    try expectConvertDe("", "<!DOCTYPE html><html><body><html id=x>");
    try expectConvertDe("X", "<!DOCTYPE html>X</body><html id=\"x\">");
    try expectConvertDe("", "<!DOCTYPE html><head><html id=x>");
    try expectConvertDe("XX", "<!DOCTYPE html>X</html>X");
    try expectConvertDe("X", "<!DOCTYPE html>X</html>");
    try expectConvertDe("X\n\nX", "<!DOCTYPE html>X</html><p>X");
    try expectConvertDe("X", "<!DOCTYPE html>X<p/x/y/z>");
    try expectConvertDe("", "<!DOCTYPE html><!--x--");
    try expectConvertDe("", "<!DOCTYPE html><table><tr><td></p></table>");
    try expectConvertDe(">-->", "<!DOCTYPE <!DOCTYPE HTML>><!--<!--x-->-->");
    try expectConvertDe("", "<!doctype html><div><form></form><div></div></div>");
}

// test "html5lib_tests3" {
//     try expectConvert("", "<head></head><style></style>");
//     try expectConvert("", "<head></head><script></script>");
//     try expectConvert("", "<head></head><!-- --><style></style><!-- --><script></script>");
//     try expectConvert("x", "<head></head><!-- -->x<style></style><!-- --><script></script>");
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><html><head></head><body><pre>\n</pre></body></html>",
//     );
//     try expectConvert(
//         "foo",
//         "<!DOCTYPE html><html><head></head><body><pre>\nfoo</pre></body></html>",
//     );
//     try expectConvert(
//         "foo",
//         "<!DOCTYPE html><html><head></head><body><pre>\n\nfoo</pre></body></html>",
//     );
//     try expectConvert(
//         "foo",
//         "<!DOCTYPE html><html><head></head><body><pre>\nfoo\n</pre></body></html>",
//     );
//     try expectConvert(
//         "x",
//         "<!DOCTYPE html><html><head></head><body><pre>x</pre><span>\n</span></body></html>",
//     );
//     try expectConvert(
//         "xy",
//         "<!DOCTYPE html><html><head></head><body><pre>x\ny</pre></body></html>",
//     );
//     try expectConvert(
//         "xy",
//         "<!DOCTYPE html><html><head></head><body><pre>x<div>\ny</pre></body></html>",
//     );
//     try expectConvert("A", "<!DOCTYPE html><pre>&#x0a;&#x0a;A</pre>");
//     try expectConvert("", "<!DOCTYPE html><HTML><META><HEAD></HEAD></HTML>");
//     try expectConvert("", "<!DOCTYPE html><HTML><HEAD><head></HEAD></HTML>");
//     try expectConvert("foobarbaz", "<textarea>foo<span>bar</span><i>baz");
//     try expectConvert("foobarbaz", "<title>foo<span>bar</em><i>baz");
//     try expectConvert("", "<!DOCTYPE html><textarea>\n</textarea>");
//     try expectConvert("foo", "<!DOCTYPE html><textarea>\nfoo</textarea>");
//     try expectConvert("foo", "<!DOCTYPE html><textarea>\n\nfoo</textarea>");
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><html><head></head><body><ul><li><div><p><li></ul></body></html>",
//     );
//     try expectConvert("", "<!doctype html><nobr><nobr><nobr>");
//     try expectConvert("", "<!doctype html><nobr><nobr></nobr><nobr>");
//     try expectConvert("", "<!doctype html><html><body><p><table></table></body></html>");
//     try expectConvert("", "<p><table></table>");
// }

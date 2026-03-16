const std = @import("std");
const decoding = @import("decoding.zig");
const ascii = std.ascii;
const fs = std.fs;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Writer = std.io.Writer;

pub const Error = Allocator.Error || Writer.Error;

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

    // MathML tag
    annotation,
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
    is_rcdata: bool = false,
    is_rawtext: bool = false,
    is_preformatted: bool = false,
};

pub const tag_properties = std.EnumArray(Tag, TagProperty).initDefault(.{}, .{
    .area = .{ .is_void = true },
    .base = .{ .is_void = true },
    .br = .{ .is_void = true },
    .col = .{ .is_void = true },
    .embed = .{ .is_void = true },
    .frame = .{ .is_void = true },
    .hr = .{ .is_void = true },
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
    .iframe = .{ .is_ignore = true, .is_rawtext = true },
    .map = .{ .is_ignore = true },
    .annotation = .{ .is_ignore = true },
    .noembed = .{ .is_ignore = true, .is_rawtext = true },
    .noframes = .{ .is_ignore = true, .is_rawtext = true },

    // ekdy should act as if JS is disabled, therefore we treat
    // noscript and object as ordinary tags.
    // .noscript = .{ .is_ignore = true, .is_rawtext = true },
    // .object = .{ .is_ignore = true },
    .picture = .{ .is_ignore = true },
    .script = .{ .is_ignore = true, .is_rawtext = true },
    .style = .{ .is_ignore = true, .is_rawtext = true },
    // .svg = .{ .is_ignore = true },
    .template = .{ .is_ignore = true },
    .video = .{ .is_ignore = true },
    .plaintext = .{ .is_rawtext = true, .is_void = true },
    .textarea = .{ .is_rcdata = true, .is_preformatted = true },
    .title = .{ .is_rcdata = true, .is_ignore = true },
    .xmp = .{ .is_rawtext = true, .is_preformatted = true },
    .pre = .{ .is_preformatted = true },
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

pub fn TextExtractor(T: type) type {
    return struct {
        const Self = @This();

        /// Whitespace type to emit.
        pending_whitespace: ?Whitespace = null,

        /// Flag to indicate last written character is a <br>.
        last_br: bool = false,

        /// Flag to check if we have emitted any text.
        any_text: bool = false,

        /// Quote character used in attribute values.
        attr_val_quote: ?u8 = null,

        /// Flag to check if attribute value has started.
        attr_val_start: bool = false,

        /// Parser state.
        state: State = .text,

        cursor: usize = 0,

        /// Depth of ignore tags.
        ignore_depth: usize = 0,

        /// Depth of tags that output preformatted text.
        preformatted_depth: usize = 0,

        /// Output writer.
        out_writer: *Writer,

        stack: ArrayList(Tag) = ArrayList(Tag){},

        /// Buffer for current tag.
        tag_buffer: ArrayList(u8),

        /// Entity decoder.
        decoder: decoding.EntityDecoder,

        /// Text policy.
        policy: *T,

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
            script,
            script_escaped,
            script_double_escaped,
        };

        pub fn init(allocator: Allocator, out_writer: *Writer, policy: *T) !Self {
            return Self{
                .tag_buffer = try ArrayList(u8).initCapacity(allocator, 32),
                .out_writer = out_writer,
                .decoder = decoding.EntityDecoder.init(out_writer),
                .policy = policy,
            };
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
        ) !void {
            while (self.cursor < html.len) {
                const curr_html = html[self.cursor..];
                self.cursor += try switch (self.state) {
                    .text => self.handleText(allocator, curr_html),
                    .tag => self.handleTag(curr_html),
                    .tag_start => self.handleTagStart(allocator, curr_html),
                    .tag_start_found => self.handleTagStartFound(curr_html),
                    .tag_end => self.handleTagEnd(allocator, curr_html),
                    .tag_end_found => self.handleTagEndFound(curr_html),
                    .attr_key => self.handleAttrKey(curr_html),
                    .attr_val => self.handleAttrVal(curr_html),
                    .comment => self.handleComment(curr_html),
                    .plaintext => self.handlePlaintext(curr_html),
                    .script => self.handleScript(curr_html),
                    .script_escaped => self.handleScriptEscaped(curr_html),
                    .script_double_escaped => self.handleScriptDoubleEscaped(curr_html),
                };
            }
            self.cursor -= html.len;
        }

        /// Writes any text remaining. Should be called after all html
        /// chunks are processed with convert.
        pub fn eos(self: *Self) !void {
            switch (self.state) {
                .tag => {
                    try self.decoder_w().writeByte('<');
                },
                .tag_end => {
                    // Only output </ when tag buffer is empty.
                    // If any tag has started than output nothing.
                    if (self.tag_buffer.items.len == 0)
                        _ = try self.decoder_w().write("</");
                },
                else => {},
            }
            try self.decoder_w().flush();
        }

        fn decoder_w(self: *Self) *Writer {
            return &self.decoder.writer;
        }

        fn writer(self: *Self, tag_prop: ?TagProperty) *Writer {
            return if (tag_prop == null or !tag_prop.?.is_rawtext)
                self.decoder_w()
            else
                self.out_writer;
        }

        //<p>ekdy...</p>
        //   ^~~~~~~
        fn handleText(
            self: *Self,
            allocator: Allocator,
            html: []const u8,
        ) Error!usize {
            const c = html[0];
            const tag = self.stack.getLastOrNull();
            const tag_prop = if (tag) |t| tag_properties.get(t) else null;

            // Script is special.
            if (tag != null and tag.? == .script) {
                self.state = .script;
                return 0;
            }

            if (c == '<') {
                if (tag == null or (!tag_prop.?.is_rawtext and !tag_prop.?.is_rcdata)) {
                    self.state = State.tag;
                    return 1;
                }

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

            if (self.ignore_depth > 0) return 1;

            if (self.preformatted_depth == 0 and ascii.isWhitespace(c)) {
                // When last processed tag was br and it inserted a new line,
                // we do not queue a new space.
                if (self.pending_whitespace == null and !self.last_br) {
                    self.pending_whitespace = .space;
                }
                return 1;
            }

            // rawtext tags do not decode entities.
            const w = self.writer(tag_prop);

            if (self.pending_whitespace) |pw| {
                if (self.any_text) {
                    const ws = switch (pw) {
                        .space => " ",
                        .single_break => "\n",
                        .double_break => "\n\n",
                    };
                    try w.writeAll(ws);
                }
            }

            try w.writeByte(c);
            self.any_text = true;
            self.pending_whitespace = null;
            self.last_br = false;
            return 1;
        }

        //<p>ekdy...</p>
        // ^
        //
        //<p>ekdy...</p>
        //           ^
        fn handleTag(self: *Self, html: []const u8) Error!usize {
            const c = html[0];
            if (!is_valid_fs_tag_char(c)) {
                try self.decoder_w().writeByte('<');
                self.state = State.text;
                return 0;
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
                self.state = State.comment;

                // Do not consume all 3, because it can abruptly finish
                // with: <!-->
                return 1;
            }

            if (ascii.isWhitespace(c) or c == '>' or c == '/') {
                const tag = tag_from_str(self.tag_buffer.items);
                try self.stack.append(allocator, tag);
                if (tag_properties.get(tag).is_ignore)
                    self.ignore_depth += 1;

                if (tag_properties.get(tag).is_preformatted)
                    self.preformatted_depth += 1;

                self.tag_buffer.clearRetainingCapacity();
                self.state = State.tag_start_found;
                return if (ascii.isWhitespace(c)) 1 else 0;
            }

            try self.tag_buffer.append(allocator, ascii.toLower(c));
            return 1;
        }

        /// Queue whitespace if its rank is higher than the current pending.
        fn queueWhitespace(self: *Self, ws: Whitespace) Error!void {
            if (self.pending_whitespace) |*pw| {
                pw.* = @enumFromInt(@max(@intFromEnum(pw.*), @intFromEnum(ws)));
            } else {
                self.pending_whitespace = ws;
            }
        }

        //<strong >ekdy...</strong>
        //       ^~
        fn handleTagStartFound(self: *Self, html: []const u8) Error!usize {
            const tag = self.stack.getLast();

            // br is forced line break..
            if (tag == .br) {
                try self.writer(tag_properties.get(tag)).writeByte('\n');
                self.last_br = true;
            }

            if (@hasDecl(T, "onTagStart")) {
                if (try self.policy.onTagStart(tag, self.writer(tag_properties.get(tag)))) |ws| {
                    try self.queueWhitespace(ws);
                }
            }

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
                    const tp = tag_properties.get(end_tag);
                    if (tp.is_ignore)
                        self.ignore_depth -|= 1;

                    if (tp.is_preformatted)
                        self.preformatted_depth -|= 1;

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
                    if (@hasDecl(T, "onTagEnd")) {
                        if (try self.policy.onTagEnd(
                            end_tag,
                            self.writer(tag_properties.get(end_tag)),
                        )) |ws| {
                            try self.queueWhitespace(ws);
                        }
                    }
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
        fn handlePlaintext(self: *Self, html: []const u8) Error!usize {
            try self.out_writer.writeAll(html);
            return html.len;
        }

        // Check if given tag prefix is proper tag. For example if
        // '</script' is given will try to match a proper </script> tag by
        // relying to the rules of tag matching (whitespace etc.). If
        // there is no match will return 0, otherwise will return number
        // of bytes that points after the tag match. This function is
        // useful to avoid complex script sub-state machine, rather than
        // having a full sub-state machine this helper handles boilerplate
        // tag matching logic.
        fn checkTagPrefixMatch(html: []const u8, tag_prefix: []const u8) usize {
            if (html.len < tag_prefix.len + 1)
                return html.len;

            if (!std.mem.eql(u8, html[0..tag_prefix.len], tag_prefix))
                return 0;

            var script_match = false;
            for (html[tag_prefix.len..], 1..) |c, i| {
                if (c == '>')
                    return tag_prefix.len + i;

                if (!ascii.isWhitespace(c))
                    if (!script_match) return tag_prefix.len;

                script_match = true;
            }

            // Consumed everything
            return html.len;
        }

        // Handle exit from a script tag here.
        fn endScript(self: *Self) void {
            // Stack must have the script tag
            const st = self.stack.pop() orelse unreachable;
            if (st != .script)
                unreachable;

            self.state = .text;
            self.ignore_depth -|= 1;
        }

        // <script>ekdy...</script>
        //         ^~~~~~~
        // FIXME: This part cannot be simply converted to SIMD.
        // for SIMD we need to first look for a '<' match.
        fn handleScript(self: *Self, html: []const u8) Error!usize {
            const check_adv = checkTagPrefixMatch(html, "</script");
            if (check_adv > 0) {
                self.endScript();
                return check_adv;
            }

            const escape_tok = "<!--";
            if (std.mem.eql(u8, html[0..escape_tok.len], escape_tok)) {
                self.state = .script_escaped;
                return escape_tok.len;
            }

            return 1;
        }

        // <script>ekdy <!-- ekdy....
        //                  ^~~~~~~~~
        fn handleScriptEscaped(self: *Self, html: []const u8) Error!usize {
            const esc_end_tok = "-->";
            if (html.len < esc_end_tok.len)
                return html.len;

            if (std.mem.eql(u8, html[0..esc_end_tok.len], esc_end_tok)) {
                self.state = .script;
                return esc_end_tok.len;
            }

            const start_adv = checkTagPrefixMatch(html, "<script");
            if (start_adv > 0) {
                self.state = .script_double_escaped;
                return start_adv;
            }

            const end_adv = checkTagPrefixMatch(html, "</script");
            if (end_adv > 0) {
                self.endScript();
                return end_adv;
            }

            return 1;
        }

        // <script>ekdy <!-- ... <script> ekdy...
        //                               ^~~~~~~~
        fn handleScriptDoubleEscaped(self: *Self, html: []const u8) Error!usize {
            const esc_end_tok = "-->";
            if (html.len < esc_end_tok.len)
                return html.len;

            if (std.mem.eql(u8, html[0..esc_end_tok.len], esc_end_tok)) {
                self.state = .script;
                return esc_end_tok.len;
            }

            const end_adv = checkTagPrefixMatch(html, "</script");
            if (end_adv > 0) {
                self.state = .script_escaped;
                return end_adv;
            }

            return 1;
        }
    };
}

const talloc = std.testing.allocator;

/// Check if html to text works as expected.
fn expectConvert(expected: []const u8, html_text: []const u8) !void {
    var allocating = std.io.Writer.Allocating.init(talloc);
    defer allocating.deinit();
    const InnerText = @import("policy/InnerText.zig");
    var policy = InnerText{};
    var extractor = try TextExtractor(InnerText).init(talloc, &allocating.writer, &policy);
    defer extractor.deinit(talloc);
    try extractor.convert(talloc, html_text);
    try extractor.eos();
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
    const exp = "Short < >\n\nHi! ¨";
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

    try expectConvert(text, html);
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

fn expectHTML5(comptime ekdytest_filename: []const u8, skip_tests: []const u64) !void {
    const src_dir = fs.path.dirname(@src().file) orelse "";
    const ekdytest_path = try fs.path.join(
        talloc,
        &[_][]const u8{ src_dir, "test-resource", "html5lib-expectations", ekdytest_filename },
    );
    defer talloc.free(ekdytest_path);

    const ekdytest_file = try fs.cwd().openFile(ekdytest_path, .{});
    defer ekdytest_file.close();

    const read_buf = try talloc.alloc(u8, (try ekdytest_file.stat()).size);
    defer talloc.free(read_buf);
    var et_reader = ekdytest_file.reader(read_buf);
    const reader = &et_reader.interface;

    var html_da = ArrayList(u8){};
    var text_da = ArrayList(u8){};
    defer {
        html_da.deinit(talloc);
        text_da.deinit(talloc);
    }
    var in_data = false;
    var test_id: u64 = 0;
    var skip_i: u64 = 0;
    while (reader.takeDelimiterInclusive('\n')) |line| {
        if (std.mem.eql(u8, line, "#data\n")) {
            in_data = true;
            if (html_da.items.len > 0) {
                defer text_da.clearRetainingCapacity();
                defer html_da.clearRetainingCapacity();
                defer test_id += 1;
                // Skip the given test ids.
                if (skip_i < skip_tests.len and test_id == skip_tests[skip_i]) {
                    skip_i += 1;
                    continue;
                }
                _ = text_da.pop();
                _ = html_da.pop();
                expectConvert(
                    text_da.items,
                    html_da.items,
                ) catch |terr| {
                    std.debug.print("failed test_id={} on '{s}'\n", .{
                        test_id,
                        html_da.items,
                    });
                    return terr;
                };
            }
        } else if (std.mem.eql(u8, line, "#text\n")) {
            in_data = false;
        } else if (in_data) {
            try html_da.appendSlice(talloc, line);
        } else {
            try text_da.appendSlice(talloc, line);
        }
    } else |err| {
        if (err != error.StreamTooLong) return err;
        _ = text_da.pop();
        _ = html_da.pop();
        expectConvert(text_da.items, html_da.items) catch |terr| {
            std.debug.print("failed on {s}\n", .{html_da.items});
            return terr;
        };
    }
}

test "html5lib_tests1" {
    try expectHTML5("tests1.ekdytest", &.{34, 78, 79});
}

// Tests from:
// https://github.com/html5lib/html5lib-tests/tree/master/tree-construction.
// Expected strings obtained partially from python beautifulsoup package.

// test "html5lib_tests1" {
//     try expectConvert("Test", "Test");
//     try expectConvert("One\n\nTwo", "<p>One<p>Two");
//     try expectConvert("Line1\nLine2\nLine3\nLine4", "Line1<br>Line2<br>Line3<br>Line4");
//     try expectConvert("", "<html>");
//     try expectConvert("", "<head>");
//     try expectConvert("", "<body>");
//     try expectConvert("", "<html><head>");
//     try expectConvert("", "<html><head></head>");
//     try expectConvert("", "<html><head></head><body>");
//     try expectConvert("", "<html><head></head><body></body>");
//     try expectConvert("", "<html><head><body></body></html>");
//     try expectConvert("", "<html><head></body></html>");
//     try expectConvert("", "<html><head><body></html>");
//     try expectConvert("", "<html><body></html>");
//     try expectConvert("", "<body></html>");
//     try expectConvert("", "<head></html>");
//     try expectConvert("", "</head>");
//     try expectConvert("", "</body>");
//     try expectConvert("", "</html>");
//     try expectConvert("", "<b><table><td><i></table>");
//     try expectConvert("X", "<b><table><td></b><i></table>X");
//     try expectConvert("Hello\n\nWorld", "<h1>Hello<h2>World");
//     try expectConvert("XYZ", "<a><p>X<a>Y</a>Z</p></a>");
//     try expectConvert("foobar", "<b><button>foo</b>bar");
//     try expectConvert("foobar", "<!DOCTYPE html><span><button>foo</span>bar");
//     try expectConvert("X", "<p><b><div><marquee></p></b></div>X");
//     try expectConvert("<p>", "<script><div></script></div><title><p></title><p><p>");
//     try expectConvert("--", "<!--><div>--<!-->");
//     try expectConvert("", "<p><hr></p>");
//     try expectConvert("X", "<select><b><option><select><option></b></select>X");
//     try expectConvert(
//         "XCY",
//         "<a><table><td><a><table></table><a></tr><a></table><b>X</b>C<a>Y",
//     );
//     try expectConvert("012", "<a X>0<b>1<a Y>2");
//     try expectConvert(
//         "hello\n\nexcite!me!\nplease!",
//         "<!-----><font><div>hello<table>excite!<b>me!<th><i>please!</tr><!--X-->",
//     );
//     try expectConvert(
//         "hello\nworld\n\nhow\ndo\n\nyou",
//         "<!DOCTYPE html><li>hello<li>world<ul>how<li>do</ul>you</body><!--do-->",
//     );
//     try expectConvert(
//         "A\nB\nCD\nE",
//         "<!DOCTYPE html>A<option>B<optgroup>C<select>D</option>E",
//     );
//     try expectConvert("<", "<");
//     try expectConvert("<#", "<#");
//     try expectConvert("", "</");
//     try expectConvert("", "</#");
//     try expectConvert("", "<?");
//     try expectConvert("", "<?#");
//     try expectConvert("", "<!");
//     try expectConvert("", "<!#");
//     try expectConvert("", "<?COMMENT?>");
//     try expectConvert("", "<!COMMENT>");
//     try expectConvert("", "</ COMMENT >");
//     try expectConvert("", "<?COM--MENT?>");
//     try expectConvert("", "<!COM--MENT>");
//     try expectConvert("", "</ COM--MENT >");
//     try expectConvert("", "<!DOCTYPE html><style> EOF");
//     try expectConvert(
//         "--> EOF",
//         "<!DOCTYPE html><script> <!-- </script> --> </script> EOF",
//     );
//     try expectConvert("TEST", "<b><p></b>TEST");
//     try expectConvert("TEST", "<p id=a><b><p id=b></b>TEST");
//     try expectConvert("TEST", "<b id=a><p><b id=b></p></b>TEST");
//     try expectConvert(
//         "U-test\n\nTest",
//         "<!DOCTYPE html><title>U-test</title><body><div><p>Test<u></p></div></body>",
//     );
//     try expectConvert("", "<!DOCTYPE html><font><table></font></table></font>");
//     try expectConvert("hellocruelworld", "<font><p>hello<b>cruel</font>world");
//     try expectConvert("TestTest", "<b>Test</i>Test");
//     try expectConvert("AB\nC", "<b>A<cite>B<div>C");
//     try expectConvert("AB\nCD", "<b>A<cite>B<div>C</cite>D");
//     try expectConvert("AB\nCD", "<b>A<cite>B<div>C</b>D");
//     try expectConvert("", "");
//     try expectConvert("", "<DIV>");
//     try expectConvert("abc", "<DIV> abc");
//     try expectConvert("abc", "<DIV> abc <B>");
//     try expectConvert("abc def", "<DIV> abc <B> def");
//     try expectConvert("abc def", "<DIV> abc <B> def <I>");
//     try expectConvert("abc def ghi", "<DIV> abc <B> def <I> ghi");
//     try expectConvert("abc def ghi", "<DIV> abc <B> def <I> ghi <P>");
//     try expectConvert("abc def ghi\n\njkl", "<DIV> abc <B> def <I> ghi <P> jkl");
//     try expectConvert("abc def ghi\n\njkl", "<DIV> abc <B> def <I> ghi <P> jkl </B>");
//     try expectConvert(
//         "abc def ghi\n\njkl mno",
//         "<DIV> abc <B> def <I> ghi <P> jkl </B> mno",
//     );
//     try expectConvert(
//         "abc def ghi\n\njkl mno",
//         "<DIV> abc <B> def <I> ghi <P> jkl </B> mno </I>",
//     );
//     try expectConvert(
//         "abc def ghi\n\njkl mno pqr",
//         "<DIV> abc <B> def <I> ghi <P> jkl </B> mno </I> pqr",
//     );
//     try expectConvert(
//         "abc def ghi\n\njkl mno pqr",
//         "<DIV> abc <B> def <I> ghi <P> jkl </B> mno </I> pqr </P>",
//     );
//     try expectConvert(
//         "abc def ghi\n\njkl mno pqr\n\nstu",
//         "<DIV> abc <B> def <I> ghi <P> jkl </B> mno </I> pqr </P> stu",
//     );
//     try expectConvert("", "<test attribute" ++ "-" ** 1024 ++ ">");
//     try expectConvert(
//         "aba\n\nbr\nx\n\naoe",
//         "<a href=\"blah\">aba<table><a href=\"foo\">br<tr><td></td></tr>x</table>aoe",
//     );
//     try expectConvert(
//         "aba\n\nbr\nx\n\naoe",
//         "<a href=\"blah\">aba<table><tr><td><a href=\"foo\">br</td></tr>x</table>aoe",
//     );
//     try expectConvert(
//         "aba\nbr\nx\n\naoe",
//         "<table><a href=\"blah\">aba<tr><td><a href=\"foo\">br</td></tr>x</table>aoe",
//     );
//     try expectConvert("aaaabbaa", "<a href=a>aa<marquee>aa<a href=b>bb</marquee>aa");
//     try expectConvert("", "<wbr><strike><code></strike><code><strike></code>");
//     try expectConvert("foo", "<!DOCTYPE html><spacer>foo");
//     try expectConvert("<meta>\n\n<meta>", "<title><meta></title><link><title><meta></title>");
//     try expectConvert("", "<style><!--</style><meta><script>--><link></script>");
//     try expectConvert("", "<head><meta></head><link>");
//     try expectConvert("X", "<table><tr><tr><td><td><span><th><span>X</table>");
//     try expectConvert(
//         "<p>",
//         "<body><body><base><link><meta><title><p></title><body><p></body>",
//     );
//     try expectConvert("<p>", "<textarea><p></textarea>");
//     try expectConvert("", "<p><image></p>");
//     try expectConvert("", "<a><table><a></table><p><a><div><a>");
//     try expectConvert("", "<head></p><meta><p>");
//     try expectConvert("", "<head></html><meta><p>");
//     try expectConvert("", "<b><table><td></b><i></table>");
//     try expectConvert("", "<h1><h2>");
//     try expectConvert("", "<a><p><a></a></p></a>");
//     try expectConvert("", "<b><button></b></button></b>");
//     try expectConvert("", "<p><b><div><marquee></p></b></div>");
//     try expectConvert("", "<script></script></div><title></title><p><p>");
//     try expectConvert("", "<select><b><option><select><option></b></select>");
//     try expectConvert("", "<html><head><title></title><body></body></html>");
//     try expectConvert("", "<a><table><td><a><table></table><a></tr><a></table><a>");
//     try expectConvert(
//         "",
//         "<ul><li></li><div><li></div><li><li><div><li><address><li><b><em></b><li></ul>",
//     );
//     try expectConvert("a", "<ul><li><ul></li><li>a</li></ul></li></ul>");
//     try expectConvert(
//         "",
//         "<frameset><frame><frameset><frame></frameset><noframes></noframes></frameset>",
//     );
//     try expectConvert("", "<h1><table><td><h3></table><h3></h1>");
//     try expectConvert(
//         "",
//         "<table><colgroup><col><colgroup><col><col><col><colgroup><col><col><thead><tr>" ++
//             "<td></table>",
//     );
//     try expectConvert("", "<table><col><tbody><col><tr><col><td><col></table><col>");
//     try expectConvert(
//         "",
//         "<table><colgroup><tbody><colgroup><tr><colgroup><td><colgroup></table><colgroup>",
//     );
//     try expectConvert(
//         "",
//         "</strong></b></em></i></u></strike></s></blink></tt></pre></big></small></font>" ++
//             "</select></h1></h2></h3></h4></h5></h6></body></br></a></img></title></span>" ++
//             "</style></script></table></th></td></tr></frame></area></link></param></hr>" ++
//             "</input></col></base></meta></basefont></bgsound></embed></spacer></p></dd>" ++
//             "</dt></caption></colgroup></tbody></tfoot></thead></address></blockquote>" ++
//             "</center></dir></div></dl></fieldset></listing></menu></ol></ul></li></nobr>" ++
//             "</wbr></form></button></marquee></object></html></frameset></head></iframe>" ++
//             "</image></isindex></noembed></noframes></noscript></optgroup></option>" ++
//             "</plaintext></textarea>",
//     );
//     try expectConvert(
//         "",
//         "<table><tr></strong></b></em></i></u></strike></s></blink></tt></pre></big>" ++
//             "</small></font></select></h1></h2></h3></h4></h5></h6></body></br></a>" ++
//             "</img></title></span></style></script></table></th></td></tr></frame>" ++
//             "</area></link></param></hr></input></col></base></meta></basefont>" ++
//             "</bgsound></embed></spacer></p></dd></dt></caption></colgroup></tbody>" ++
//             "</tfoot></thead></address></blockquote></center></dir></div></dl>" ++
//             "</fieldset></listing></menu></ol></ul></li></nobr></wbr></form></button>" ++
//             "</marquee></object></html></frameset></head></iframe></image></isindex>" ++
//             "</noembed></noframes></noscript></optgroup></option></plaintext></textarea>",
//     );
//     try expectConvert("", "<frameset>");
// }

// test "html5lib_tests2" {
//     try expectConvert("Test", "<!DOCTYPE html>Test");
//     try expectConvert("test</div>test", "<textarea>test</div>test");
//     try expectConvert("", "<table><td>");
//     try expectConvert("test", "<table><td>test</tbody></table>");
//     try expectConvert("test", "<frame>test");
//     try expectConvert("", "<!DOCTYPE html><frameset>test");
//     try expectConvert("", "<!DOCTYPE html><frameset> te st");
//     try expectConvert("te st", "<!DOCTYPE html><frameset></frameset> te st");
//     try expectConvert("", "<!DOCTYPE html><frameset><!DOCTYPE html>");
//     try expectConvert("test", "<!DOCTYPE html><font><p><b>test</font>");
//     try expectConvert("", "<!DOCTYPE html><dt><div><dd>");
//     try expectConvert("", "<script></x");
//     try expectConvert("<td>", "<table><plaintext><td>");
//     try expectConvert("</plaintext>", "<plaintext></plaintext>");
//     try expectConvert("TEST", "<!DOCTYPE html><table><tr>TEST");
//     try expectConvert("", "<!DOCTYPE html><body t1=1><body t2=2><body t3=3 t4=4>");
//     try expectConvert("", "</b test");
//     try expectConvert("X", "<!DOCTYPE html></b test<b &=&amp>X");
//     try expectConvert("", "<!doctypehtml><scrIPt type=text/x-foobar;baz>X</SCRipt");
//     try expectConvert("&", "&");
//     try expectConvert("&#", "&#");
//     try expectConvert("&#X", "&#X");
//     try expectConvert("&#x", "&#x");
//     try expectConvert("&#45", "&#45");
//     try expectConvert("&x-test", "&x-test");
//     try expectConvert("", "<!doctypehtml><p><li>");
//     try expectConvert("", "<!doctypehtml><p><dt>");
//     try expectConvert("", "<!doctypehtml><p><dd>");
//     try expectConvert("", "<!doctypehtml><p><form>");
//     try expectConvert("X", "<!DOCTYPE html><p></P>X");
//     try expectConvert("&AMP", "&AMP");
//     try expectConvert("&AMp;", "&AMp;");
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><html><head></head><body>" ++
//             "<thisISasillyTESTelementNameToMakeSureCrazyTagNamesArePARSEDcorrectLY>",
//     );
//     try expectConvert("XX", "<!DOCTYPE html>X</body>X");
//     try expectConvert("", "<!DOCTYPE html><!-- X");
//     try expectConvert(
//         "test TEST\ntest",
//         "<!DOCTYPE html><table><caption>test TEST</caption><td>test",
//     );
//     try expectConvert("", "<!DOCTYPE html><select><option><optgroup>");
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><select><optgroup><option></optgroup><option><select><option>",
//     );
//     try expectConvert("", "<!DOCTYPE html><select><optgroup><option><optgroup>");
//     try expectConvert("foo\nbar", "<!DOCTYPE html><datalist><option>foo</datalist>bar");
//     try expectConvert("", "<!DOCTYPE html><font><input><input></font>");
//     try expectConvert("", "<!DOCTYPE html><!-- XXX - XXX -->");
//     try expectConvert("", "<!DOCTYPE html><!-- XXX - XXX");
//     try expectConvert("", "<!DOCTYPE html><!-- XXX - XXX - XXX -->");
//     try expectConvert("", "<!DOCTYPE html> <!DOCTYPE html>");
//     try expectConvert("test test", "test\ntest");
//     try expectConvert("test</body>", "<!DOCTYPE html><body><title>test</body></title>");
//     try expectConvert(
//         "X",
//         "<!DOCTYPE html><body><title>X</title><meta name=z><link rel=foo>" ++
//             "<style>\nx { content:\"</style\" } </style>",
//     );
//     try expectConvert("", "<!DOCTYPE html><select><optgroup></optgroup></select>");
//     try expectConvert("", "\n");
//     try expectConvert("", "<!DOCTYPE html>  <html>");
//     try expectConvert(
//         "x",
//         "<!DOCTYPE html><script>\n</script>  <title>x</title>  </head>",
//     );
//     try expectConvert("", "<!DOCTYPE html><html><body><html id=x>");
//     try expectConvert("X", "<!DOCTYPE html>X</body><html id=\"x\">");
//     try expectConvert("", "<!DOCTYPE html><head><html id=x>");
//     try expectConvert("XX", "<!DOCTYPE html>X</html>X");
//     try expectConvert("X", "<!DOCTYPE html>X</html>");
//     try expectConvert("X\n\nX", "<!DOCTYPE html>X</html><p>X");
//     try expectConvert("X", "<!DOCTYPE html>X<p/x/y/z>");
//     try expectConvert("", "<!DOCTYPE html><!--x--");
//     try expectConvert("", "<!DOCTYPE html><table><tr><td></p></table>");
//     try expectConvert(">-->", "<!DOCTYPE <!DOCTYPE HTML>><!--<!--x-->-->");
//     try expectConvert("", "<!doctype html><div><form></form><div></div></div>");
// }

// test "html5lib_tests3" {
//     try expectConvert("", "<head></head><style></style>");
//     try expectConvert("", "<head></head><script></script>");
//     try expectConvert("", "<head></head><!-- --><style></style><!-- --><script></script>");
//     try expectConvert("x", "<head></head><!-- -->x<style></style><!-- --><script></script>");
//     try expectConvert(
//         "\n",
//         "<!DOCTYPE html><html><head></head><body><pre>\n</pre></body></html>",
//     );
//     try expectConvert(
//         "\nfoo",
//         "<!DOCTYPE html><html><head></head><body><pre>\nfoo</pre></body></html>",
//     );
//     try expectConvert(
//         "\n\nfoo",
//         "<!DOCTYPE html><html><head></head><body><pre>\n\nfoo</pre></body></html>",
//     );
//     try expectConvert(
//         "\nfoo\n",
//         "<!DOCTYPE html><html><head></head><body><pre>\nfoo\n</pre></body></html>",
//     );
//     try expectConvert(
//         "x",
//         "<!DOCTYPE html><html><head></head><body><pre>x</pre><span>\n</span></body></html>",
//     );
//     try expectConvert(
//         "x\ny",
//         "<!DOCTYPE html><html><head></head><body><pre>x\ny</pre></body></html>",
//     );
//     try expectConvert(
//         "x\n\ny",
//         "<!DOCTYPE html><html><head></head><body><pre>x<div>\ny</pre></body></html>",
//     );
//     try expectConvert("\n\nA", "<!DOCTYPE html><pre>&#x0a;&#x0a;A</pre>");
//     try expectConvert("", "<!DOCTYPE html><HTML><META><HEAD></HEAD></HTML>");
//     try expectConvert("", "<!DOCTYPE html><HTML><HEAD><head></HEAD></HTML>");
//     try expectConvert("foo<span>bar</span><i>baz", "<textarea>foo<span>bar</span><i>baz");
//     try expectConvert("foo<span>bar</em><i>baz", "<title>foo<span>bar</em><i>baz");
//     try expectConvert("\n", "<!DOCTYPE html><textarea>\n</textarea>");
//     try expectConvert("\nfoo", "<!DOCTYPE html><textarea>\nfoo</textarea>");
//     try expectConvert("\n\nfoo", "<!DOCTYPE html><textarea>\n\nfoo</textarea>");
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><html><head></head><body><ul><li><div><p><li></ul></body></html>",
//     );
//     try expectConvert("", "<!doctype html><nobr><nobr><nobr>");
//     try expectConvert("", "<!doctype html><nobr><nobr></nobr><nobr>");
//     try expectConvert("", "<!doctype html><html><body><p><table></table></body></html>");
//     try expectConvert("", "<p><table></table>");
// }

// test "html5lib_tests4" {
//     try expectConvert("direct div content", "direct div content");
//     try expectConvert("direct textarea content", "direct textarea content");
//     try expectConvert(
//         "textarea content with pseudo markup",
//         "textarea content with <em>pseudo</em> <foo>markup",
//     );
//     try expectConvert(
//         "this is CDATA inside a",
//         "this is &#x0043;DATA inside a <style> element",
//     );
//     try expectConvert("", "</plaintext>");
//     try expectConvert("setting html's innerHTML", "setting html's innerHTML");
//     try expectConvert("setting head's innerHTML", "<title>setting head's innerHTML</title>");
//     try expectConvert("direct\n\ncontent", "direct <title> content");
//     try expectConvert("", "<!-- inside </script> -->");
// }

// test "html5lib_tests5" {
//     try expectConvert("x", "<style> <!-- </style>x");
//     try expectConvert("--> x", "<style> <!-- </style> --> </style>x");
//     try expectConvert("x", "<style> <!--> </style>x");
//     try expectConvert("x", "<style> <!---> </style>x");
//     try expectConvert("x", "<iframe> <!---> </iframe>x");
//     try expectConvert("->x --> x", "<iframe> <!--- </iframe>->x</iframe> --> </iframe>x");
//     try expectConvert("--> x", "<script> <!-- </script> --> </script>x");
//     try expectConvert("<!--\n\n--> x", "<title> <!-- </title> --> </title>x");
//     try expectConvert(
//         " <!--- ->x --> x",
//         "<textarea> <!--- </textarea>->x</textarea> --> </textarea>x",
//     );
//     try expectConvert("x", "<style> <!</-- </style>x");
//     try expectConvert("", "<p><xmp></xmp>");
//     try expectConvert(" <!-- > --> ", "<xmp> <!-- > --> </xmp>");
//     try expectConvert("&", "<title>&amp;</title>");
//     try expectConvert("<!--&-->", "<title><!--&amp;--></title>");
//     try expectConvert("<!--", "<title><!--</title>");
//     try expectConvert("", "<noscript><!--</noscript>--></noscript>");
//     try expectConvert("", "<noscript><!--</noscript>--></noscript>");
// }

// test "html5lib_tests6" {
//     try expectConvert("", "<!doctype html></head> <head>");
//     try expectConvert("", "<!doctype html><form><div></form><div>");
//     try expectConvert("&", "<!doctype html><title>&amp;</title>");
//     try expectConvert("<!--&-->", "<!doctype html><title><!--&amp;--></title>");
//     try expectConvert("", "<!doctype>");
//     try expectConvert("", "<!---x");
//     try expectConvert("", "<body>\n<div>");
//     try expectConvert("foo", "<frameset></frameset>\nfoo");
//     try expectConvert("", "<frameset></frameset>\n<noframes>");
//     try expectConvert("", "<frameset></frameset>\n<div>");
//     try expectConvert("", "<frameset></frameset>\n</html>");
//     try expectConvert("", "<frameset></frameset>\n</div>");
//     try expectConvert("", "<form><form>");
//     try expectConvert("", "<button><button>");
//     try expectConvert("", "<table><tr><td></th>");
//     try expectConvert("", "<table><caption><td>");
//     try expectConvert("", "<table><caption><div>");
//     try expectConvert("", "</caption><div>");
//     try expectConvert("", "<table><caption><div></caption>");
//     try expectConvert("", "<table><caption></table>");
//     try expectConvert("", "</table><div>");
//     try expectConvert(
//         "",
//         "<table><caption></body></col></colgroup></html></tbody></td></tfoot></th>" ++
//             "</thead></tr>",
//     );
//     try expectConvert("", "<table><caption><div></div>");
//     try expectConvert("", "<table><tr><td></body></caption></col></colgroup></html>");
//     try expectConvert("", "</table></tbody></tfoot></thead></tr><div>");
//     try expectConvert("foo", "<table><colgroup>foo");
//     try expectConvert("foo", "foo<col>");
//     try expectConvert("", "<table><colgroup></col>");
//     try expectConvert("", "<frameset><div>");
//     try expectConvert("", "</frameset><frame>");
//     try expectConvert("", "<frameset></div>");
//     try expectConvert("", "</body><div>");
//     try expectConvert("", "<table><tr><div>");
//     try expectConvert("", "</tr><td>");
//     try expectConvert("", "</tbody></tfoot></thead><td>");
//     try expectConvert("", "<table><tr><div><td>");
//     try expectConvert("", "<caption><col><colgroup><tbody><tfoot><thead><tr>");
//     try expectConvert("", "<table><tbody></thead>");
//     try expectConvert("", "</table><tr>");
//     try expectConvert(
//         "",
//         "<table><tbody></body></caption></col></colgroup></html></td></th></tr>",
//     );
//     try expectConvert("", "<table><tbody></div>");
//     try expectConvert("", "<table><table>");
//     try expectConvert(
//         "",
//         "<table></body></caption></col></colgroup></html></tbody></td></tfoot></th></thead></tr>",
//     );
//     try expectConvert("", "</table><tr>");
//     try expectConvert("", "<body></body></html>");
//     try expectConvert("", "<html><frameset></frameset></html>");
//     try expectConvert(
//         "",
//         "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01//EN\"><html></html>",
//     );
//     try expectConvert("", "<param><frameset></frameset>");
//     try expectConvert("", "<source><frameset></frameset>");
//     try expectConvert("", "<track><frameset></frameset>");
//     try expectConvert("", "</html><frameset></frameset>");
//     try expectConvert("", "</body><frameset></frameset>");
// }

// test "html5lib_tests7" {
//     try expectConvert("X", "<!doctype html><body><title>X</title>");
//     try expectConvert("X", "<!doctype html><table><title>X</title></table>");
//     try expectConvert("X", "<!doctype html><head></head><title>X</title>");
//     try expectConvert("X", "<!doctype html></head><title>X</title>");
//     try expectConvert("X", "<!doctype html></head><base>X");
//     try expectConvert("X", "<!doctype html></head><basefont>X");
//     try expectConvert("X", "<!doctype html></head><bgsound>X");
//     try expectConvert("", "<!doctype html><table><meta></table>");
//     try expectConvert("X", "<!doctype html><table>X<tr><td><table> <meta></table></table>");
//     try expectConvert("", "<!doctype html><html> <head>");
//     try expectConvert("", "<!doctype html> <head>");
//     try expectConvert("", "<!doctype html><table><style> <tr>x </style> </table>");
//     try expectConvert("", "<!doctype html><table><TBODY><script> <tr>x </script> </table>");
//     try expectConvert("X", "<!doctype html><p><applet><p>X</p></applet>");
//     try expectConvert(
//         "X",
//         "<!doctype html><p><object type=\"application/x-non-existant-plugin\"><p>X</p>" ++
//             "</object>",
//     );
//     try expectConvert("X", "<!doctype html><listing>\nX</listing>");
//     try expectConvert("X", "<!doctype html><select><input>X");
//     try expectConvert("X", "<!doctype html><select><select>X");
//     try expectConvert("", "<!doctype html><table><input type=hidDEN></table>");
//     try expectConvert("X", "<!doctype html><table>X<input type=hidDEN></table>");
//     try expectConvert("", "<!doctype html><table>  <input type=hidDEN></table>");
//     try expectConvert("", "<!doctype html><table>  <input type='hidDEN'></table>");
//     try expectConvert(
//         "",
//         "<!doctype html><table><input type=\" hidden\"><input type=hidDEN></table>",
//     );
//     try expectConvert("X", "<!doctype html><table><select>X<tr>");
//     try expectConvert("X", "<!doctype html><select>X</select>");
//     try expectConvert("", "<!DOCTYPE hTmL><html></html>");
//     try expectConvert("", "<!DOCTYPE HTML><html></html>");
//     try expectConvert("X", "<body>X</body></body>");
//     try expectConvert("a b", "<div><p>a</x> b");
//     try expectConvert("", "<table><tr><td><code></code> </table>");
//     try expectConvert("aaa\nbbb\n\nccc", "<table><b><tr><td>aaa</td></tr>bbb</table>ccc");
//     try expectConvert("A\n\nB\nB", "A<table><tr> B</tr> B</table>");
//     try expectConvert("A\n\nB\nC", "A<table><tr> B</tr> </em>C</table>");
//     try expectConvert("", "<select><keygen>");
// }

// test "html5lib_tests8" {
//     try expectConvert("x", "<div>\n<div></div>\n</span>x");
//     try expectConvert("x\nx", "<div>x<div></div>\n</span>x");
//     try expectConvert("x\nxx", "<div>x<div></div>x</span>x");
//     try expectConvert("x\nyz", "<div>x<div></div>y</span>z");
//     try expectConvert("x\nxx", "<table><div>x<div></div>x</span>x");
//     try expectConvert("", "<table><li><li></table>");
//     try expectConvert("x\n\nx", "x<table>x");
//     try expectConvert("x\n\nx", "x<table><table>x");
//     try expectConvert("a\ny", "<b>a<div></div><div></b>y");
//     try expectConvert("", "<a><div><p></a>");
// }

// test "html5lib_tests9" {
//     try expectConvert("", "<!DOCTYPE html><math></math>");
//     try expectConvert("", "<!DOCTYPE html><body><math></math>");
//     try expectConvert("", "<!DOCTYPE html><math><mi>");
//     try expectConvert("", "<!DOCTYPE html><math><annotation-xml><svg><u>");
//     try expectConvert("", "<!DOCTYPE html><body><select><math></math></select>");
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><body><select><option><math></math></option></select>",
//     );
//     try expectConvert("", "<!DOCTYPE html><body><table><math></math></table>");
//     try expectConvert(
//         "foo",
//         "<!DOCTYPE html><body><table><math><mi>foo</mi></math></table>",
//     );
//     try expectConvert(
//         "foobar",
//         "<!DOCTYPE html><body><table><math><mi>foo</mi><mi>bar</mi></math></table>",
//     );
//     try expectConvert(
//         "foobar",
//         "<!DOCTYPE html><body><table><tbody><math><mi>foo</mi><mi>bar</mi></math>" ++
//             "</tbody></table>",
//     );
//     try expectConvert(
//         "foobar",
//         "<!DOCTYPE html><body><table><tbody><tr><math><mi>foo</mi><mi>bar</mi></math>" ++
//             "</tr></tbody></table>",
//     );
//     try expectConvert(
//         "foobar",
//         "<!DOCTYPE html><body><table><tbody><tr><td><math><mi>foo</mi><mi>bar</mi>" ++
//             "</math></td></tr></tbody></table>",
//     );
//     try expectConvert(
//         "foobar\n\nbaz",
//         "<!DOCTYPE html><body><table><tbody><tr><td><math><mi>foo</mi><mi>bar</mi>" ++
//             "</math><p>baz</td></tr></tbody></table>",
//     );
//     try expectConvert(
//         "foobar\n\nbaz",
//         "<!DOCTYPE html><body><table><caption><math><mi>foo</mi><mi>bar</mi></math>" ++
//             "<p>baz</caption></table>",
//     );
//     try expectConvert(
//         "foobar\n\nbaz\n\nquux",
//         "<!DOCTYPE html><body><table><caption><math><mi>foo</mi><mi>bar</mi><p>baz" ++
//             "</table><p>quux",
//     );
//     try expectConvert(
//         "foobarbaz\n\nquux",
//         "<!DOCTYPE html><body><table><caption><math><mi>foo</mi><mi>bar</mi>baz" ++
//             "</table><p>quux",
//     );
//     try expectConvert(
//         "foobar\n\nbaz\n\nquux",
//         "<!DOCTYPE html><body><table><colgroup><math><mi>foo</mi><mi>bar</mi><p>" ++
//             "baz</table><p>quux",
//     );
//     try expectConvert(
//         "foobar\n\nbaz\n\nquux",
//         "<!DOCTYPE html><body><table><tr><td><select><math><mi>foo</mi><mi>bar</mi>" ++
//             "<p>baz</table><p>quux",
//     );
//     try expectConvert(
//         "foobar\n\nbaz\n\nquux",
//         "<!DOCTYPE html><body><table><select><math><mi>foo</mi><mi>bar</mi><p>baz" ++
//             "</table><p>quux",
//     );
//     try expectConvert(
//         "foobar\n\nbaz",
//         "<!DOCTYPE html><body></body></html><math><mi>foo</mi><mi>bar</mi><p>baz",
//     );
//     try expectConvert(
//         "foobar\n\nbaz",
//         "<!DOCTYPE html><body></body><math><mi>foo</mi><mi>bar</mi><p>baz",
//     );
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><frameset><math><mi></mi><mi></mi><p><span>",
//     );
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><frameset></frameset><math><mi></mi><mi></mi><p><span>",
//     );
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><body xlink:href=foo><math xlink:href=foo></math>",
//     );
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><body xlink:href=foo xml:lang=en><math>" ++
//             "<mi xml:lang=en xlink:href=foo></mi></math>",
//     );
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><body xlink:href=foo xml:lang=en><math>" ++
//             "<mi xml:lang=en xlink:href=foo /></math>",
//     );
//     try expectConvert(
//         "bar",
//         "<!DOCTYPE html><body xlink:href=foo xml:lang=en><math>" ++
//             "<mi xml:lang=en xlink:href=foo />bar</math>",
//     );
// }

// test "html5lib_tests10" {
//     try expectConvert("", "<!DOCTYPE html><svg></svg>");
//     try expectConvert("", "<!DOCTYPE html><svg></svg><![CDATA[a]]>");
//     try expectConvert("", "<!DOCTYPE html><body><svg></svg>");
//     try expectConvert("", "<!DOCTYPE html><body><select><svg></svg></select>");
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><body><select><option><svg></svg></option></select>",
//     );
//     try expectConvert("", "<!DOCTYPE html><body><table><svg></svg></table>");
//     try expectConvert("foo", "<!DOCTYPE html><body><table><svg><g>foo</g></svg></table>");
//     try expectConvert(
//         "foobar",
//         "<!DOCTYPE html><body><table><svg><g>foo</g><g>bar</g></svg></table>",
//     );
//     try expectConvert(
//         "foobar",
//         "<!DOCTYPE html><body><table><tbody><svg><g>foo</g><g>bar</g></svg></tbody></table>",
//     );
//     try expectConvert(
//         "foobar",
//         "<!DOCTYPE html><body><table><tbody><tr><svg><g>foo</g><g>bar</g></svg>" ++
//             "</tr></tbody></table>",
//     );
//     try expectConvert(
//         "foobar",
//         "<!DOCTYPE html><body><table><tbody><tr><td><svg><g>foo</g><g>bar</g></svg>" ++
//             "</td></tr></tbody></table>",
//     );
//     try expectConvert(
//         "foobar\n\nbaz",
//         "<!DOCTYPE html><body><table><tbody><tr><td><svg><g>foo</g><g>bar</g></svg>" ++
//             "<p>baz</td></tr></tbody></table>",
//     );
//     try expectConvert(
//         "foobar\n\nbaz",
//         "<!DOCTYPE html><body><table><caption><svg><g>foo</g><g>bar</g></svg><p>baz" ++
//             "</caption></table>",
//     );
//     try expectConvert(
//         "foobar\n\nbaz\n\nquux",
//         "<!DOCTYPE html><body><table><caption><svg><g>foo</g><g>bar</g><p>baz" ++
//             "</table><p>quux",
//     );
//     try expectConvert(
//         "foobarbaz\n\nquux",
//         "<!DOCTYPE html><body><table><caption><svg><g>foo</g><g>bar</g>baz</table><p>quux",
//     );
//     try expectConvert(
//         "foobar\n\nbaz\n\nquux",
//         "<!DOCTYPE html><body><table><colgroup><svg><g>foo</g><g>bar</g><p>baz</table" ++
//             "><p>quux",
//     );
//     try expectConvert(
//         "foobar\n\nbaz\n\nquux",
//         "<!DOCTYPE html><body><table><tr><td><select><svg><g>foo</g><g>bar</g>" ++
//             "<p>baz</table><p>quux",
//     );
//     try expectConvert(
//         "foobar\n\nbaz\n\nquux",
//         "<!DOCTYPE html><body><table><select><svg><g>foo</g><g>bar</g><p>baz</table><p>quux",
//     );
//     try expectConvert(
//         "foobar\n\nbaz",
//         "<!DOCTYPE html><body></body></html><svg><g>foo</g><g>bar</g><p>baz",
//     );
//     try expectConvert(
//         "foobar\n\nbaz",
//         "<!DOCTYPE html><body></body><svg><g>foo</g><g>bar</g><p>baz",
//     );
//     try expectConvert("", "<!DOCTYPE html><frameset><svg><g></g><g></g><p><span>");
//     try expectConvert("", "<!DOCTYPE html><frameset></frameset><svg><g></g><g>" ++
//         "</g><p><span>");
//     try expectConvert("", "<!DOCTYPE html><body xlink:href=foo><svg xlink:href=foo></svg>");
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><body xlink:href=foo xml:lang=en><svg>" ++
//             "<g xml:lang=en xlink:href=foo></g></svg>",
//     );
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><body xlink:href=foo xml:lang=en><svg>" ++
//             "<g xml:lang=en xlink:href=foo /></svg>",
//     );
//     try expectConvert(
//         "bar",
//         "<!DOCTYPE html><body xlink:href=foo xml:lang=en><svg>" ++
//             "<g xml:lang=en xlink:href=foo />bar</svg>",
//     );
//     try expectConvert("", "<svg></path>");
//     try expectConvert("a", "<div><svg></div>a");
//     try expectConvert("a", "<div><svg><path></div>a");
//     try expectConvert("", "<div><svg><path></svg><path>");
//     try expectConvert("a", "<div><svg><path><foreignObject><math></div>a");
//     try expectConvert("a", "<div><svg><path><foreignObject><p></div>a");
//     try expectConvert("a", "<!DOCTYPE html><svg><desc><div><svg><ul>a");
//     try expectConvert("a", "<!DOCTYPE html><svg><desc><svg><ul>a");
//     try expectConvert("", "<!DOCTYPE html><p><svg><desc><p>");
//     try expectConvert("<p>", "<!DOCTYPE html><p><svg><title><p>");
//     try expectConvert("", "<div><svg><path><foreignObject><p></foreignObject><p>");
//     try expectConvert(
//         "",
//         "<math><mi><div><object><div><span></span></div></object></div></mi><mi>",
//     );
//     try expectConvert(
//         "",
//         "<math><mi><svg><foreignObject><div><div></div></div></foreignObject>" ++
//             "</svg></mi><mi>",
//     );
//     try expectConvert("", "<svg><script></script><path>");
//     try expectConvert("", "<table><svg></svg><tr>");
//     try expectConvert("", "<math><mi><mglyph>");
//     try expectConvert("", "<math><mi><malignmark>");
//     try expectConvert("", "<math><mo><mglyph>");
//     try expectConvert("", "<math><mo><malignmark>");
//     try expectConvert("", "<math><mn><mglyph>");
//     try expectConvert("", "<math><mn><malignmark>");
//     try expectConvert("", "<math><ms><mglyph>");
//     try expectConvert("", "<math><ms><malignmark>");
//     try expectConvert("", "<math><mtext><mglyph>");
//     try expectConvert("", "<math><mtext><malignmark>");
//     try expectConvert("", "<math><annotation-xml><svg></svg></annotation-xml><mi>");
//     try expectConvert(
//         "",
//         "<math><annotation-xml><svg><foreignObject><div><math><mi></mi></math>" ++
//             "<span></span></div></foreignObject><path></path></svg></annotation-xml><mi>",
//     );
//     try expectConvert(
//         "",
//         "<math><annotation-xml><svg><foreignObject><math><mi><svg></svg></mi><mo>" ++
//             "</mo></math><span></span></foreignObject><path></path></svg>" ++
//             "</annotation-xml><mi>",
//     );
// }

// test "html5lib_tests11" {
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><body><svg attributeName='' attributeType='' baseFrequency=''" ++
//             " baseProfile='' calcMode='' clipPathUnits='' diffuseConstant='' " ++
//             "edgeMode='' filterUnits='' glyphRef='' gradientTransform='' " ++
//             "gradientUnits='' kernelMatrix='' kernelUnitLength='' keyPoints='' " ++
//             "keySplines='' keyTimes='' lengthAdjust='' limitingConeAngle='' " ++
//             "markerHeight='' markerUnits='' markerWidth='' maskContentUnits='' " ++
//             "maskUnits='' numOctaves='' pathLength='' patternContentUnits=''" ++
//             " patternTransform='' patternUnits='' pointsAtX='' pointsAtY=''" ++
//             " pointsAtZ='' preserveAlpha='' preserveAspectRatio='' " ++
//             "primitiveUnits='' refX='' refY='' repeatCount='' repeatDur=''" ++
//             " requiredExtensions='' requiredFeatures='' specularConstant='' " ++
//             "specularExponent='' spreadMethod='' startOffset='' stdDeviation='' " ++
//             "stitchTiles='' surfaceScale='' systemLanguage='' tableValues='' " ++
//             "targetX='' targetY='' textLength='' viewBox='' viewTarget=''" ++
//             " xChannelSelector='' yChannelSelector='' zoomAndPan=''></svg>",
//     );
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><BODY><SVG ATTRIBUTENAME='' ATTRIBUTETYPE='' BASEFREQUENCY=''" ++
//             " BASEPROFILE='' CALCMODE='' CLIPPATHUNITS='' DIFFUSECONSTANT='' " ++
//             "EDGEMODE='' FILTERUNITS='' GLYPHREF='' GRADIENTTRANSFORM='' " ++
//             "GRADIENTUNITS='' KERNELMATRIX='' KERNELUNITLENGTH='' KEYPOINTS='' " ++
//             "KEYSPLINES='' KEYTIMES='' LENGTHADJUST='' LIMITINGCONEANGLE='' " ++
//             "MARKERHEIGHT='' MARKERUNITS='' MARKERWIDTH='' MASKCONTENTUNITS='' " ++
//             "MASKUNITS='' NUMOCTAVES='' PATHLENGTH='' PATTERNCONTENTUNITS='' " ++
//             "PATTERNTRANSFORM='' PATTERNUNITS='' POINTSATX='' POINTSATY='' " ++
//             "POINTSATZ='' PRESERVEALPHA='' PRESERVEASPECTRATIO='' PRIMITIVEUNITS='' " ++
//             "REFX='' REFY='' REPEATCOUNT='' REPEATDUR='' REQUIREDEXTENSIONS='' " ++
//             "REQUIREDFEATURES='' SPECULARCONSTANT='' SPECULAREXPONENT='' " ++
//             "SPREADMETHOD='' STARTOFFSET='' STDDEVIATION='' STITCHTILES='' " ++
//             "SURFACESCALE='' SYSTEMLANGUAGE='' TABLEVALUES='' TARGETX='' TARGETY='' " ++
//             "TEXTLENGTH='' VIEWBOX='' VIEWTARGET='' XCHANNELSELECTOR='' " ++
//             "YCHANNELSELECTOR='' ZOOMANDPAN=''></SVG>",
//     );
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><body><svg attributename='' attributetype='' basefrequency='' " ++
//             "baseprofile='' calcmode='' clippathunits='' diffuseconstant='' edgemode=''" ++
//             " filterunits='' filterres='' glyphref='' gradienttransform='' " ++
//             "gradientunits='' kernelmatrix='' kernelunitlength='' keypoints='' " ++
//             "keysplines='' keytimes='' lengthadjust='' limitingconeangle='' " ++
//             "markerheight='' markerunits='' markerwidth='' maskcontentunits='' " ++
//             "maskunits='' numoctaves='' pathlength='' patterncontentunits='' " ++
//             "patterntransform='' patternunits='' pointsatx='' pointsaty='' " ++
//             "pointsatz='' preservealpha='' preserveaspectratio='' primitiveunits=''" ++
//             " refx='' refy='' repeatcount='' repeatdur='' requiredextensions='' " ++
//             "requiredfeatures='' specularconstant='' specularexponent='' spreadmethod=''" ++
//             " startoffset='' stddeviation='' stitchtiles='' surfacescale='' " ++
//             "systemlanguage='' tablevalues='' targetx='' targety='' textlength=''" ++
//             " viewbox='' viewtarget='' xchannelselector='' ychannelselector=''" ++
//             " zoomandpan=''></svg>",
//     );
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><body><math attributeName='' attributeType='' baseFrequency='' " ++
//             "baseProfile='' calcMode='' clipPathUnits='' diffuseConstant='' edgeMode=''" ++
//             " filterUnits='' glyphRef='' gradientTransform='' gradientUnits=''" ++
//             " kernelMatrix='' kernelUnitLength='' keyPoints='' keySplines='' " ++
//             "keyTimes='' lengthAdjust='' limitingConeAngle='' markerHeight='' " ++
//             "markerUnits='' markerWidth='' maskContentUnits='' maskUnits='' " ++
//             "numOctaves='' pathLength='' patternContentUnits='' patternTransform='' " ++
//             "patternUnits='' pointsAtX='' pointsAtY='' pointsAtZ='' preserveAlpha=''" ++
//             " preserveAspectRatio='' primitiveUnits='' refX='' refY='' repeatCount=''" ++
//             " repeatDur='' requiredExtensions='' requiredFeatures='' specularConstant=''" ++
//             " specularExponent='' spreadMethod='' startOffset='' stdDeviation=''" ++
//             " stitchTiles='' surfaceScale='' systemLanguage='' tableValues='' " ++
//             "targetX='' targetY='' textLength='' viewBox='' viewTarget='' " ++
//             "xChannelSelector='' yChannelSelector='' zoomAndPan=''></math>",
//     );
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><body><svg contentScriptType='' contentStyleType='' " ++
//             "externalResourcesRequired='' filterRes=''></svg>",
//     );
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><body><svg CONTENTSCRIPTTYPE='' CONTENTSTYLETYPE='' " ++
//             "EXTERNALRESOURCESREQUIRED='' FILTERRES=''></svg>",
//     );
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><body><svg contentscripttype='' contentstyletype='' " ++
//             "externalresourcesrequired='' filterres=''></svg>",
//     );
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><body><math contentScriptType='' contentStyleType='' " ++
//             "externalResourcesRequired='' filterRes=''></math>",
//     );
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><body><svg><altGlyph /><altGlyphDef /><altGlyphItem />" ++
//             "<animateColor /><animateMotion /><animateTransform /><clipPath />" ++
//             "<feBlend /><feColorMatrix /><feComponentTransfer /><feComposite />" ++
//             "<feConvolveMatrix /><feDiffuseLighting /><feDisplacementMap />" ++
//             "<feDistantLight /><feFlood /><feFuncA /><feFuncB /><feFuncG />" ++
//             "<feFuncR /><feGaussianBlur /><feImage /><feMerge /><feMergeNode />" ++
//             "<feMorphology /><feOffset /><fePointLight /><feSpecularLighting />" ++
//             "<feSpotLight /><feTile /><feTurbulence /><foreignObject /><glyphRef />" ++
//             "<linearGradient /><radialGradient /><textPath /></svg>",
//     );
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><body><svg><altglyph /><altglyphdef /><altglyphitem />" ++
//             "<animatecolor /><animatemotion /><animatetransform /><clippath />" ++
//             "<feblend /><fecolormatrix /><fecomponenttransfer /><fecomposite />" ++
//             "<feconvolvematrix /><fediffuselighting /><fedisplacementmap />" ++
//             "<fedistantlight /><feflood /><fefunca /><fefuncb /><fefuncg />" ++
//             "<fefuncr /><fegaussianblur /><feimage /><femerge /><femergenode />" ++
//             "<femorphology /><feoffset /><fepointlight /><fespecularlighting />" ++
//             "<fespotlight /><fetile /><feturbulence /><foreignobject /><glyphref />" ++
//             "<lineargradient /><radialgradient /><textpath /></svg>",
//     );
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><BODY><SVG><ALTGLYPH /><ALTGLYPHDEF /><ALTGLYPHITEM />" ++
//             "<ANIMATECOLOR /><ANIMATEMOTION /><ANIMATETRANSFORM /><CLIPPATH />" ++
//             "<FEBLEND /><FECOLORMATRIX /><FECOMPONENTTRANSFER /><FECOMPOSITE />" ++
//             "<FECONVOLVEMATRIX /><FEDIFFUSELIGHTING /><FEDISPLACEMENTMAP />" ++
//             "<FEDISTANTLIGHT /><FEFLOOD /><FEFUNCA /><FEFUNCB /><FEFUNCG />" ++
//             "<FEFUNCR /><FEGAUSSIANBLUR /><FEIMAGE /><FEMERGE /><FEMERGENODE />" ++
//             "<FEMORPHOLOGY /><FEOFFSET /><FEPOINTLIGHT /><FESPECULARLIGHTING />" ++
//             "<FESPOTLIGHT /><FETILE /><FETURBULENCE /><FOREIGNOBJECT /><GLYPHREF />" ++
//             "<LINEARGRADIENT /><RADIALGRADIENT /><TEXTPATH /></SVG>",
//     );
//     try expectConvert(
//         "",
//         "<!DOCTYPE html><body><math><altGlyph /><altGlyphDef /><altGlyphItem />" ++
//             "<animateColor /><animateMotion /><animateTransform /><clipPath />" ++
//             "<feBlend /><feColorMatrix /><feComponentTransfer /><feComposite />" ++
//             "<feConvolveMatrix /><feDiffuseLighting /><feDisplacementMap />" ++
//             "<feDistantLight /><feFlood /><feFuncA /><feFuncB /><feFuncG />" ++
//             "<feFuncR /><feGaussianBlur /><feImage /><feMerge /><feMergeNode />" ++
//             "<feMorphology /><feOffset /><fePointLight /><feSpecularLighting />" ++
//             "<feSpotLight /><feTile /><feTurbulence /><foreignObject /><glyphRef />" ++
//             "<linearGradient /><radialGradient /><textPath /></math>",
//     );
//     try expectConvert("", "<!DOCTYPE html><body><svg><solidColor /></svg>");
// }

// test "html5lib_tests12" {
//     try expectConvert(
//         "foobazeggs\n\nspam\n\nquuxbar",
//         "<!DOCTYPE html><body><p>foo<math><mtext><i>baz</i></mtext><annotation-xml>" ++
//             "<svg><desc><b>eggs</b></desc><g><foreignObject><P>spam<TABLE><tr><td>" ++
//             "<img></td></table></foreignObject></g><g>quux</g></svg></annotation-xml>" ++
//             "</math>bar",
//     );
//     try expectConvert(
//         "foobazeggs\n\nspam\n\nquuxbar",
//         "<!DOCTYPE html><body>foo<math><mtext><i>baz</i></mtext><annotation-xml><svg>" ++
//             "<desc><b>eggs</b></desc><g><foreignObject><P>spam<TABLE><tr><td><img></td>" ++
//             "</table></foreignObject></g><g>quux</g></svg></annotation-xml></math>bar",
//     );
// }

// test "html5lib_tests14" {
//     try expectConvert("", "<!DOCTYPE html><html><body><xyz:abc></xyz:abc>");
//     try expectConvert("", "<!DOCTYPE html><html><body><xyz:abc></xyz:abc><span></span>");
//     try expectConvert("", "<!DOCTYPE html><html><html abc:def=gh><xyz:abc></xyz:abc>");
//     try expectConvert("", "<!DOCTYPE html><html xml:lang=bar><html xml:lang=foo>");
//     try expectConvert("", "<!DOCTYPE html><html 123=456>");
//     try expectConvert("", "<!DOCTYPE html><html 123=456><html 789=012>");
//     try expectConvert("", "<!DOCTYPE html><html><body 789=012>");
// }

// test "html5lib_tests15" {
//     try expectConvert("X", "<!DOCTYPE html><p><b><i><u></p> <p>X");
//     try expectConvert("X", "<p><b><i><u></p>\n<p>X");
//     try expectConvert("", "<!doctype html></html> <head>");
//     try expectConvert("", "<!doctype html></body><meta>");
//     try expectConvert("", "<html></html><!-- foo -->");
//     try expectConvert("X", "<!doctype html></body><title>X</title>");
//     try expectConvert("X", "<!doctype html><table> X<meta></table>");
//     try expectConvert("x", "<!doctype html><table> x</table>");
//     try expectConvert("x", "<!doctype html><table> x </table>");
//     try expectConvert("x", "<!doctype html><table><tr> x</table>");
//     try expectConvert("X", "<!doctype html><table>X<style> <tr>x </style> </table>");
//     try expectConvert(
//         "foo\nbar",
//         "<!doctype html><div><table><a>foo</a> <tr><td>bar</td> </tr></table></div>",
//     );
//     try expectConvert(
//         "",
//         "<frame></frame></frame><frameset><frame><frameset><frame></frameset><noframes>" ++
//             "</frameset><noframes>",
//     );
//     try expectConvert("", "<!DOCTYPE html><object></html>");
// }

// test "html5lib_tests16" {
//     try expectConvert("", "<!doctype html><script>");
//     try expectConvert("", "<!doctype html><script>a");
//     try expectConvert("", "<!doctype html><script><");
//     try expectConvert("", "<!doctype html><script></");
//     try expectConvert("", "<!doctype html><script></S");
//     try expectConvert("", "<!doctype html><script></SC");
//     try expectConvert("", "<!doctype html><script></SCR");
//     try expectConvert("", "<!doctype html><script></SCRI");
//     try expectConvert("", "<!doctype html><script></SCRIP");
//     try expectConvert("", "<!doctype html><script></SCRIPT");
//     try expectConvert("", "<!doctype html><script></SCRIPT");
//     try expectConvert("", "<!doctype html><script></s");
//     try expectConvert("", "<!doctype html><script></sc");
//     try expectConvert("", "<!doctype html><script></scr");
//     try expectConvert("", "<!doctype html><script></scri");
//     try expectConvert("", "<!doctype html><script></scrip");
//     try expectConvert("", "<!doctype html><script></script");
//     try expectConvert("", "<!doctype html><script></script");
//     try expectConvert("", "<!doctype html><script><!");
//     try expectConvert("", "<!doctype html><script><!a");
//     try expectConvert("", "<!doctype html><script><!-");
//     try expectConvert("", "<!doctype html><script><!-a");
//     try expectConvert("", "<!doctype html><script><!--");
//     try expectConvert("", "<!doctype html><script><!--a");
//     try expectConvert("", "<!doctype html><script><!--<");
//     try expectConvert("", "<!doctype html><script><!--<a");
//     try expectConvert("", "<!doctype html><script><!--</");
//     try expectConvert("", "<!doctype html><script><!--</script");
//     try expectConvert("", "<!doctype html><script><!--</script");
//     try expectConvert("", "<!doctype html><script><!--<s");
//     try expectConvert("", "<!doctype html><script><!--<script");
//     try expectConvert("", "<!doctype html><script><!--<script");
//     try expectConvert("", "<!doctype html><script><!--<script <");
//     try expectConvert("", "<!doctype html><script><!--<script <a");
//     try expectConvert("", "<!doctype html><script><!--<script </");
//     try expectConvert("", "<!doctype html><script><!--<script </s");
//     try expectConvert("", "<!doctype html><script><!--<script </script");
//     try expectConvert("", "<!doctype html><script><!--<script </scripta");
//     try expectConvert("", "<!doctype html><script><!--<script </script");
//     try expectConvert("", "<!doctype html><script><!--<script </script>");
//     try expectConvert("", "<!doctype html><script><!--<script </script/");
//     try expectConvert("", "<!doctype html><script><!--<script </script <");
//     try expectConvert("", "<!doctype html><script><!--<script </script <a");
//     try expectConvert("", "<!doctype html><script><!--<script </script </");
//     try expectConvert("", "<!doctype html><script><!--<script </script </script");
//     try expectConvert("", "<!doctype html><script><!--<script </script </script");
//     try expectConvert("", "<!doctype html><script><!--<script </script </script/");
//     try expectConvert("", "<!doctype html><script><!--<script </script </script>");
//     try expectConvert("", "<!doctype html><script><!--<script -");
//     try expectConvert("", "<!doctype html><script><!--<script -a");
//     try expectConvert("", "<!doctype html><script><!--<script -<");
//     try expectConvert("", "<!doctype html><script><!--<script --");
//     try expectConvert("", "<!doctype html><script><!--<script --a");
//     try expectConvert("", "<!doctype html><script><!--<script --<");
//     try expectConvert("", "<!doctype html><script><!--<script -->");
//     try expectConvert("", "<!doctype html><script><!--<script --><");
//     try expectConvert("", "<!doctype html><script><!--<script --></");
//     try expectConvert("", "<!doctype html><script><!--<script --></script");
//     try expectConvert("", "<!doctype html><script><!--<script --></script");
//     try expectConvert("", "<!doctype html><script><!--<script --></script/");
//     try expectConvert("", "<!doctype html><script><!--<script --></script>");
//     try expectConvert("", "<!doctype html><script><!--<script><\\/script>--></script>");
//     try expectConvert("", "<!doctype html><script><!--<script></scr'+'ipt>--></script>");
//     try expectConvert(
//         "",
//         "<!doctype html><script><!--<script></script><script></script></script>",
//     );
//     try expectConvert(
//         "",
//         "<!doctype html><script><!--<script></script><script></script>--><!--</script>",
//     );
//     try expectConvert(
//         "",
//         "<!doctype html><script><!--<script></script><script></script>-- ></script>",
//     );
//     try expectConvert(
//         "",
//         "<!doctype html><script><!--<script></script><script></script>- -></script>",
//     );
//     try expectConvert(
//         "",
//         "<!doctype html><script><!--<script></script><script></script>- - ></script>",
//     );
//     try expectConvert(
//         "",
//         "<!doctype html><script><!--<script></script><script></script>-></script>",
//     );
//     try expectConvert("", "<!doctype html><script><!--<script>--!></script>X");
//     try expectConvert("-->", "<!doctype html><script><!--<scr'+'ipt></script>--></script>");
//     try expectConvert("", "<!doctype html><script><!--<script></scr'+'ipt></script>X");
//     try expectConvert("-->", "<!doctype html><style><!--<style></style>--></style>");
//     try expectConvert("X", "<!doctype html><style><!--</style>X");
//     try expectConvert("...-->", "<!doctype html><style><!--...</style>...--></style>");
//     try expectConvert(
//         "X",
//         "<!doctype html><style><!--<br><html xmlns:v=\"urn:schemas-microsoft-com:vml\">" ++
//             "<!--[if !mso]><style></style>X",
//     );
//     try expectConvert(
//         "-->",
//         "<!doctype html><style><!--...<style><!--...--!></style>--></style>",
//     );
//     try expectConvert(
//         "",
//         "<!doctype html><style><!--...</style><!-- --><style>@import ...</style>",
//     );
//     try expectConvert("", "<!doctype html><style>...<style><!--...</style><!-- --></style>");
//     try expectConvert("X", "<!doctype html><style>...<!--[if IE]><style>...</style>X");
//     try expectConvert("<!--<title>\n\n-->", "<!doctype html><title><!--<title></title>--></title>");
//     try expectConvert("</title>", "<!doctype html><title>&lt;/title></title>");
//     try expectConvert(
//         "foo/title><link></head><body>X",
//         "<!doctype html><title>foo/title><link></head><body>X",
//     );
//     try expectConvert(
//         "",
//         "<!doctype html><noscript><!--<noscript></noscript>--></noscript>",
//     );
//     try expectConvert(
//         "",
//         "<!doctype html><noscript><!--<noscript></noscript>--></noscript>",
//     );
//     try expectConvert(
//         "",
//         "<!doctype html><noscript><!--</noscript>X<noscript>--></noscript>",
//     );
//     try expectConvert(
//         "",
//         "<!doctype html><noscript><!--</noscript>X<noscript>--></noscript>",
//     );
//     try expectConvert("", "<!doctype html><noscript><iframe></noscript>X");
//     try expectConvert("", "<!doctype html><noscript><iframe></noscript>X");
//     try expectConvert(
//         "-->",
//         "<!doctype html><noframes><!--<noframes></noframes>--></noframes>",
//     );
//     try expectConvert(
//         "",
//         "<!doctype html><noframes><body><script><!--...</script></body></noframes></html>",
//     );
//     try expectConvert(
//         "<!--<textarea>-->",
//         "<!doctype html><textarea><!--<textarea></textarea>--></textarea>",
//     );
//     try expectConvert("</textarea>", "<!doctype html><textarea>&lt;/textarea></textarea>");
//     try expectConvert("<", "<!doctype html><textarea>&lt;</textarea>");
//     try expectConvert("a<b", "<!doctype html><textarea>a&lt;b</textarea>");
//     try expectConvert("-->", "<!doctype html><iframe><!--<iframe></iframe>--></iframe>");
//     try expectConvert("", "<!doctype html><iframe>...<!--X->...<!--/X->...</iframe>");
//     try expectConvert("<!--<xmp>\n\n-->", "<!doctype html><xmp><!--<xmp></xmp>--></xmp>");
//     try expectConvert("-->", "<!doctype html><noembed><!--<noembed></noembed>--></noembed>");
//     try expectConvert("", "<script>");
//     try expectConvert("", "<script>a");
//     try expectConvert("", "<script><");
//     try expectConvert("", "<script></");
//     try expectConvert("", "<script></S");
//     try expectConvert("", "<script></SC");
//     try expectConvert("", "<script></SCR");
//     try expectConvert("", "<script></SCRI");
//     try expectConvert("", "<script></SCRIP");
//     try expectConvert("", "<script></SCRIPT");
//     try expectConvert("", "<script></SCRIPT");
//     try expectConvert("", "<script></s");
//     try expectConvert("", "<script></sc");
//     try expectConvert("", "<script></scr");
//     try expectConvert("", "<script></scri");
//     try expectConvert("", "<script></scrip");
//     try expectConvert("", "<script></script");
//     try expectConvert("", "<script></script");
//     try expectConvert("", "<script><!");
//     try expectConvert("", "<script><!a");
//     try expectConvert("", "<script><!-");
//     try expectConvert("", "<script><!-a");
//     try expectConvert("", "<script><!--");
//     try expectConvert("", "<script><!--a");
//     try expectConvert("", "<script><!--<");
//     try expectConvert("", "<script><!--<a");
//     try expectConvert("", "<script><!--</");
//     try expectConvert("", "<script><!--</script");
//     try expectConvert("", "<script><!--</script");
//     try expectConvert("", "<script><!--<s");
//     try expectConvert("", "<script><!--<script");
//     try expectConvert("", "<script><!--<script");
//     try expectConvert("", "<script><!--<script <");
//     try expectConvert("", "<script><!--<script <a");
//     try expectConvert("", "<script><!--<script </");
//     try expectConvert("", "<script><!--<script </s");
//     try expectConvert("", "<script><!--<script </script");
//     try expectConvert("", "<script><!--<script </scripta");
//     try expectConvert("", "<script><!--<script </script");
//     try expectConvert("", "<script><!--<script </script>");
//     try expectConvert("", "<script><!--<script </script/");
//     try expectConvert("", "<script><!--<script </script <");
//     try expectConvert("", "<script><!--<script </script <a");
//     try expectConvert("", "<script><!--<script </script </");
//     try expectConvert("", "<script><!--<script </script </script");
//     try expectConvert("", "<script><!--<script </script </script");
//     try expectConvert("", "<script><!--<script </script </script/");
//     try expectConvert("", "<script><!--<script </script </script>");
//     try expectConvert("", "<script><!--<script -");
//     try expectConvert("", "<script><!--<script -a");
//     try expectConvert("", "<script><!--<script --");
//     try expectConvert("", "<script><!--<script --a");
//     try expectConvert("", "<script><!--<script -->");
//     try expectConvert("", "<script><!--<script --><");
//     try expectConvert("", "<script><!--<script --></");
//     try expectConvert("", "<script><!--<script --></script");
//     try expectConvert("", "<script><!--<script --></script");
//     try expectConvert("", "<script><!--<script --></script/");
//     try expectConvert("", "<script><!--<script --></script>");
//     try expectConvert("", "<script><!--<script><\\/script>--></script>");
//     try expectConvert("", "<script><!--<script></scr'+'ipt>--></script>");
//     try expectConvert("", "<script><!--<script></script><script></script></script>");
//     try expectConvert(
//         "",
//         "<script><!--<script></script><script></script>--><!--</script>",
//     );
//     try expectConvert("", "<script><!--<script></script><script></script>-- ></script>");
//     try expectConvert("", "<script><!--<script></script><script></script>- -></script>");
//     try expectConvert(
//         "",
//         "<script><!--<script></script><script></script>- - ></script>",
//     );
//     try expectConvert("", "<script><!--<script></script><script></script>-></script>");
//     try expectConvert("", "<script><!--<script>--!></script>X");
//     try expectConvert("-->", "<script><!--<scr'+'ipt></script>--></script>");
//     try expectConvert("", "<script><!--<script></scr'+'ipt></script>X");
//     try expectConvert("-->", "<style><!--<style></style>--></style>");
//     try expectConvert("X", "<style><!--</style>X");
//     try expectConvert("...-->", "<style><!--...</style>...--></style>");
//     try expectConvert(
//         "X",
//         "<style><!--<br><html xmlns:v=\"urn:schemas-microsoft-com:vml\"><!--[if !mso]>" ++
//             "<style></style>X",
//     );
//     try expectConvert("-->", "<style><!--...<style><!--...--!></style>--></style>");
//     try expectConvert("", "<style><!--...</style><!-- --><style>@import ...</style>");
//     try expectConvert("", "<style>...<style><!--...</style><!-- --></style>");
//     try expectConvert("X", "<style>...<!--[if IE]><style>...</style>X");
//     try expectConvert("<!--<title>\n\n-->", "<title><!--<title></title>--></title>");
//     try expectConvert("</title>", "<title>&lt;/title></title>");
//     try expectConvert("foo/title><link></head><body>X", "<title>foo/title><link></head><body>X");
//     try expectConvert("", "<noscript><!--<noscript></noscript>--></noscript>");
//     try expectConvert("", "<noscript><!--<noscript></noscript>--></noscript>");
//     try expectConvert("", "<noscript><!--</noscript>X<noscript>--></noscript>");
//     try expectConvert("", "<noscript><!--</noscript>X<noscript>--></noscript>");
//     try expectConvert("", "<noscript><iframe></noscript>X");
//     try expectConvert("-->", "<noframes><!--<noframes></noframes>--></noframes>");
//     try expectConvert(
//         "",
//         "<noframes><body><script><!--...</script></body></noframes></html>",
//     );
//     try expectConvert("<!--<textarea>-->", "<textarea><!--<textarea></textarea>--></textarea>");
//     try expectConvert("</textarea>", "<textarea>&lt;/textarea></textarea>");
//     try expectConvert("-->", "<iframe><!--<iframe></iframe>--></iframe>");
//     try expectConvert("", "<iframe>...<!--X->...<!--/X->...</iframe>");
//     try expectConvert("<!--<xmp>\n\n-->", "<xmp><!--<xmp></xmp>--></xmp>");
//     try expectConvert("-->", "<noembed><!--<noembed></noembed>--></noembed>");
//     try expectConvert("", "<!doctype html><table>\n");
//     try expectConvert("", "<!doctype html><table><td><span><font></span><span>");
//     try expectConvert("", "<!doctype html><form><table></form><form></table></form>");
// }

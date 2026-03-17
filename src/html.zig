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

fn expectHTML5(
    comptime ekdytest_filename: []const u8,
    overwrite_exps: []const struct { u64, []const u8 },
) !void {
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

                _ = text_da.pop();
                _ = html_da.pop();

                var exp: []const u8 = text_da.items;
                // Override expectation for the test ID.
                if (skip_i < overwrite_exps.len and test_id == overwrite_exps[skip_i].@"0") {
                    exp = overwrite_exps[skip_i].@"1";
                    skip_i += 1;
                }

                expectConvert(exp, html_da.items) catch |terr| {
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
    // 34: Special case for <select>, <option> and <optgroup>
    // 77-79: Special case for <table> that require foster parenting.
    try expectHTML5(
        "tests1.ekdytest",
        &.{
            .{ 34, "A\nB\nCD\nE" },   .{ 77, "ababr\nx\naoe" }, .{ 78, "aba\nbrx\naoe" },
            .{ 79, "aba\nbrx\naoe" },
        },
    );
}

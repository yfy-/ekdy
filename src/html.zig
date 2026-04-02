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
    @"annotation-xml",
    mi,
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

pub const TagProperty = packed struct {
    is_void: bool = false,
    is_ignore: bool = false,
    is_rcdata: bool = false,
    is_rawtext: bool = false,
    is_preformatted: bool = false,
};

pub const default_tag_properties = std.EnumArray(Tag, TagProperty).initDefault(.{}, .{
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
    .datalist = .{ .is_ignore = true },
    .fencedframe = .{ .is_ignore = true },
    .frameset = .{ .is_ignore = true },
    .iframe = .{ .is_ignore = true, .is_rawtext = true },
    .map = .{ .is_ignore = true },
    .annotation = .{ .is_ignore = true },
    .@"annotation-xml" = .{ .is_ignore = true },
    .noembed = .{ .is_ignore = true, .is_rawtext = true },
    .noframes = .{ .is_ignore = true, .is_rawtext = true },

    // ekdy should act as if JS is disabled, therefore we treat
    // noscript and object as inline tags.
    // .noscript = .{ .is_ignore = true, .is_rawtext = true },
    // .object = .{ .is_ignore = true },
    .picture = .{ .is_ignore = true },
    .script = .{ .is_ignore = true, .is_rawtext = true },
    .style = .{ .is_ignore = true, .is_rawtext = true },
    .svg = .{ .is_ignore = true },
    .template = .{ .is_ignore = true },
    .video = .{ .is_ignore = true },
    .plaintext = .{ .is_rawtext = true, .is_void = true },
    .textarea = .{ .is_rcdata = true, .is_preformatted = true },
    .title = .{ .is_rcdata = true, .is_ignore = true },
    .xmp = .{ .is_rawtext = true, .is_preformatted = true },
    .pre = .{ .is_preformatted = true },
    .rp = .{ .is_ignore = true },
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
        const tag_properties = initTagProps();

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

        /// Flag to identify first character of preformatted text.
        /// Preformatted text omits the first character if its '\n'.
        preformatted_first: bool = false,

        /// State to return back after an attribute state.
        attr_return_state: State = .tag_start_found,

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
        decoder: decoding.EntityDecoder = decoding.EntityDecoder{},

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
            frameset,
        };

        // Initialize tag properties by respecting the overrides
        // provided by the policy type.
        fn initTagProps() std.EnumArray(Tag, TagProperty) {
            var props = default_tag_properties;
            if (!@hasDecl(T, "tag_property_overrides"))
                return props;

            for (&T.tag_property_overrides) |tp| {
                props.set(tp.@"0", tp.@"1");
            }

            return props;
        }

        pub fn init(allocator: Allocator, out_writer: *Writer, policy: *T) !Self {
            return Self{
                .tag_buffer = try ArrayList(u8).initCapacity(allocator, 32),
                .out_writer = out_writer,
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
                // std.debug.print("state: {} char: {c}\n", .{ self.state, curr_html[0] });
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
                    .frameset => self.handleFrameSet(curr_html),
                };
            }
            self.cursor -= html.len;
        }

        /// Writes any text remaining. Should be called after all html
        /// chunks are processed with convert.
        pub fn eos(self: *Self) !void {
            switch (self.state) {
                .tag => {
                    try self.out_writer.writeByte('<');
                },
                .tag_end => {
                    // Only output </ when tag buffer is empty.
                    // If any tag has started than output nothing.
                    if (self.tag_buffer.items.len == 0)
                        _ = try self.out_writer.write("</");
                },
                else => {},
            }
        }

        //<p>ekdy...</p>
        //   ^~~~~~~
        fn handleText(
            self: *Self,
            allocator: Allocator,
            html: []const u8,
        ) Error!usize {
            const tag = self.stack.getLastOrNull();
            const tag_prop = if (tag) |t| tag_properties.get(t) else null;

            const c = html[0];
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

            // Text in <math> is ignored unless other math related tags are used.
            if (self.ignore_depth > 0 or (tag != null and tag.? == .math)) return 1;

            if (self.preformatted_depth == 0 and ascii.isWhitespace(c)) {
                // When last processed tag was br and it inserted a new line,
                // we do not queue a new space.
                if (self.pending_whitespace == null and !self.last_br) {
                    self.pending_whitespace = .space;
                }
                return 1;
            }

            if (self.pending_whitespace) |pw| {
                if (self.any_text) {
                    const ws = switch (pw) {
                        .space => " ",
                        .single_break => "\n",
                        .double_break => "\n\n",
                    };
                    try self.out_writer.writeAll(ws);
                }
            }
            self.pending_whitespace = null;
            const consumed = try self.emitText(html, tag, tag_prop);
            self.last_br = false;
            return consumed;
        }

        fn emitText(self: *Self, html: []const u8, tag: ?Tag, tag_prop: ?TagProperty) Error!usize {
            var consumed: usize = 1;

            // Write decoding.
            const c = html[0];
            if (c == '&' and (tag == null or !tag_prop.?.is_rawtext)) {
                const decoded = self.decoder.decode(html[1..]);
                if (decoded.@"1") |cps| {
                    consumed += decoded.@"0";

                    // Decoded could be ascii whitespace.
                    if (cps[1] == 0 and cps[0] <= std.math.maxInt(u8) and
                        ascii.isWhitespace(@intCast(cps[0])))
                    {
                        if (self.preformatted_depth > 0) {
                            try self.emitPreformattedWhitespace(@intCast(cps[0]));
                        } else {
                            try self.queueWhitespace(.space);
                        }
                    } else {
                        try self.out_writer.print("{u}", .{cps[0]});
                        if (cps[1] != 0) try self.out_writer.print("{u}", .{cps[1]});
                    }
                } else {
                    try self.out_writer.writeByte(c);
                }
            } else if (c != 0) {
                if (self.preformatted_depth > 0) {
                    try self.emitPreformattedWhitespace(c);
                } else {
                    try self.out_writer.writeByte(c);
                }
            }

            self.any_text = true;
            self.preformatted_first = false;
            return consumed;
        }

        fn emitPreformattedWhitespace(self: *Self, c: u8) Error!void {
            var c_out = c;
            // preformatted mode turns \r to \n.
            if (c_out == '\r')
                c_out = '\n';

            if (c_out != '\n' or !self.preformatted_first)
                try self.out_writer.writeByte(c_out);
        }

        //<p>ekdy...</p>
        // ^
        //
        //<p>ekdy...</p>
        //           ^
        fn handleTag(self: *Self, html: []const u8) Error!usize {
            const c = html[0];
            if (!is_valid_fs_tag_char(c)) {
                try self.out_writer.writeByte('<');
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
                var tag = tag_from_str(self.tag_buffer.items);

                // frameset is special. Its only a valid tag if no
                // text has been written before which in that case no
                // text can be emitted afterwards. Otherwise, we map
                // it to unknown to process it inline.
                if (tag == .frameset) {
                    if (!self.any_text) {
                        self.state = .frameset;
                        return html.len;
                    }
                    tag = .unknown;
                }

                // br is forced line break..
                if (tag == .br) {
                    try self.out_writer.writeByte('\n');
                    self.last_br = true;
                }

                try self.stack.append(allocator, tag);
                if (tag_properties.get(tag).is_ignore)
                    self.ignore_depth += 1;

                if (tag_properties.get(tag).is_preformatted) {
                    self.preformatted_depth += 1;
                    if (self.preformatted_depth == 1) self.preformatted_first = true;
                }

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

            if (@hasDecl(T, "onTagStart")) {
                if (try self.policy.onTagStart(tag, self.out_writer)) |ws| {
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

		self.state = if (tag == .script) State.script else State.text;
                return 1;
            }

            self.attr_return_state = State.tag_start_found;
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

        fn popUntilMatching(self: *Self, end_tag: Tag) bool {
            var found_idx = self.stack.items.len;
            while (found_idx > 0) : (found_idx -= 1) {
                if (end_tag == self.stack.items[found_idx - 1]) {
                    for (self.stack.items[found_idx - 1 ..]) |pop_tag| {
                        const tp = tag_properties.get(pop_tag);
                        if (tp.is_ignore)
                            self.ignore_depth -|= 1;

                        if (tp.is_preformatted) {
                            self.preformatted_depth -|= 1;
                            if (self.preformatted_depth == 0) self.preformatted_first = false;
                        }
                    }

                    self.stack.items.len = found_idx - 1;
                    return true;
                }
            }

            return false;
        }

        //<strong >ekdy...</strong >
        //                        ^~
        fn handleTagEndFound(self: *Self, html: []const u8) Error!usize {
            const c = html[0];

            if (ascii.isWhitespace(c)) return 1;

            if (c != '>') {
                self.attr_return_state = .tag_end_found;
                self.state = .attr_key;
                return 0;
            }

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
                    const match = self.popUntilMatching(end_tag);
                    if (@hasDecl(T, "onTagEnd")) {
                        const ws = try self.policy.onTagEnd(
                            end_tag,
                            self.out_writer,
                        );
                        if (ws != null and match) {
                            try self.queueWhitespace(ws.?);
                        }
                    }
                } else {
                    // Tag buffer is empty if it's void tag, just pop it.
                    _ = self.stack.pop();
                }
            }

            self.state = State.text;
            return 1;
        }

        fn switchAttrEndState(self: *Self) void {
            self.state = self.attr_return_state;
            self.attr_return_state = .tag_start_found;
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
                self.switchAttrEndState();
                return 0;
            }

            return 1;
        }

        //<a href="http://...">ekdy</a>
        //        ^~~~~~~~~~~~
        fn handleAttrVal(self: *Self, html: []const u8) Error!usize {
            const c = html[0];
            if (self.attr_val_quote) |qc| {
                if (c == qc) {
                    self.switchAttrEndState();
                    self.attr_val_quote = null;
                    self.attr_val_start = false;
                }
            } else {
                if (ascii.isWhitespace(c)) {
                    if (self.attr_val_start) {
                        self.switchAttrEndState();
                        self.attr_val_start = false;
                    }
                } else if (c == '"' or c == '\'') {
                    self.attr_val_quote = c;
                    self.attr_val_start = true;
                } else if (c == '>') {
                    self.attr_val_start = false;
                    self.switchAttrEndState();
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

            if (html.len > 3 and std.mem.eql(u8, html[0..4], "--!>")) {
                self.state = State.text;
                return 4;
            }

            return 1;
        }

        //<plaintext>ekdy...
        //           ^~~~~~~
        fn handlePlaintext(self: *Self, html: []const u8) Error!usize {
            // In plaintext null bytes are printed as invalid as
            // opposed to normal text mode where they are ignored.
            for (html) |c| {
                if (c == 0) {
                    try self.out_writer.print("{u}", .{decoding.html_unicode_invalid});
                } else {
                    try self.out_writer.writeByte(c);
                }
            }

            return html.len;
        }

        // Check if given tag prefix is proper tag. For example if
        // '</script' is given will try to match a proper </script> tag by
        // relying to the rules of script tag matching (whitespace etc.). If
        // there is no match will return 0, otherwise will return number
        // of bytes that points after the tag match. This function is
        // useful to avoid complex script sub-state machine, rather than
        // having a full sub-state machine this helper handles boilerplate
        // tag matching logic.
        fn tagMatchScriptMode(
            self: *Self,
            html: []const u8,
            comptime tag_prefix: []const u8,
        ) Error!usize {
            if (html.len < tag_prefix.len + 1)
                return html.len;

            var lowercase_buf: [tag_prefix.len]u8 = undefined;
            const lowercase = ascii.lowerString(&lowercase_buf, html[0..tag_prefix.len]);
            if (!std.mem.eql(u8, lowercase, tag_prefix))
                return 0;

            var script_match = false;
            var sub_cursor = tag_prefix.len;
            while (sub_cursor < html.len) {
                const c = html[sub_cursor];
                if (c == '>')
                    return sub_cursor + 1;

                if (!ascii.isWhitespace(c) and c != '/') {
                    if (!script_match) return 0;

                    // Some attribute is starting here. Save the
                    // current state to attr_return_state so we don't
                    // accidentally return to some weird state.
                    self.attr_return_state = self.state;
                    const orig_state = self.state;
                    self.state = .attr_key;
                    while (sub_cursor < html.len and self.state != orig_state) {
                        sub_cursor += try switch (self.state) {
                            .attr_key => self.handleAttrKey(html[sub_cursor..]),
                            .attr_val => self.handleAttrVal(html[sub_cursor..]),
                            else => {
                                unreachable;
                            },
                        };
                    }
                } else {
                    sub_cursor += 1;
                    // In below states the final > is not required for tag start or end.
                    // Simply either ascii whitespace or / can end the tag.
                    if (self.state == .script_escaped or self.state == .script_double_escaped)
                        return sub_cursor;

                    script_match = true;
                }
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
            const check_adv = try self.tagMatchScriptMode(html, "</script");
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

            const start_adv = try self.tagMatchScriptMode(html, "<script");
            if (start_adv > 0) {
                self.state = .script_double_escaped;
                return start_adv;
            }

            const end_adv = try self.tagMatchScriptMode(html, "</script");
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

            const end_adv = try self.tagMatchScriptMode(html, "</script");
            if (end_adv > 0) {
                self.state = .script_escaped;
                return end_adv;
            }

            return 1;
        }

        fn handleFrameSet(self: *Self, html: []const u8) Error!usize {
            _ = self;
            return html.len;
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
    const exp = "Welcome\n\nThis paragraph contains an " ++
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
    const exp = "Hi! ¨";
    try expectConvert(exp, html);
}

test "unmatching" {
    try expectConvert(
        "12345",
        "<p>1<b>2<i>3</b>4</i>5</p>",
    );
}

test "tag_end_bogus_attribute" {
    try expectConvert("abc", "<i>abc</i a=\">\">");
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

fn expectHTML5CheckHelper(
    html_da: *ArrayList(u8),
    text_da: *ArrayList(u8),
    deviation_index: *u64,
    deviations: []const struct { u64, []const u8 },
    test_id: u64,
) !void {
    _ = text_da.pop();
    _ = html_da.pop();

    var exp: []const u8 = text_da.items;
    // Override expectation for the test ID.
    if (deviation_index.* < deviations.len and
        test_id == deviations[deviation_index.*].@"0")
    {
        exp = deviations[deviation_index.*].@"1";
        deviation_index.* += 1;
    }

    expectConvert(exp, html_da.items) catch |terr| {
        std.debug.print("failed test_id={} on '{s}'\n", .{
            test_id,
            html_da.items,
        });
        return terr;
    };
}

/// Expect all tests in the html5lib ekdytest files pass with the
/// optional provided overwritten expectations. Overwritten
/// expectations is used when 'ekdy' decided to not comply with the
/// HTML5 or the inner policy provided to TextExtractor.
fn expectHTML5(
    comptime ekdytest_filename: []const u8,
    deviations: []const struct { u64, []const u8 },
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
    var deviation_i: u64 = 0;
    while (reader.takeDelimiterInclusive('\n')) |line| {
        if (std.mem.eql(u8, line, "#data\n")) {
            in_data = true;
            if (html_da.items.len == 0)
                continue;

            defer text_da.clearRetainingCapacity();
            defer html_da.clearRetainingCapacity();
            defer test_id += 1;

            try expectHTML5CheckHelper(
                &html_da,
                &text_da,
                &deviation_i,
                deviations,
                test_id,
            );
        } else if (std.mem.eql(u8, line, "#text\n")) {
            in_data = false;
        } else if (in_data) {
            try html_da.appendSlice(talloc, line);
        } else {
            try text_da.appendSlice(talloc, line);
        }
    } else |err| {
        if (err != error.EndOfStream) return err;
        try expectHTML5CheckHelper(&html_da, &text_da, &deviation_i, deviations, test_id);
    }
}

test "html5lib_tests1" {
    // 34: <select> without <option> or <optgroup>
    // 75: Most likely adoption rules are fixing the tree.
    // 77-79: <table> foster parenting.
    // 86: Table <tr> and <td> handling.
    try expectHTML5(
        "tests1.ekdytest",
        &.{
            .{ 34, "A\nB\nCD\nE" },   .{ 75, "abc def ghi\n\njkl mno pqr stu" },
            .{ 77, "ababr\nx\naoe" }, .{ 78, "aba\nbrx\naoe" },
            .{ 79, "aba\nbrx\naoe" }, .{ 86, "X" },
        },
    );
}

test "html5lib_tests2" {
    try expectHTML5("tests2.ekdytest", &.{});
}

test "html5lib_tests3" {
    try expectHTML5("tests3.ekdytest", &.{});
}

test "html5lib_tests4" {
    try expectHTML5("tests4.ekdytest", &.{});
}

test "html5lib_tests5" {
    try expectHTML5("tests5.ekdytest", &.{});
}

test "html5lib_tests6" {
    try expectHTML5("tests6.ekdytest", &.{});
}

test "html5lib_tests7" {
    // 23-24: <select> without <option> or <optgroup>
    // 30-31: <table> foster parenting.
    // 32: <table>
    try expectHTML5("tests7.ekdytest", &.{
        .{ 23, "X" }, .{ 24, "X" }, .{ 30, "aaabbb\nccc" }, .{ 31, "A\nB B" }, .{ 32, "A\nB C" },
    });
}

test "html5lib_tests8" {
    // 7: <table> tag ending without </table> causes a newline in
    // chromium but not in ekdy as </table> does not exist.
    try expectHTML5("tests8.ekdytest", &.{.{ 7, "xx" }});
}

test "html5lib_tests9" {
    // All: <math> <select> and <table>
    try expectHTML5("tests9.ekdytest", &.{
        .{ 8, "foobar" },                 .{ 9, "foobar" },
        .{ 10, "foobar" },                .{ 11, "foobar" },
        .{ 12, "foobar\n\nbaz" },         .{ 13, "foobar\n\nbaz" },
        .{ 14, "foobar\n\nbaz\n\nquux" }, .{ 15, "foobar\n\nquux" },
        .{ 16, "foobar\n\nbaz\n\nquux" }, .{ 17, "foobar\n\nbaz\n\nquux" },
        .{ 18, "foobar\n\nbaz\n\nquux" }, .{ 19, "foobar\n\nbaz" },
        .{ 20, "foobar\n\nbaz" },
    });
}

test "html5lib_tests10" {
    // 13, 15, 18-19, 30-31: SVG parsing.
    try expectHTML5("tests10.ekdytest", &.{
        .{ 13, "quux" }, .{ 15, "quux" }, .{ 18, "" }, .{ 19, "" }, .{ 30, "a" }, .{ 31, "a" },
    });
}

test "html5lib_tests11" {
    try expectHTML5("tests11.ekdytest", &.{});
}

test "html5lib_tests12" {
    // 0-1: Math parsing.
    try expectHTML5("tests12.ekdytest", &.{ .{ 0, "foobaz\n\nbar" }, .{ 1, "foobaz\n\nbar" } });
}

test "html5lib_tests14" {
    try expectHTML5("tests14.ekdytest", &.{});
}

test "html5lib_tests15" {
    try expectHTML5("tests15.ekdytest", &.{});
}

test "html5lib_tests16" {
    try expectHTML5("tests16.ekdytest", &.{});
}

test "html5lib_tests17" {
    // 2-3: <table> parsing.
    try expectHTML5("tests17.ekdytest", &.{ .{ 2, "" }, .{ 3, "" } });
}

test "html5lib_tests18" {
    // 13-15: <template> parsing.
    // 21: <svg> parsing.
    // 27-29: <select> parsing.
    // 35: <table> indentation.
    try expectHTML5("tests18.ekdytest", &.{
        .{ 13, "</plaintext>X" },  .{ 14, "a<caption>b" }, .{ 15, "a</template>b" },
        .{ 21, "a</plaintext>b" }, .{ 27, "abc" },         .{ 28, "abc" },
        .{ 29, "abc" },            .{ 35, "abc" },
    });
}

test "html5lib_tests19" {
    // 61: <br> with no text does not emit \n.
    try expectHTML5("tests19.ekdytest", &.{ .{ 23, "abcfoo" }, .{ 61, "\n" } });
}

test "html5lib_tests20" {
    try expectHTML5("tests20.ekdytest", &.{});
}

test "html5lib_tests21" {
    try expectHTML5("tests21.ekdytest", &.{});
}

test "html5lib_tests22" {
    try expectHTML5("tests22.ekdytest", &.{});
}

test "html5lib_tests23" {
    try expectHTML5("tests23.ekdytest", &.{});
}

test "html5lib_tests24" {
    try expectHTML5("tests24.ekdytest", &.{});
}

test "html5lib_tests25" {
    try expectHTML5("tests25.ekdytest", &.{});
}

test "html5lib_tests26" {
    // 10: <svg> parsing.
    try expectHTML5("tests26.ekdytest", &.{ .{ 10, "" }, .{ 11, "" } });
}

// Adoption is not possible with ekdy, so its best effort.
test "html5lib_adoption01" {
    // 4: Adoption
    // 10-11: <table> foster parenting.
    // 23: <h*> type of tags can be closed by any of them.
    try expectHTML5("adoption01.ekdytest", &.{
        .{ 4, "1\n2\n345" }, .{ 10, "1\n23" }, .{ 11, "A\nBC" }, .{ 23, "abcfoo" },
    });
}

test "html5lib_adoption02" {
    try expectHTML5("adoption01.ekdytest", &.{
        .{ 4, "1\n2\n345" }, .{ 10, "1\n23" }, .{ 11, "A\nBC" },
    });
}

test "html5lib_blocks" {
    // 10-13: <details>, <dialog> handling requires attribute
    // buffering for open attribute.
    // 16-17, 20-23, 26-29, 32-35, 40-41, 44-47: Auto inserted </p>.
    try expectHTML5("blocks.ekdytest", &.{
        .{ 10, "foo\n\nbar\n\nbaz" }, .{ 11, "foo\n\nbar" },      .{ 12, "foo\n\nbar\n\nbaz" },
        .{ 13, "foo\n\nbar" },        .{ 16, "foo\nbar\n\nbaz" }, .{ 17, "foo\nbar" },
        .{ 20, "foo\nbar\n\nbaz" },   .{ 21, "foo\nbar" },        .{ 22, "foo\nbar\n\nbaz" },
        .{ 23, "foo\nbar" },          .{ 26, "foo\nbar\n\nbaz" }, .{ 27, "foo\nbar" },
        .{ 28, "foo\nbar\n\nbaz" },   .{ 29, "foo\nbar" },        .{ 32, "foobar\n\nbaz" },
        .{ 33, "foobar" },            .{ 34, "foo\nbar\n\nbaz" }, .{ 35, "foo\nbar" },
        .{ 40, "foo\nbar\n\nbaz" },   .{ 41, "foo\nbar" },        .{ 44, "foo\nbar\n\nbaz" },
        .{ 45, "foo\nbar" },          .{ 46, "foo\nbar\n\nbaz" }, .{ 47, "foo\nbar" },
    });
}

test "html5lib_comments01" {
    try expectHTML5("comments01.ekdytest", &.{});
}

test "html5lib_doctype01" {
    try expectHTML5("doctype01.ekdytest", &.{});
}

test "html5lib_domjs-unsafe" {
    try expectHTML5("domjs-unsafe.ekdytest", &.{});
}

test "html5lib_entities01" {
    try expectHTML5("entities01.ekdytest", &.{});
}

test "html5lib_entities02" {
    try expectHTML5("entities02.ekdytest", &.{});
}

test "html5lib_foreign-fragment" {
    try expectHTML5("foreign-fragment.ekdytest", &.{});
}

test "html5lib_html5test-com" {
    try expectHTML5("html5test-com.ekdytest", &.{});
}

test "html5lib_inbody01" {
    try expectHTML5("inbody01.ekdytest", &.{});
}

test "html5lib_isindex" {
    try expectHTML5("isindex.ekdytest", &.{});
}

test "html5lib_main-element" {
    try expectHTML5("main-element.ekdytest", &.{});
}

test "html5lib_math" {
    try expectHTML5("math.ekdytest", &.{});
}

test "html5lib_menuitem-element" {
    try expectHTML5("menuitem-element.ekdytest", &.{});
}

test "html5lib_namespace-sensitivity" {
    // 0: <svg>
    try expectHTML5("namespace-sensitivity.ekdytest", &.{.{ 0, "" }});
}

test "html5lib_noscript01" {
    try expectHTML5("noscript01.ekdytest", &.{});
}

test "html5lib_pending-spec-changes-plain-text-unsafe" {
    try expectHTML5("pending-spec-changes-plain-text-unsafe.ekdytest", &.{});
}

test "html5lib_pending-spec-changes" {
    // 2: <table>
    try expectHTML5("pending-spec-changes.ekdytest", &.{.{ 2, "" }});
}

test "html5lib_plain-text-unsafe" {
    // 13-27: <svg>
    try expectHTML5("plain-text-unsafe.ekdytest", &.{ .{ 13, "" }, .{ 27, "" } });
}

test "html5lib_quirks01" {
    try expectHTML5("quirks01.ekdytest", &.{});
}

test "html5lib_ruby" {
    try expectHTML5("ruby.ekdytest", &.{});
}

test "html5lib_scriptdata01" {
    try expectHTML5("scriptdata01.ekdytest", &.{});
}

test "html5lib_search-element" {
    try expectHTML5("search-element.ekdytest", &.{});
}

test "html5lib_svg" {
    try expectHTML5("svg.ekdytest", &.{});
}

test "html5lib_tables01" {
    // 15: <table> tab handling.
    try expectHTML5("tables01.ekdytest", &.{ .{ 15, "" }, .{ 16, "" } });
}

test "html5lib_template" {
    // 6, 78: <template> parsing.
    try expectHTML5("template.ekdytest", &.{ .{ 6, "Hello" }, .{ 78, "Foo" } });
}

test "html5lib_tests_innerHTML_1" {
    // 73: <table> tab handling.
    try expectHTML5("tests_innerHTML_1.ekdytest", &.{.{ 73, "" }});
}

test "html5lib_tricky01" {
    const deviation =
        \\Italic and Red
        \\
        \\Italic and Red Just italic. Italic only. Plain
        \\
        \\I should not be red. Red. Italic and red.
        \\
        \\Italic and red. Red. I should not be red.
        \\
        \\Bold Bold and italic Only Italic Plain
    ;

    // 0-1: Automatic <p> insertion.
    // 7: <table> parsing somehow allows initial whitespace without any text.
    try expectHTML5("tricky01.ekdytest", &.{
        .{ 0, "Bold Not bold Also not bold." },                              .{ 1, deviation },
        .{ 7, "This page contains an insanely badly-nested tag sequence." },
    });
}

test "html5lib_webkit01" {
    // 18, 20: <br> prints nothing if there is no text at all. But if
    // there is at least 1 text char all <br> is written. This
    // requires bufferin so we omit this.
    // 31: Weird <option> and <select> spacing.
    // 47: <table> tab spacing.
    // 49: MathML parsing, uses unicode symbols.
    try expectHTML5("webkit01.ekdytest", &.{
        .{ 18, "\n" }, .{ 20, "\n" }, .{ 31, "A\nB\nC\nD\nE\nF\nG" }, .{ 47, "" }, .{ 49, "1a" },
    });
}

test "html5lib_webkit02" {
    // 19: <svg> parsing.
    // 20: <svg> parsing does not recognize <title> tag inside.
    // 37-38: <select> and <option> parsing.
    try expectHTML5("webkit02.ekdytest", &.{
        .{ 19, "</foreignObject></svg><div>bar</div>" }, .{ 20, "" },
        .{ 37, "div 1\nbutton\ndiv 2\ndiv 3" },          .{ 38, "button" },
    });
}

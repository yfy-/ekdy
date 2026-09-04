const std = @import("std");
const decoding = @import("decoding.zig");
const ascii = std.ascii;
const fs = std.fs;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

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
    listing,
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
    table,
    caption,
    col,
    colgroup,
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

    // MathML
    mi,
    mo,
    mn,
    ms,
    mtext,
    annotation,
    @"annotation-xml",

    // SVG
    foreignObject,
    desc,
    svg_title,

    // Uncategorized
    applet,
    basefont,
    bgsound,
    keygen,
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

pub const ContentType = enum(u2) {
    normal,
    rcdata,
    rawtext,
};

pub const Namespace = enum(u2) {
    html,
    math,
    svg,
};

pub const EndType = enum(u2) {
    none,
    implied,
    thorough,
};

pub const TagProperty = packed struct {
    void: bool = false,
    ignore: bool = false,
    content_type: ContentType = .normal,
    preformatted: bool = false,
    end_type: EndType = .none,
    closes_p: bool = false,
    namespace: Namespace = .html,
    scope_boundary: bool = false,
    heading: bool = false,
    special: bool = false,
};

pub const default_tag_properties = std.EnumArray(Tag, TagProperty).initDefault(.{}, .{
    .address = .{ .closes_p = true, .special = true },
    .article = .{ .closes_p = true, .special = true },
    .aside = .{ .closes_p = true, .special = true },
    .blockquote = .{ .closes_p = true, .special = true },
    .center = .{ .closes_p = true, .special = true },
    .details = .{ .closes_p = true, .special = true },
    .dialog = .{ .closes_p = true },
    .dir = .{ .closes_p = true, .special = true },
    .div = .{ .closes_p = true, .special = true },
    .dl = .{ .closes_p = true, .special = true },
    .fieldset = .{ .closes_p = true, .special = true },
    .figcaption = .{ .closes_p = true, .special = true },
    .figure = .{ .closes_p = true, .special = true },
    .footer = .{ .closes_p = true, .special = true },
    .header = .{ .closes_p = true, .special = true },
    .hgroup = .{ .closes_p = true, .special = true },
    .main = .{ .closes_p = true, .special = true },
    .menu = .{ .closes_p = true, .special = true },
    .nav = .{ .closes_p = true, .special = true },
    .ol = .{ .closes_p = true, .special = true },
    .search = .{ .closes_p = true, .special = true },
    .section = .{ .closes_p = true, .special = true },
    .summary = .{ .closes_p = true, .special = true },
    .ul = .{ .closes_p = true, .special = true },
    .form = .{ .closes_p = true, .special = true },

    .area = .{ .void = true, .special = true },
    .base = .{ .void = true, .special = true },
    .br = .{ .void = true, .special = true },
    .col = .{ .void = true, .special = true },
    .embed = .{ .void = true, .special = true },
    .frame = .{ .void = true, .special = true },
    .hr = .{ .void = true, .special = true },
    .image = .{ .void = true },
    .img = .{ .void = true, .special = true },
    .input = .{ .void = true, .special = true },
    .link = .{ .void = true, .special = true },
    .meta = .{ .void = true, .special = true },
    .param = .{ .void = true, .special = true },
    .source = .{ .void = true, .special = true },
    .track = .{ .void = true, .special = true },
    .wbr = .{ .void = true, .special = true },
    .iframe = .{ .content_type = .rawtext, .special = true },
    .noembed = .{ .content_type = .rawtext, .special = true },
    .noframes = .{ .content_type = .rawtext, .special = true },

    .script = .{ .ignore = true, .content_type = .rawtext, .special = true },
    .style = .{ .ignore = true, .content_type = .rawtext, .special = true },
    .template = .{ .ignore = true, .scope_boundary = true, .special = true },
    .plaintext = .{ .content_type = .rawtext, .void = true, .special = true },
    .textarea = .{ .content_type = .rcdata, .preformatted = true, .special = true },
    .title = .{ .content_type = .rcdata, .special = true },
    .xmp = .{ .content_type = .rawtext, .preformatted = true, .special = true },
    .pre = .{ .preformatted = true, .closes_p = true, .special = true },
    .listing = .{ .preformatted = true, .closes_p = true, .special = true },

    .dd = .{ .end_type = .implied, .special = true },
    .dt = .{ .end_type = .implied, .special = true },
    .li = .{ .end_type = .implied, .special = true },
    .optgroup = .{ .end_type = .implied },
    .option = .{ .end_type = .implied },
    .p = .{ .end_type = .implied, .closes_p = true, .special = true },
    .rb = .{ .end_type = .implied },
    .rp = .{ .end_type = .implied },
    .rt = .{ .end_type = .implied },
    .rtc = .{ .end_type = .implied },

    .caption = .{ .end_type = .thorough, .scope_boundary = true, .special = true },
    .colgroup = .{ .end_type = .thorough, .special = true },
    .tbody = .{ .end_type = .thorough, .special = true },
    .td = .{ .end_type = .thorough, .scope_boundary = true, .special = true },
    .tfoot = .{ .end_type = .thorough, .special = true },
    .th = .{ .end_type = .thorough, .scope_boundary = true, .special = true },
    .thead = .{ .end_type = .thorough, .special = true },
    .tr = .{ .end_type = .thorough, .special = true },

    .mi = .{ .namespace = .math, .scope_boundary = true, .special = true },
    .mo = .{ .namespace = .math, .scope_boundary = true, .special = true },
    .mn = .{ .namespace = .math, .scope_boundary = true, .special = true },
    .ms = .{ .namespace = .math, .scope_boundary = true, .special = true },
    .mtext = .{ .namespace = .math, .scope_boundary = true, .special = true },
    .annotation = .{ .namespace = .math },
    .@"annotation-xml" = .{ .namespace = .math, .scope_boundary = true, .special = true },

    .foreignObject = .{ .namespace = .svg, .scope_boundary = true, .special = true },
    .desc = .{ .namespace = .svg, .scope_boundary = true, .special = true },
    .svg_title = .{ .namespace = .svg, .scope_boundary = true, .special = true },

    .applet = .{ .scope_boundary = true, .special = true },
    .html = .{ .scope_boundary = true, .special = true },
    .table = .{ .scope_boundary = true, .special = true },
    .marquee = .{ .scope_boundary = true, .special = true },
    .object = .{ .scope_boundary = true, .special = true },
    .select = .{ .scope_boundary = true, .special = true },

    .h1 = .{ .heading = true, .closes_p = true, .special = true },
    .h2 = .{ .heading = true, .closes_p = true, .special = true },
    .h3 = .{ .heading = true, .closes_p = true, .special = true },
    .h4 = .{ .heading = true, .closes_p = true, .special = true },
    .h5 = .{ .heading = true, .closes_p = true, .special = true },
    .h6 = .{ .heading = true, .closes_p = true, .special = true },

    .basefont = .{ .special = true },
    .bgsound = .{ .special = true },
    .body = .{ .special = true },
    .button = .{ .special = true },
    .frameset = .{ .special = true },
    .head = .{ .special = true },
    .keygen = .{ .special = true },
    // ekdy should act as if JS is disabled, therefore we treat
    // noscript and object as inline tags.
    .noscript = .{ .special = true },
});

pub const tag_to_enum = std.StaticStringMap(Tag).initComptime(blk: {
    const fields = std.meta.fields(Tag);
    var init_vals: [fields.len]struct { []const u8, Tag } = undefined;
    for (fields, 0..) |f, i| {
        // svg_title is not actually a tag name.
        const tag = if (std.mem.eql(u8, f.name, "svg_title")) Tag.unknown else @field(Tag, f.name);
        init_vals[i] = .{ f.name, tag };
    }

    break :blk init_vals;
});

pub const max_tag_len = blk: {
    var max_len = 0;
    for (std.meta.fields(Tag)) |field| {
        max_len = @max(max_len, field.name.len);
    }

    break :blk max_len;
};

pub fn is_valid_fs_tag_char(c: u8) bool {
    return ascii.isAlphabetic(c) or c == '!' or c == '?' or c == '/';
}

pub const StructuralDepths = struct {
    ignore: usize = 0,
    preformatted: usize = 0,
    table: usize = 0,
    svg: usize = 0,
    math: usize = 0,
};

pub fn TextExtractor(T: type) type {
    if (!@hasDecl(T, "onText")) {
        @compileError("policy must have onText implemented.");
    }

    return struct {
        const Self = @This();
        const tag_properties = initTagProps();
        const Error = Allocator.Error || T.Error;

        // Maximum size to copy from current html chunk to residual.
        const max_refill_size = 32;

        /// Whitespace type to emit.
        pending_whitespace: ?Whitespace = null,

        /// Flag to check if we last emitted <br>.
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

        /// Frameset-ok flag. Allows transition to <frameset>.
        frameset_ok: bool = true,

        /// Flag for checking if from element pointer is set.
        form_elem_ptr_set: bool = false,

        /// State to return back after an attribute state.
        attr_return_state: State = .tag_start_found,

        /// Parser state.
        state: State = .text,

        cursor: usize = 0,

        depths: StructuralDepths = .{},

        stack: ArrayList(Tag) = ArrayList(Tag).empty,

        /// Buffer for current tag.
        tag_buffer: [max_tag_len]u8 = undefined,

        /// Current tag length.
        tag_buffer_len: usize = 0,

        /// Flag to indicate tag has overflown and should be just unknown.
        tag_buffer_overflow: bool = false,

        /// Buffer for residual html that stores copies of previous chunks.
        residual_html: ArrayList(u8) = ArrayList(u8).empty,

        /// Residual html cursor.
        residual_cursor: usize = 0,

        /// Entity decoder.
        decoder: decoding.EntityDecoder = decoding.EntityDecoder{},

        /// Text policy.
        policy: *T,

        const State = enum {
            text,
            decoding,
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

        // Initialize tag properties by respecting the additional
        // ignored tags.
        fn initTagProps() std.EnumArray(Tag, TagProperty) {
            var props = default_tag_properties;
            if (!@hasDecl(T, "ignored_tags"))
                return props;

            for (&T.ignored_tags) |it| {
                props.getPtr(it).ignore = true;
            }

            return props;
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.stack.deinit(allocator);
            self.residual_html.deinit(allocator);
        }

        const ParseStep = struct {
            consumed: usize,
            buffer_rest: bool = false,
        };

        pub fn feedAll(self: *Self, allocator: Allocator, html: []const u8) Error!void {
            try self.feed(allocator, html);
            try self.finish();
        }

        inline fn step(self: *Self, allocator: Allocator, html: []const u8) Error!ParseStep {
            return switch (self.state) {
                .text => try self.handleText(html),
                .decoding => try self.handleDecoding(html),
                .tag => try self.handleTag(html),
                .tag_start => self.handleTagStart(html),
                .tag_start_found => try self.handleTagStartFound(allocator, html),
                .tag_end => self.handleTagEnd(html),
                .tag_end_found => try self.handleTagEndFound(html),
                .attr_key => self.handleAttrKey(html),
                .attr_val => self.handleAttrVal(html),
                .comment => self.handleComment(html),
                .plaintext => try self.handlePlaintext(html),
                .script => self.handleScript(html),
                .script_escaped => self.handleScriptEscaped(html),
                .script_double_escaped => self.handleScriptDoubleEscaped(html),
                .frameset => self.handleFrameSet(html),
            };
        }

        /// Feed a chunk of html.
        /// Can be repeteadly called for consecutive html chunks.
        /// When all the chunks are fed, finish must be called.
        pub fn feed(
            self: *Self,
            allocator: Allocator,
            html: []const u8,
        ) Error!void {
            // Cursor should always reset after this because we always fully use html.
            defer self.cursor = 0;

            if (html.len == 0)
                return;

            // Feed the residual if we have anything buffered there.
            if (self.residual_html.items.len > 0) {
                const init_copy_sz = @min(html.len - self.cursor, max_refill_size);
                try self.residual_html.appendSlice(allocator, html[0..init_copy_sz]);
                self.cursor += init_copy_sz;
                while (self.residual_cursor < self.residual_html.items.len) {
                    const step_res = try self.step(
                        allocator,
                        self.residual_html.items[self.residual_cursor..],
                    );
                    self.residual_cursor += step_res.consumed;
                    if (step_res.buffer_rest) {
                        const copy_sz = @min(html.len - self.cursor, max_refill_size);
                        if (copy_sz == 0)
                            return;

                        try self.residual_html.appendSlice(allocator, html[0..copy_sz]);
                        self.cursor += copy_sz;
                    }
                }

                self.residual_cursor = 0;
                self.residual_html.clearRetainingCapacity();
            }

            // Feed the rest of the html buffer.
            while (self.cursor < html.len) {
                const step_res = try self.step(allocator, html[self.cursor..]);
                self.cursor += step_res.consumed;
                if (step_res.buffer_rest) {
                    try self.residual_html.appendSlice(allocator, html[self.cursor..]);
                    break;
                }
            }
        }

        /// Writes any text remaining. Should be called after all html
        /// chunks are fed.
        pub fn finish(self: *Self) T.Error!void {
            switch (self.state) {
                .tag => {
                    try self.emitText("<", self.stack.getLastOrNull());
                },
                .tag_end => {
                    // Only output </ when tag buffer is empty.
                    // If any tag has started than output nothing.
                    if (self.tag_buffer_len == 0)
                        _ = try self.emitText("</", self.stack.getLastOrNull());
                },
                .decoding => {
                    try self.emitDecoded(self.decoder.finish());
                },
                else => {},
            }
        }

        /// Peek tag ending matches for RCDATA and RAWTEXT tags.
        fn peekRawEndTag(self: *Self, tag: Tag, html: []const u8) ForwardMatchResult {
            const tag_end_fw = forwardMatch("</", html);
            if (tag_end_fw != .full) return tag_end_fw;

            if (html.len <= 2) return .partial;
            const tag_str = @tagName(tag);
            self.tag_buffer_len = @min(html.len - 2, tag_str.len);
            const lower_tag = std.ascii.lowerString(
                &self.tag_buffer,
                html[2 .. self.tag_buffer_len + 2],
            );
            return forwardMatch(tag_str, lower_tag);
        }

        //<p>ekdy...</p>
        //   ^~~~~~~
        fn handleText(
            self: *Self,
            html: []const u8,
        ) T.Error!ParseStep {
            const tag = self.stack.getLastOrNull();
            const tag_prop = if (tag) |t| tag_properties.get(t) else null;

            var start: usize = 0;
            var consumed: usize = 0;
            while (consumed < html.len) : ({
                consumed += 1;
            }) {
                const c = html[consumed];
                if (c == '<') {
                    if (tag == null or tag_prop.?.content_type == .normal) {
                        try self.emitText(html[start..consumed], tag);
                        self.state = State.tag;
                        // Also consume the <.
                        return .{ .consumed = consumed + 1 };
                    }

                    // RAWTEXT and RCDATA
                    const raw_end_match = self.peekRawEndTag(tag.?, html[consumed..]);
                    if (raw_end_match == .partial) return .{
                        .consumed = consumed,
                        .buffer_rest = true,
                    };

                    if (raw_end_match == .full) {
                        try self.emitText(html[start..consumed], tag);
                        self.state = State.tag_end_found;
                        // Tag buffer currently contains the correct tag
                        // we also consume the "</".
                        return .{ .consumed = consumed + self.tag_buffer_len + 2 };
                    }
                } else if (ascii.isWhitespace(c)) {
                    try self.emitText(html[start..consumed], tag);
                    try self.handleWhitespace(c);
                    start = consumed + 1;
                } else if (c == 0) {
                    try self.emitText(html[start..consumed], tag);
                    start = consumed + 1;
                } else if (c == '&' and (tag == null or tag_prop.?.content_type != .rawtext)) {
                    try self.emitText(html[start..consumed], tag);
                    self.state = State.decoding;
                    return .{ .consumed = consumed + 1 };
                } else {
                    self.preformatted_first = false;
                    if (self.pending_whitespace == null) continue;
                    try self.emitText(html[start..consumed], tag);
                    start = consumed;
                }
            }

            try self.emitText(html[start..consumed], tag);
            return .{ .consumed = html.len };
        }

        fn handleWhitespace(self: *Self, whitespace: u8) T.Error!void {
            if (self.depths.preformatted == 0) {
                if (!self.last_br and self.depths.ignore == 0)
                    self.queueWhitespace(.space);
                return;
            }

            if (self.preformatted_first) {
                self.preformatted_first = false;
                if (whitespace != '\n' and whitespace != '\r' and self.depths.ignore == 0)
                    try self.policy.onText((&whitespace)[0..1]);
            } else {
                const c_out = if (whitespace == '\r') '\n' else whitespace;
                if (self.depths.ignore == 0)
                    try self.policy.onText((&c_out)[0..1]);
            }
        }

        inline fn emitText(
            self: *Self,
            text: []const u8,
            tag: ?Tag,
        ) T.Error!void {
            if (text.len == 0 or
                self.depths.ignore > 0 or
                (tag != null and tag.? == .math))
            {
                return;
            }

            if (self.pending_whitespace) |pw| {
                if (self.any_text) {
                    const ws = switch (pw) {
                        .space => " ",
                        .single_break => "\n",
                        .double_break => "\n\n",
                    };
                    try self.policy.onText(ws);
                }
                self.pending_whitespace = null;
            }

            try self.policy.onText(text);
            self.any_text = true;
            self.last_br = false;
        }

        fn handleDecoding(self: *Self, html: []const u8) T.Error!ParseStep {
            const feed_res = self.decoder.feed(html);
            if (feed_res.emit == null) {
                return .{ .consumed = feed_res.consumed };
            }

            try self.emitDecoded(feed_res.emit.?);
            self.state = State.text;
            return .{ .consumed = feed_res.consumed };
        }

        fn emitDecoded(self: *Self, emit: decoding.EntityDecoder.Emit) T.Error!void {
            const tag = self.stack.getLastOrNull();
            if (emit.codepoints) |cps| {
                if (cps[1] == 0 and cps[0] <= std.math.maxInt(u8) and
                    ascii.isWhitespace(@intCast(cps[0])))
                {
                    try self.handleWhitespace(@intCast(cps[0]));
                } else {
                    var utf8enc: [8]u8 = undefined;
                    // Our codepoints are valid from the decoder.
                    var len = std.unicode.utf8Encode(cps[0], &utf8enc) catch unreachable;
                    if (cps[1] != 0) {
                        len += std.unicode.utf8Encode(cps[1], utf8enc[len..]) catch unreachable;
                    }
                    try self.emitText(utf8enc[0..len], tag);
                }
            } else {
                // No codepoint therefore not a valid entity at all,
                // we need to emit the & as literal.
                try self.emitText("&", tag);
            }

            try self.emitText(emit.literal, tag);
        }

        //<p>ekdy...</p>
        // ^
        //
        //<p>ekdy...</p>
        //           ^
        fn handleTag(self: *Self, html: []const u8) T.Error!ParseStep {
            const c = html[0];
            if (!is_valid_fs_tag_char(c)) {
                try self.policy.onText("<");
                self.state = State.text;
                return .{ .consumed = 0 };
            }

            if (c == '/') {
                self.state = State.tag_end;
                return .{ .consumed = 1 };
            }

            self.state = State.tag_start;
            return .{ .consumed = 0 };
        }

        /// Result value to use when we try to do forward lookup on
        /// the HTML buffer. Because we only have a chunk of HTML the
        /// result might be inconclusive thereby we use partial.
        const ForwardMatchResult = enum { full, partial, none };

        inline fn forwardMatch(target: []const u8, html: []const u8) ForwardMatchResult {
            const min_len = @min(target.len, html.len);
            if (std.mem.eql(u8, target[0..min_len], html[0..min_len])) {
                return if (target.len == min_len) .full else .partial;
            }

            return .none;
        }

        fn accumTagChar(self: *Self, c: u8) void {
            if (self.tag_buffer_len < self.tag_buffer.len) {
                self.tag_buffer[self.tag_buffer_len] = ascii.toLower(c);
                self.tag_buffer_len += 1;
            } else {
                self.tag_buffer_overflow = true;
            }
        }

        fn resolveTag(self: *Self) Tag {
            if (self.tag_buffer_overflow) return Tag.unknown;

            const maybe_tag = tag_to_enum.get(self.tag_buffer[0..self.tag_buffer_len]);
            if (maybe_tag == null) return Tag.unknown;

            const tag = maybe_tag.?;
            const tp = tag_properties.get(tag);

            if (tp.namespace == .math and self.depths.math == 0) return Tag.unknown;
            if (tp.namespace == .svg and self.depths.svg == 0) return Tag.unknown;
            if (tag == .title and self.depths.svg > 0) return Tag.svg_title;

            return tag;
        }

        const Scope = enum(u3) {
            stack,
            scope,
            list_item,
            button,
            table,
        };

        fn inScope(self: *Self, tag: Tag, scope: Scope) bool {
            var it = std.mem.reverseIterator(self.stack.items);
            while (it.next()) |st_tag| {
                const st_tp = tag_properties.get(st_tag);
                switch (scope) {
                    .stack => {},
                    .scope => {
                        if (st_tp.scope_boundary)
                            return false;
                    },
                    .list_item => {
                        if (st_tp.scope_boundary or st_tag == .ol or st_tag == .ul)
                            return false;
                    },
                    .button => {
                        if (st_tp.scope_boundary or st_tag == .button)
                            return false;
                    },
                    .table => {
                        if (st_tag == .html or st_tag == .table or st_tag == .template)
                            return false;
                    },
                }

                if (st_tag != .unknown and st_tag == tag)
                    return true;
            }

            return false;
        }

        fn insertElement(self: *Self, tag: Tag, allocator: Allocator) Allocator.Error!void {
            try self.stack.append(allocator, tag);
            if (tag_properties.get(tag).ignore)
                self.depths.ignore += 1;

            if (tag_properties.get(tag).preformatted) {
                self.depths.preformatted += 1;
                // Only xmp does not cause first new line to be skipped.
                if (self.depths.preformatted == 1 and tag != .xmp)
                    self.preformatted_first = true;
            }

            if (tag == .table) {
                self.depths.table += 1;
            } else if (tag == .svg) {
                self.depths.svg += 1;
            } else if (tag == .math) {
                self.depths.math += 1;
            }
        }

        /// Pop the stack until pos (including it) starting from top.
        fn popUntil(self: *Self, pos: usize) T.Error!void {
            var i = self.stack.items.len;
            while (i > pos) : (i -= 1) {
                try self.closeTag(self.stack.items[i - 1]);
            }

            try self.closeTag(self.stack.items[pos]);
            self.stack.items.len = pos;
        }

        /// Close a <p> and everything in between if there is one in
        /// the button scope.
        fn pCloseButtonScope(self: *Self) T.Error!void {
            var i: usize = self.stack.items.len;
            while (i > 0) : (i -= 1) {
                const tag = self.stack.items[i - 1];
                const tp = tag_properties.get(tag);
                if (tp.scope_boundary or tag == .button)
                    return;

                if (tag == .p) {
                    try self.popUntil(i - 1);
                    return;
                }
            }
        }

        /// Closes a previously open peer element by walking the stack
        /// from top to bottom. If a matching peer tag is found, pops
        /// all elements from the top of the stack down to and
        /// including the peer, emitting close events for each. The
        /// walk stops without closing if a Special-category element
        /// is encountered, except for `address`, `div`, and `p` which
        /// are transparent to the walk. Used for `li` (peers: `li`),
        /// `dd` and `dt` (peers: `dd`, `dt`). Ref: WHATWG §13.2.6.4.7
        /// "in body" — start tags "li", "dd", "dt".
        fn closePrevPeer(self: *Self, peer_tags: []const Tag) T.Error!void {
            var i = self.stack.items.len;
            while (i > 0) : (i -= 1) {
                const st_tag = self.stack.items[i - 1];
                if (std.mem.findScalar(Tag, peer_tags, st_tag) != null) {
                    try self.popUntil(i - 1);
                    break;
                }

                const tp = tag_properties.get(st_tag);
                if (tp.special and st_tag != .address and st_tag != .div and st_tag != .p)
                    break;
            }
        }

        /// Process a tag start in body. Implements
        /// https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-inbody.
        /// Returns true if 'tag' is processed i.e. pushed to stack.
        fn processModeBodyStartTag(self: *Self, tag: Tag, allocator: Allocator) Error!bool {
            const tp = tag_properties.get(tag);
            if (tag == .body) {
                self.frameset_ok = false;
                if (!self.inScope(tag, .scope))
                    try self.insertElement(tag, allocator);
            } else if (tag == .frameset) {
                if (self.frameset_ok) {
                    try self.insertElement(tag, allocator);
                } else {
                    return false;
                }
            } else if (tag == .form) {
                const temp_in_stack = self.inScope(.template, .stack);
                if (self.form_elem_ptr_set and temp_in_stack)
                    return false;

                try self.pCloseButtonScope();
                try self.insertElement(tag, allocator);

                // NOTE: We don't need to check if <template> is in
                // the stack again after pCloseButtonScope might have
                // changed the stack, because <template> is scope
                // boundary therefore it could not have been popped.
                if (!temp_in_stack)
                    self.form_elem_ptr_set = true;
            } else if (tp.closes_p) {
                try self.pCloseButtonScope();
                if (tp.heading) {
                    if (self.stack.getLastOrNull()) |curr_tag| {
                        if (tag_properties.get(curr_tag).heading) {
                            _ = self.stack.pop();
                            try self.closeTag(curr_tag);
                        }
                    }
                }

                try self.insertElement(tag, allocator);
                if (tag == .pre or tag == .listing)
                    self.frameset_ok = false;
            } else if (tag == .li or tag == .dd or tag == .dt) {
                self.frameset_ok = false;
                try self.closePrevPeer(if (tag == .li) &.{.li} else &.{ .dd, .dt });
                try self.pCloseButtonScope();
                try self.insertElement(tag, allocator);
            } else if (tag == .plaintext) {
                try self.pCloseButtonScope();
                try self.insertElement(tag, allocator);
            } else {
                try self.insertElement(tag, allocator);
            }

            // br is forced line break..
            if (tag == .br) {
                try self.policy.onText("\n");
                self.last_br = true;
            }

            return true;
        }

        //<strong>ekdy...</strong>
        // ^~~~~
        fn handleTagStart(self: *Self, html: []const u8) ParseStep {
            // Handle comments below if tag has not started
            if (self.tag_buffer_len == 0) {
                const comment_match = forwardMatch("!--", html);
                if (comment_match == .full) {
                    self.state = State.comment;

                    // Do not consume all 3, because it can abruptly finish
                    // with: <!-->
                    return .{ .consumed = 1, .buffer_rest = false };
                }

                if (comment_match == .partial) {
                    return .{ .consumed = 0, .buffer_rest = true };
                }
            }

            const c = html[0];

            // Tag name ends in this block
            if (ascii.isWhitespace(c) or c == '>' or c == '/') {
                self.state = State.tag_start_found;
                return .{ .consumed = if (ascii.isWhitespace(c)) 1 else 0 };
            }

            self.accumTagChar(c);
            return .{ .consumed = 1 };
        }

        /// Queue whitespace if its rank is higher than the current pending.
        fn queueWhitespace(self: *Self, ws: Whitespace) void {
            if (!self.any_text) return;
            if (self.pending_whitespace) |*pw| {
                pw.* = @enumFromInt(@max(@intFromEnum(pw.*), @intFromEnum(ws)));
            } else {
                self.pending_whitespace = ws;
            }
        }

        //<strong >ekdy...</strong>
        //       ^~
        fn handleTagStartFound(
            self: *Self,
            allocator: Allocator,
            html: []const u8,
        ) Error!ParseStep {
            const c = html[0];
            if (ascii.isWhitespace(c) or c == '/')
                return .{ .consumed = 1 };

            if (c != '>') {
                self.attr_return_state = State.tag_start_found;
                self.state = State.attr_key;
                return .{ .consumed = 0 };
            }

            defer {
                self.tag_buffer_len = 0;
                self.tag_buffer_overflow = false;
            }
            const tag = self.resolveTag();
            const inserted = try if (self.depths.svg > 0 or self.depths.math > 0)
                self.processModeBodyStartTag(tag, allocator)
            else if (self.depths.table > 0)
                self.processModeBodyStartTag(tag, allocator)
            else
                self.processModeBodyStartTag(tag, allocator);

            if (!inserted)
                return .{ .consumed = 1 };

            if (@hasDecl(T, "onTagStart")) {
                if (try self.policy.onTagStart(tag, self.depths.table)) |ws| {
                    self.queueWhitespace(ws);
                }
            }

            self.state = switch (tag) {
                .script => State.script,
                .frameset => State.frameset,
                .plaintext => State.plaintext,
                else => State.text,
            };

            if (tag_properties.get(tag).void)
                _ = self.stack.pop();

            return .{ .consumed = 1 };
        }

        //<strong >ekdy...</strong>
        //                 ^
        fn handleTagEnd(self: *Self, html: []const u8) ParseStep {
            const c = html[0];
            if (ascii.isWhitespace(c) or c == '>') {
                self.state = State.tag_end_found;
                return .{ .consumed = if (c == '>') 0 else 1 };
            }

            self.accumTagChar(c);
            return .{ .consumed = 1 };
        }

        fn closeTag(self: *Self, tag: Tag) T.Error!void {
            if (@hasDecl(T, "onTagEnd")) {
                const ws = try self.policy.onTagEnd(tag, self.depths.table);
                if (ws != null) {
                    self.queueWhitespace(ws.?);
                }
            }

            const tp = tag_properties.get(tag);
            if (tp.ignore)
                self.depths.ignore -|= 1;

            if (tp.preformatted) {
                self.depths.preformatted -|= 1;
                if (self.depths.preformatted == 0) self.preformatted_first = false;
            }

            if (tag == .table) {
                self.depths.table -|= 1;
            } else if (tag == .svg) {
                self.depths.svg -|= 1;
            } else if (tag == .math) {
                self.depths.math -|= 1;
            }
        }

        /// Closes implied tags.
        fn generate_implied(self: *Self, thorough: bool) T.Error!void {
            var new_length = self.stack.items.len;
            while (new_length > 0) : (new_length -= 1) {
                const tag = self.stack.items[new_length - 1];
                const tp = tag_properties.get(tag);
                if (!tp.implied_end and (!thorough or !tp.implied_end_thorough))
                    break;

                try self.closeTag(tag);
            }

            self.stack.items.len = new_length;
        }

        fn popUntilMatching(self: *Self, end_tag: Tag) T.Error!void {
            var found_idx = self.stack.items.len;
            while (found_idx > 0) : (found_idx -= 1) {
                if (end_tag == self.stack.items[found_idx - 1]) {
                    for (self.stack.items[found_idx - 1 ..]) |tag| {
                        try self.closeTag(tag);
                    }

                    self.stack.items.len = found_idx - 1;
                    return;
                }
            }
        }

        //<strong >ekdy...</strong >
        //                        ^~
        fn handleTagEndFound(self: *Self, html: []const u8) T.Error!ParseStep {
            const c = html[0];

            if (ascii.isWhitespace(c)) return .{ .consumed = 1 };

            if (c != '>') {
                self.attr_return_state = .tag_end_found;
                self.state = .attr_key;
                return .{ .consumed = 0 };
            }

            defer {
                self.tag_buffer_len = 0;
                self.tag_buffer_overflow = false;
            }
            try self.popUntilMatching(self.resolveTag());
            self.state = State.text;
            return .{ .consumed = 1 };
        }

        fn switchAttrEndState(self: *Self) void {
            self.state = self.attr_return_state;
            self.attr_return_state = .tag_start_found;
        }

        //<a href="http://...">ekdy</a>
        //   ^~~~
        fn handleAttrKey(self: *Self, html: []const u8) ParseStep {
            const c = html[0];
            if (c == '=') {
                self.state = State.attr_val;
                return .{ .consumed = 1 };
            }

            if (c == '>') {
                self.switchAttrEndState();
                return .{ .consumed = 0 };
            }

            return .{ .consumed = 1 };
        }

        //<a href="http://...">ekdy</a>
        //        ^~~~~~~~~~~~
        fn handleAttrVal(self: *Self, html: []const u8) ParseStep {
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
                    return .{ .consumed = 0 };
                } else {
                    self.attr_val_start = true;
                }
            }

            return .{ .consumed = 1 };
        }

        //<!-- ekdy -->
        //    ^~~~~~
        fn handleComment(self: *Self, html: []const u8) ParseStep {
            const cm = forwardMatch("-->", html);
            if (cm == .full) {
                self.state = State.text;
                return .{ .consumed = 3 };
            }

            if (cm == .partial) {
                return .{ .consumed = 0, .buffer_rest = true };
            }

            const cm2 = forwardMatch("--!>", html);
            if (cm2 == .full) {
                self.state = State.text;
                return .{ .consumed = 4 };
            }

            if (cm2 == .partial) {
                return .{ .consumed = 0, .buffer_rest = true };
            }

            return .{ .consumed = 1 };
        }

        //<plaintext>ekdy...
        //           ^~~~~~~
        fn handlePlaintext(self: *Self, html: []const u8) T.Error!ParseStep {
            // In plaintext null bytes are printed as invalid as
            // opposed to normal text mode where they are ignored.
            var inv_str: [8]u8 = undefined;
            const len = std.unicode.utf8Encode(
                decoding.html_unicode_invalid,
                &inv_str,
            ) catch unreachable;
            var last_valid_idx: usize = 0;
            for (html, 0..) |c, i| {
                if (c == 0) {
                    try self.policy.onText(html[last_valid_idx..i]);
                    try self.policy.onText(inv_str[0..len]);
                    last_valid_idx = i + 1;
                }
            }

            try self.policy.onText(html[last_valid_idx..]);
            return .{ .consumed = html.len };
        }

        // Check if given tag prefix is properly matched. For example if
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
        ) ?ParseStep {
            var lowercase_buf: [tag_prefix.len]u8 = undefined;
            const lc_html = ascii.lowerString(
                &lowercase_buf,
                html[0..@min(tag_prefix.len, html.len)],
            );
            const fw_match = forwardMatch(tag_prefix, lc_html);
            if (fw_match == .none) {
                return null;
            }

            if (fw_match == .partial) {
                return .{ .consumed = 0, .buffer_rest = true };
            }

            var script_match = false;
            var sub_cursor = tag_prefix.len;
            while (sub_cursor < html.len) {
                const c = html[sub_cursor];
                if (c == '>')
                    return .{ .consumed = sub_cursor + 1 };

                if (!ascii.isWhitespace(c) and c != '/') {
                    if (!script_match) return null;

                    // Some attribute is starting here. Save the
                    // current state to attr_return_state so we don't
                    // accidentally return to some weird state.
                    self.attr_return_state = self.state;
                    const orig_state = self.state;
                    self.state = .attr_key;

                    // In streaming attribute may not fully processed
                    // therefore we need to guarantee the original
                    // state is restored.
                    defer self.state = orig_state;

                    while (sub_cursor < html.len and self.state != orig_state) {
                        const sub_step_res = switch (self.state) {
                            .attr_key => self.handleAttrKey(html[sub_cursor..]),
                            .attr_val => self.handleAttrVal(html[sub_cursor..]),
                            else => {
                                unreachable;
                            },
                        };
                        sub_cursor += sub_step_res.consumed;
                        if (sub_step_res.buffer_rest) {
                            unreachable;
                        }
                    }
                } else {
                    sub_cursor += 1;
                    // In below states the final > is not required for tag start or end.
                    // Simply either ascii whitespace or / can end the tag.
                    if (self.state == .script_escaped or self.state == .script_double_escaped)
                        return .{ .consumed = sub_cursor };

                    script_match = true;
                }
            }

            // Consumed everything without resolving. This case
            // requires setting the following back to their original
            // values as we might be required to finish in the middle
            // of attribute parsing.
            self.attr_val_quote = null;
            self.attr_val_start = false;
            return .{ .consumed = 0, .buffer_rest = true };
        }

        // Handle exit from a script tag here.
        fn endScript(self: *Self) void {
            // Stack must have the script tag
            const st = self.stack.pop() orelse unreachable;
            if (st != .script)
                unreachable;

            self.state = .text;
            self.depths.ignore -|= 1;
        }

        // <script>ekdy...</script>
        //         ^~~~~~~
        fn handleScript(self: *Self, html: []const u8) ParseStep {
            // NOTE: Fast path for script transition check. If we only
            // check below using `tagMatchScriptMode` we always
            // lowercase the `html` which is extremely slow as it is
            // done on every character.
            if (html[0] != '<')
                return .{ .consumed = 1 };

            if (self.tagMatchScriptMode(html, "</script")) |m| {
                if (!m.buffer_rest)
                    self.endScript();

                return m;
            }

            const escape_tok = "<!--";
            return switch (forwardMatch(escape_tok, html)) {
                .none => .{ .consumed = 1 },
                .partial => .{ .consumed = 0, .buffer_rest = true },
                .full => blk: {
                    self.state = .script_escaped;
                    break :blk .{ .consumed = escape_tok.len };
                },
            };
        }

        // <script>ekdy <!-- ekdy....
        //                  ^~~~~~~~~
        fn handleScriptEscaped(self: *Self, html: []const u8) ParseStep {
            const esc_end_tok = "-->";
            const esc_end_m = forwardMatch(esc_end_tok, html);
            if (esc_end_m == .full) {
                self.state = .script;
                return .{ .consumed = esc_end_tok.len };
            }

            if (esc_end_m == .partial) {
                return .{ .consumed = 0, .buffer_rest = true };
            }

            if (self.tagMatchScriptMode(html, "<script")) |m| {
                if (!m.buffer_rest)
                    self.state = .script_double_escaped;

                return m;
            }

            if (self.tagMatchScriptMode(html, "</script")) |m| {
                if (!m.buffer_rest)
                    self.endScript();

                return m;
            }

            return .{ .consumed = 1 };
        }

        // <script>ekdy <!-- ... <script> ekdy...
        //                               ^~~~~~~~
        fn handleScriptDoubleEscaped(self: *Self, html: []const u8) ParseStep {
            const esc_end_tok = "-->";
            const esc_end_m = forwardMatch(esc_end_tok, html);
            if (esc_end_m == .full) {
                self.state = .script;
                return .{ .consumed = esc_end_tok.len };
            }

            if (esc_end_m == .partial) {
                return .{ .consumed = 0, .buffer_rest = true };
            }

            if (self.tagMatchScriptMode(html, "</script")) |m| {
                if (!m.buffer_rest)
                    self.state = .script_escaped;

                return m;
            }

            return .{ .consumed = 1 };
        }

        fn handleFrameSet(self: *Self, html: []const u8) ParseStep {
            _ = self;
            return .{ .consumed = html.len };
        }
    };
}

const talloc = std.testing.allocator;

/// Check if html to text works as expected both as a single and
/// streaming payload.
fn expectConvert(expected: []const u8, html_text: []const u8) !void {
    var allocating = std.Io.Writer.Allocating.init(talloc);
    defer allocating.deinit();
    const InnerText = @import("policy/InnerText.zig");
    var policy = InnerText{ .writer = &allocating.writer };
    const InnerTextExtractor = TextExtractor(InnerText);
    var extractor = InnerTextExtractor{ .policy = &policy };
    defer extractor.deinit(talloc);

    // Check as a single payload.
    try extractor.feed(talloc, html_text);
    try extractor.finish();
    const single_shot_res = std.testing.expectEqualStrings(expected, allocating.written());

    allocating.clearRetainingCapacity();
    var stream_policy = InnerText{ .writer = &allocating.writer };
    var stream_extractor = InnerTextExtractor{ .policy = &stream_policy };
    defer stream_extractor.deinit(talloc);

    // Check streaming 1 character at a time.
    for (html_text) |c| {
        try stream_extractor.feed(talloc, (&c)[0..1]);
    }
    try stream_extractor.finish();
    const stream_res = std.testing.expectEqualStrings(expected, allocating.written());
    single_shot_res catch {
        std.debug.print("single-shot failed on input: {s}\n", .{html_text});
    };

    stream_res catch {
        std.debug.print("streaming failed on input: {s}\n", .{html_text});
    };
    try single_shot_res;
    try stream_res;
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

test "tag_buffer_overflow" {
    try expectConvert("abc\n\nxyz", "<" ++ "x" ** 100 ++ ">abc</" ++ "y" ** 200 ++ "><p>xyz</p>");
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

    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();
    const html_file = try cwd.openFile(io, html_path, .{});
    defer html_file.close(io);

    var html_file_reader = html_file.reader(io, &.{});
    const html = try html_file_reader.interface.allocRemaining(talloc, .unlimited);
    defer talloc.free(html);

    // Read text file
    const text_path = try fs.path.join(
        talloc,
        &[_][]const u8{ resource_dir, file_base ++ ".txt" },
    );
    defer talloc.free(text_path);

    const text_file = try cwd.openFile(io, text_path, .{});
    defer text_file.close(io);

    var text_file_reader = text_file.reader(io, &.{});
    const text = try text_file_reader.interface.allocRemaining(talloc, .unlimited);
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

    // std.debug.print("running on={s}\n", .{html_da.items});
    return expectConvert(exp, html_da.items);
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
    const io = std.testing.io;
    const ekdytest_file = try std.Io.Dir.cwd().openFile(io, ekdytest_path, .{});
    defer ekdytest_file.close(io);

    const read_buf = try talloc.alloc(u8, (try ekdytest_file.stat(io)).size);
    defer talloc.free(read_buf);
    var et_reader = ekdytest_file.reader(io, read_buf);
    const reader = &et_reader.interface;

    var html_da = ArrayList(u8).empty;
    var text_da = ArrayList(u8).empty;
    defer {
        html_da.deinit(talloc);
        text_da.deinit(talloc);
    }

    var in_data = false;
    var test_id: u64 = 0;
    var deviation_i: u64 = 0;
    var errors = ArrayList(anyerror!void).empty;
    defer errors.deinit(talloc);
    while (reader.takeDelimiterInclusive('\n')) |line| {
        if (std.mem.eql(u8, line, "#data\n")) {
            in_data = true;
            if (html_da.items.len == 0)
                continue;

            defer text_da.clearRetainingCapacity();
            defer html_da.clearRetainingCapacity();
            defer test_id += 1;

            expectHTML5CheckHelper(
                &html_da,
                &text_da,
                &deviation_i,
                deviations,
                test_id,
            ) catch |terr| {
                std.debug.print("failed test_id={} on '{s}'\n", .{
                    test_id,
                    html_da.items,
                });
                try errors.append(talloc, terr);
            };
        } else if (std.mem.eql(u8, line, "#text\n")) {
            in_data = false;
        } else if (in_data) {
            try html_da.appendSlice(talloc, line);
        } else {
            try text_da.appendSlice(talloc, line);
        }
    } else |err| {
        if (err != error.EndOfStream) return err;
        expectHTML5CheckHelper(
            &html_da,
            &text_da,
            &deviation_i,
            deviations,
            test_id,
        ) catch |terr| {
            try errors.append(talloc, terr);
        };
    }

    for (errors.items) |e| {
        try e;
    }
}

test "html5lib_tests1" {
    // 32: Table foster parenting.
    // 34: <select> without <option> or <optgroup>
    // 75: Most likely adoption rules are fixing the tree.
    // 77-79: <table> foster parenting.
    // 86: Table <tr> and <td> handling.
    try expectHTML5(
        "tests1.ekdytest",
        &.{
            .{ 32, "helloexcite!me!please!" },         .{ 34, "A\nB\nCD\nE" },
            .{ 75, "abc def ghi\n\njkl mno pqr stu" }, .{ 77, "ababr\nx\naoe" },
            .{ 78, "aba\nbrx\naoe" },
            .{ 79, "aba\nbrx\naoe" }, // .{ 86, "X" },
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
        // .{ 19, "</foreignObject></svg><div>bar</div>" },
        // .{ 20, "" },
        .{ 37, "div 1\nbutton\ndiv 2\ndiv 3" }, .{ 38, "button" },
    });
}

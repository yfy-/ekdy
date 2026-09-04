/// A text output policy that best approximates browser inner text
/// rendering (specifically chromium). This tries to mimic the
/// clipboard of a user when they copy an entire page within the
/// browser.
const std = @import("std");
const html = @import("../html.zig");

const tag_start_whitespaces = std.EnumMap(html.Tag, html.Whitespace).init(.{
    .hr = .single_break,
    .xmp = .single_break,
    .caption = .single_break,
    .colgroup = .single_break,
    .datalist = .single_break,
    .dd = .single_break,
    .div = .single_break,
    .dt = .single_break,
    .fieldset = .single_break,
    .figcaption = .single_break,
    .footer = .single_break,
    .form = .single_break,
    .header = .single_break,
    .legend = .single_break,
    .li = .single_break,
    .menu = .single_break,
    .optgroup = .single_break,
    .option = .single_break,
    .summary = .single_break,
    .tbody = .single_break,
    // .tfoot = .single_break,
    // .th = .single_break,
    // .thead = .single_break,
    .address = .double_break,
    .article = .double_break,
    .aside = .double_break,
    .blockquote = .double_break,
    .center = .double_break,
    .details = .double_break,
    .dialog = .double_break,
    .dir = .double_break,
    .dl = .double_break,
    .figure = .double_break,
    .h1 = .single_break,
    .h2 = .single_break,
    .h3 = .single_break,
    .h4 = .single_break,
    .h5 = .single_break,
    .h6 = .single_break,
    .hgroup = .double_break,
    .main = .double_break,
    .nav = .double_break,
    .ol = .double_break,
    .p = .double_break,
    .search = .double_break,
    .section = .double_break,
    .ul = .single_break,
    // .tr = .single_break,
    // .td = .single_break,
    .pre = .single_break,
});

const tag_end_whitespaces = std.EnumMap(html.Tag, html.Whitespace).init(.{
    .hr = .single_break,
    .xmp = .single_break,
    .caption = .single_break,
    .colgroup = .single_break,
    .datalist = .single_break,
    .dd = .single_break,
    .div = .single_break,
    .dt = .single_break,
    .fieldset = .single_break,
    .figcaption = .single_break,
    .footer = .single_break,
    .form = .single_break,
    .header = .single_break,
    .legend = .single_break,
    .li = .single_break,
    .menu = .single_break,
    .optgroup = .single_break,
    .option = .single_break,
    .summary = .single_break,
    .tbody = .single_break,
    // .tfoot = .single_break,
    // .th = .single_break,
    // .thead = .single_break,
    .address = .double_break,
    .article = .double_break,
    .aside = .double_break,
    .blockquote = .double_break,
    .center = .double_break,
    .details = .double_break,
    .dialog = .double_break,
    .dir = .double_break,
    .dl = .double_break,
    .figure = .double_break,
    .h1 = .single_break,
    .h2 = .single_break,
    .h3 = .single_break,
    .h4 = .single_break,
    .h5 = .single_break,
    .h6 = .single_break,
    .hgroup = .double_break,
    .main = .double_break,
    .nav = .double_break,
    .ol = .double_break,
    .p = .double_break,
    .search = .double_break,
    .section = .double_break,
    .ul = .single_break,
    .table = .single_break,
    .pre = .single_break,
});

pub const ignored_tags = [_]html.Tag{
    .audio,             .canvas,  .datalist, .fencedframe, .frameset, .iframe, .map,      .annotation,
    .@"annotation-xml", .noembed, .noframes, .picture,     .svg,      .video,  .textarea, .title,
    .rp,
};

const Writer = std.Io.Writer;
pub const Error = Writer.Error;

const Self = @This();

writer: *Writer,
first_tr: bool = true,
first_td_th: bool = true,

pub fn onTagStart(self: *Self, tag: html.Tag, table_depth: usize) Error!?html.Whitespace {
    // std.debug.print("TAG START: {}\n", .{tag});
    if (table_depth == 0)
        return tag_start_whitespaces.get(tag);

    if (tag == .tr) {
        if (self.first_tr) {
            self.first_tr = false;
        } else {
            try self.writer.writeByte('\n');
        }
    } else if (tag == .td or tag == .th) {
        if (self.first_td_th) {
            self.first_td_th = false;
        } else {
            try self.writer.writeByte('\t');
        }
    }

    return tag_start_whitespaces.get(tag);
}

pub fn onTagEnd(self: *Self, end_tag: html.Tag, table_depth: usize) Error!?html.Whitespace {
    // std.debug.print("TAG END: {}\n", .{end_tag});
    if (end_tag == .table and table_depth < 2) {
        self.first_tr = true;
        self.first_td_th = true;
    }

    return tag_end_whitespaces.get(end_tag);
}

pub fn onText(self: *Self, text: []const u8) Error!void {
    // std.debug.print("OUTPUT: {s}\n", .{text});
    try self.writer.writeAll(text);
}

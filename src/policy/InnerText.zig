/// A text output policy that best approximates browser inner text
/// rendering (specifically chromium). This tries to mimic the
/// clipboard of a user when they copy an entire page within the
/// browser.
const std = @import("std");
const html = @import("../html.zig");

const tag_start_whitespaces = std.EnumMap(html.Tag, html.Whitespace).init(.{
    .hr = .double_break,
    .xmp = .double_break,
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
    .menuitem = .single_break,
    .optgroup = .single_break,
    .option = .single_break,
    .summary = .single_break,
    .tbody = .single_break,
    .tfoot = .single_break,
    .th = .single_break,
    .thead = .single_break,
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
    .pre = .double_break,
    .search = .double_break,
    .section = .double_break,
    .ul = .single_break,
    .tr = .single_break,
    .td = .single_break,
});

const tag_end_whitespaces = std.EnumMap(html.Tag, html.Whitespace).init(.{
    .hr = .double_break,
    .xmp = .double_break,
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
    .menuitem = .single_break,
    .optgroup = .single_break,
    .option = .single_break,
    .summary = .single_break,
    .tbody = .single_break,
    .tfoot = .single_break,
    .th = .single_break,
    .thead = .single_break,
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
    .pre = .double_break,
    .search = .double_break,
    .section = .double_break,
    .ul = .single_break,
    .table = .single_break,
});

// Tag properties is an array of tuples where each tuple is a tag and
// its property.
pub const tag_property_overrides = [_]struct { html.Tag, html.TagProperty }{.{
    .textarea, ta: {
        // Just mark <textarea> as ignore, reserving other default properties.
        var def_ta = html.default_tag_properties.get(.textarea);
        def_ta.is_ignore = true;
        break :ta def_ta;
    },
}};

const Self = @This();

pub fn onTagStart(self: *Self, tag: html.Tag, writer: *std.io.Writer) !?html.Whitespace {
    _ = self;
    _ = writer;
    return tag_start_whitespaces.get(tag);
}

pub fn onTagEnd(self: *Self, tag: html.Tag, writer: *std.io.Writer) !?html.Whitespace {
    _ = self;
    _ = writer;
    return tag_end_whitespaces.get(tag);
}

const std = @import("std");
const http = std.http;
const Io = std.Io;
const xml = @import("xml");
const logger = @import("utilities").log;
const structs = @import("structs.zig");
const feedResult = structs.FeedResult;
const feedRequest = structs.FeedRequest;
const feedEntry = structs.FeedEntry;
const summary = structs.Summary;
const time = @import("utilities").time;
const deinitList = @import("utilities").deinitList;

pub const Client = struct {
    const Self = @This();

    cl: http.Client = undefined,
    a: std.mem.Allocator,
    io: std.Io,
    client_name: []const u8,
    logger: *logger.Logger,

    pub fn init(s: *Self, a: std.mem.Allocator, io: std.Io, name: []const u8, l: *logger.Logger) !void {
        s.a = a;
        s.client_name = try a.dupe(u8, name);
        s.cl = http.Client{ .allocator = a, .io = io };
        s.io = io;
        s.logger = l;
    }

    pub fn deinit(s: *Self) void {
        s.cl.deinit();
        s.a.free(s.client_name);
    }

    fn log(s: *Self, level: logger.Level, comptime msg: []const u8, fmt: anytype) void {
        s.logger.format(level, msg, fmt, @typeName(@This())) catch unreachable;
    }

    fn buildUri(s: *Self, request: feedRequest) !std.Uri {
        return std.Uri.parse(request.url) catch |err| {
            switch (err) {
                error.InvalidFormat, error.UnexpectedCharacter => {
                    log(s, .Error, "Error during parsing of\n\turl: {s}\n\terror: {s}", .{ request.url, @errorName(err) });
                    return err;
                },
                error.InvalidPort, error.InvalidHostName => {
                    log(s, .Error, "Invalid host or port given:{s} \n\t{s}", .{ request.url, @errorName(err) });
                    return err;
                },
            }
        };
    }

    fn fetch(s: *Self, uri: std.Uri, writer: *std.Io.Writer) !std.http.Client.FetchResult {
        const response = s.cl.fetch(.{
            .location = .{ .uri = uri },
            .response_writer = writer,
        }) catch |err| {
            log(s, .Error, "Error while requesting given url: {s}\n    Error {s}: {any}", .{ uri.path.raw, @errorName(err), err });
            return err;
        };
        try writer.flush();
        return response;
    }

    fn buildResult(s: *Self, response: std.http.Client.FetchResult, body: *std.Io.Writer.Allocating, request: feedRequest) !feedResult {
        var res: feedResult = .init(s.a);
        res.body = try std.fmt.allocPrint(s.a, "{s}", .{body.written()});
        res.status = response.status;
        res.url = try s.a.dupe(u8, request.url);
        res.headers = .empty;
        res.errors = .empty;
        res.request = request.clone(s.a);

        const entries = parseResponse(res, s.a, s.io, s.logger) catch |err| blk: {
            std.debug.print("Error while parsing response: {any}\n", .{@errorName(err)});
            break :blk std.ArrayList(feedEntry).empty;
        };

        for (entries.items) |item| {
            try res.entries.append(s.a, try item.clone(s.a));
        }
        return res;
    }

    pub fn pull(s: *Self, request: feedRequest) !feedResult {
        const uri = try s.buildUri(request);

        var body = std.Io.Writer.Allocating.init(s.a);
        defer body.deinit();

        const response = try s.fetch(uri, &body.writer);

        return try s.buildResult(response, &body, request);
    }

    fn parseResponse(result: feedResult, a: std.mem.Allocator, io: std.Io, l: *logger.Logger) !std.ArrayList(feedEntry) {
        var entries: std.ArrayList(feedEntry) = .empty;

        if (result.body == null) return entries;

        var static_reader: xml.Reader.Static = .init(a, result.body orelse "", .{});
        defer static_reader.deinit();
        const reader = &static_reader.interface;

        var itemCount: usize = 0;
        var itemOpened = false;

        var entry: feedEntry = .{};

        while (try reader.read() != .eof) {
            if (reader.node.? == .element_start) {
                for (reader.spans.items[0..]) |item| {
                    const elementName = reader.buf[item.start..item.end];
                    if (std.mem.eql(u8, "item", elementName)) {
                        // Reset entry state at the start of each <item> so fields
                        // from previous items cannot leak into the next record.
                        itemOpened = true;
                        entry = .init(a, "", "", "", "", "");
                        errdefer entry.deinit(a);
                    } else if (std.ascii.eqlIgnoreCase("title", elementName) and itemOpened) {
                        entry.title = getElementContents(a, "title", reader.buf);
                        continue;
                    } else if (std.ascii.eqlIgnoreCase("description", elementName) and itemOpened) {
                        entry.subject = getElementContents(a, "description", reader.buf);
                        continue;
                    } else if (std.ascii.eqlIgnoreCase("link", elementName) and itemOpened) {
                        entry.link = getElementContents(a, "link", reader.buf);
                        continue;
                    } else if (itemOpened and std.ascii.eqlIgnoreCase("enclosure", elementName)) {
                        if (reader.attributes.get("url")) |attribute_index| {
                            entry.link = try a.dupe(u8, try reader.attributeValue(attribute_index));
                        }
                        continue;
                    } else if (std.ascii.eqlIgnoreCase("pubDate", elementName) and itemOpened) {
                        entry.published = getElementContents(a, "pubDate", reader.buf);

                        const dt = time.parseDateTime(entry.published.?) catch |err| {
                            try l.format(.Error, "ERROR: {s} -> {any}\n", .{ entry.published.?, err }, @typeName(@This()));
                            return err;
                        };

                        const tz_sign: u8 = if (dt.timezone >= 0) '+' else '-';
                        const tz_value = @abs(dt.timezone);

                        const iso8601 = try std.fmt.allocPrint(
                            a,
                            "{}-{:0>2}-{:0>2}T{:0>2}:{:0>2}:{:0>2}.{:0>3}{c}{:0>4}",
                            .{ dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second, dt.millisecond, tz_sign, tz_value },
                        );
                        defer a.free(iso8601);
                        entry.parsedDate = try a.dupe(u8, iso8601);
                        continue;
                    }
                }
            } else if (reader.node.? == .element_end) {
                const elementName = reader.elementName();
                if (std.mem.eql(u8, "item", elementName)) {
                    itemOpened = false;
                    itemCount += 1;

                    const now = std.Io.Clock.now(.real, io).toSeconds();
                    const publishedDt = try time.parseDateTime(entry.published);
                    const publishedUnix: i64 = @intCast(time.dateTimeToUnixUtc(publishedDt));
                    const ageHours = time.differenceHours(publishedUnix, now);

                    // age_limit_hours == 0 is treated as "no age filter".
                    if (result.request.age_limit_hours == 0 or ageHours <= result.request.age_limit_hours) {
                        try entries.append(a, entry);
                    } else {
                        //if we don't include the entry, we clean it up
                        entry.deinit(a);
                    }
                }
            }
            if (itemCount >= result.request.item_limit) {
                break;
            }
        }

        return entries;
    }

    // Extracts text between the first matching open/close tag pair in buffer.
    // Does not handle nested tags, CDATA sections, or namespace prefixes; assumes
    // well-formed flat RSS fields such as <title>, <link>, and <description>.
    fn getElementContents(a: std.mem.Allocator, elementName: []const u8, buffer: []const u8) ?[]const u8 {
        // const whitespace = " \t\n\r";
        const opening = std.fmt.allocPrint(a, "<{s}>", .{elementName}) catch unreachable;
        defer a.free(opening);
        const closing = std.fmt.allocPrint(a, "</{s}>", .{elementName}) catch unreachable;
        defer a.free(closing);
        const contents_start: usize = opening.len;
        const closing_bracket = std.mem.find(u8, buffer[contents_start..], closing);
        if (closing_bracket != null) {
            const contents_end: usize = contents_start + @min(closing_bracket.?, buffer.len);
            return a.dupe(u8, buffer[contents_start..contents_end]) catch unreachable;
        } else {
            return null; //a.dupe(u8, "bad data") catch unreachable;
        }
    }
};

fn deinitEntries(entries: *std.ArrayList(feedEntry), a: std.mem.Allocator) void {
    deinitList(entries, a);
}

fn testLogger(a: std.mem.Allocator, io: std.Io) !*logger.Logger {
    const l = try logger.buildLogger(a, io, .{ .enabled = false, .stdLog = false });
    l.options.stdLog = false;
    return l;
}

test "getElementContents returns text between matching tags" {
    const a = std.testing.allocator;

    const text = Client.getElementContents(a, "title", "<title>Hello</title>");
    defer if (text != null and text.?.len > 0) a.free(text.?);

    try std.testing.expectEqualStrings("Hello", text.?);
}

test "getElementContents returns nu8ll string when closing tag absent" {
    const a = std.testing.allocator;

    const text = Client.getElementContents(a, "title", "<title>Hello");
    try std.testing.expect(text == null);
}

test "getElementContents returns empty string for empty element" {
    const a = std.testing.allocator;

    const text = Client.getElementContents(a, "title", "<title></title>");
    try std.testing.expectEqualStrings("", text.?);
}

test "parseResponse extracts entries from minimal RSS XML" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    const l = try testLogger(a, io);
    defer l.deinit();

    const req = feedRequest{ .url = try a.dupe(u8, "https://example.com/feed"), .age_limit_hours = 0, .item_limit = 5 };
    defer @constCast(&req).deinit(a);

    var result: feedResult = .init(a);
    defer result.deinit();
    result.request = req.clone(a);
    result.body = try a.dupe(
        u8,
        "<rss><channel><item><title>T1</title><description>D1</description><link>L1</link><pubDate>Fri, 17 Apr 2026 08:00:00 -0400</pubDate></item></channel></rss>",
    );

    var entries = try Client.parseResponse(result, a, io, l);
    defer deinitEntries(&entries, a);

    try std.testing.expectEqual(@as(usize, 1), entries.items.len);
    try std.testing.expectEqualStrings("T1", entries.items[0].title.?);
    try std.testing.expectEqualStrings("D1", entries.items[0].subject.?);
    try std.testing.expectEqualStrings("L1", entries.items[0].link.?);
    try std.testing.expect(entries.items[0].parsedDate != null);
}

test "parseResponse item_limit stops reading after N entries" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    const l = try testLogger(a, io);
    defer l.deinit();

    const req = feedRequest{ .url = try a.dupe(u8, "https://example.com/feed"), .age_limit_hours = 0, .item_limit = 2 };
    defer @constCast(&req).deinit(a);

    var result: feedResult = .init(a);
    defer result.deinit();
    result.request = req.clone(a);
    result.body = try a.dupe(
        u8,
        "<rss><channel>" ++
            "<item><title>A</title><description>A</description><link>A</link><pubDate>Fri, 17 Apr 2026 08:00:00 -0400</pubDate></item>" ++
            "<item><title>B</title><description>B</description><link>B</link><pubDate>Fri, 17 Apr 2026 09:00:00 -0400</pubDate></item>" ++
            "<item><title>C</title><description>C</description><link>C</link><pubDate>Fri, 17 Apr 2026 10:00:00 -0400</pubDate></item>" ++
            "</channel></rss>",
    );

    var entries = try Client.parseResponse(result, a, io, l);
    defer deinitEntries(&entries, a);

    try std.testing.expectEqual(@as(usize, 2), entries.items.len);
    try std.testing.expectEqualStrings("A", entries.items[0].title.?);
    try std.testing.expectEqualStrings("B", entries.items[1].title.?);
}

test "parseResponse age_limit_hours 0 disables age filter" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    const l = try testLogger(a, io);
    defer l.deinit();

    const req = feedRequest{ .url = try a.dupe(u8, "https://example.com/feed"), .age_limit_hours = 0, .item_limit = 5 };
    defer @constCast(&req).deinit(a);

    var result: feedResult = .init(a);
    defer result.deinit();
    result.request = req.clone(a);
    result.body = try a.dupe(
        u8,
        "<rss><channel><item><title>Old</title><description>Old</description><link>Old</link><pubDate>Sat, 01 Jan 2000 00:00:00 +0000</pubDate></item></channel></rss>",
    );

    var entries = Client.parseResponse(result, a, io, l) catch |err| blk: {
        std.debug.print("Error while parsing response: {any}\n", .{@errorName(err)});
        break :blk std.ArrayList(feedEntry).empty;
    };
    defer deinitEntries(&entries, a);

    try std.testing.expectEqual(@as(usize, 1), entries.items.len);
}

test "parseResponse excludes entries older than age_limit_hours" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    const l = try testLogger(a, io);
    defer l.deinit();

    const req = feedRequest{ .url = try a.dupe(u8, "https://example.com/feed"), .age_limit_hours = 1, .item_limit = 5 };
    defer @constCast(&req).deinit(a);

    var result: feedResult = .init(a);
    defer result.deinit();
    result.request = req.clone(a);
    result.body = try a.dupe(
        u8,
        "<rss><channel><item><title>Old</title><description>Old</description><link>Old</link><pubDate>Sat, 01 Jan 2000 00:00:00 +0000</pubDate></item></channel></rss>",
    );

    var entries = Client.parseResponse(result, a, io, l) catch |err| blk: {
        std.debug.print("Error while parsing response: {any}\n", .{@errorName(err)});
        break :blk std.ArrayList(feedEntry).empty;
    };
    defer deinitEntries(&entries, a);

    try std.testing.expectEqual(@as(usize, 0), entries.items.len);
}

test "parseResponse field isolation between items" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    const l = try testLogger(a, io);
    defer l.deinit();

    const req = feedRequest{ .url = try a.dupe(u8, "https://example.com/feed"), .age_limit_hours = 0, .item_limit = 5 };
    defer @constCast(&req).deinit(a);

    var result: feedResult = .init(a);
    defer result.deinit();
    result.request = req.clone(a);
    result.body = try a.dupe(
        u8,
        "<rss><channel>" ++
            "<item><title>One</title><description>D1</description><link>L1</link><pubDate>Fri, 17 Apr 2026 08:00:00 -0400</pubDate></item>" ++
            "<item><title>Two</title><description>D2</description><pubDate>Fri, 17 Apr 2026 09:00:00 -0400</pubDate></item>" ++
            "</channel></rss>",
    );

    var entries = Client.parseResponse(result, a, io, l) catch |err| blk: {
        std.debug.print("Error while parsing response: {any}\n", .{@errorName(err)});
        break :blk std.ArrayList(feedEntry).empty;
    };
    defer deinitEntries(&entries, a);

    try std.testing.expectEqual(@as(usize, 2), entries.items.len);
    try std.testing.expectEqualStrings("L1", entries.items[0].link.?);
    try std.testing.expectEqualStrings("", entries.items[1].link.?);
}

test "parseResponse returns empty list for null body" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    const l = try testLogger(a, io);
    defer l.deinit();

    const req = feedRequest{ .url = try a.dupe(u8, "https://example.com/feed"), .age_limit_hours = 0, .item_limit = 5 };
    defer @constCast(&req).deinit(a);

    var result: feedResult = .init(a);
    defer result.deinit();
    result.request = req.clone(a);
    result.body = null;

    var entries = Client.parseResponse(result, a, io, l) catch |err| blk: {
        std.debug.print("Error while parsing response: {any}\n", .{@errorName(err)});
        break :blk std.ArrayList(feedEntry).empty;
    };
    defer deinitEntries(&entries, a);

    try std.testing.expectEqual(@as(usize, 0), entries.items.len);
}

test "parseResponse returns empty list for gibberish body" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    const l = try testLogger(a, io);
    defer l.deinit();

    const req = feedRequest{ .url = try a.dupe(u8, "https://example.com/feed"), .age_limit_hours = 0, .item_limit = 5 };
    defer @constCast(&req).deinit(a);

    var result: feedResult = .init(a);
    defer result.deinit();
    result.request = req.clone(a);
    result.body = try a.dupe(u8, "2345asd");

    var entries = Client.parseResponse(result, a, io, l) catch |err| blk: {
        std.debug.print("Error while parsing response: {any}\n", .{@errorName(err)});
        break :blk std.ArrayList(feedEntry).empty;
    };
    defer deinitEntries(&entries, a);

    try std.testing.expectEqual(@as(usize, 0), entries.items.len);
}

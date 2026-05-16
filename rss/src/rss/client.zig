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

    pub fn pull(s: *Self, request: feedRequest) !feedResult {
        const uri = std.Uri.parse(request.url) catch |err| {
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

        //body
        var body = std.Io.Writer.Allocating.init(s.a);
        defer body.deinit();

        const response = s.cl.fetch(.{
            .location = .{ .uri = uri },
            .response_writer = &body.writer,
        }) catch |err| {
            log(s, .Error, "Error while requesting given url: {s}\n    Error {s}: {any}", .{ request.url, @errorName(err), err });
            return err;
        };

        try body.writer.flush();

        var res: feedResult = .init(s.a);
        res.body = try std.fmt.allocPrint(s.a, "{s}", .{body.written()});
        res.status = response.status;
        res.url = try s.a.dupe(u8, request.url);
        res.headers = .empty;
        res.errors = .empty;
        res.request = request.clone(s.a);

        const entries = try parseResponse(res, s.a, s.io, s.logger);

        for (entries.items) |item| {
            try res.entries.append(s.a, try item.clone(s.a));
        }

        return res;
    }

    fn parseResponse(result: feedResult, a: std.mem.Allocator, io: std.Io, l: *logger.Logger) !std.ArrayList(feedEntry) {
        var entries: std.ArrayList(feedEntry) = .empty;

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
                        errdefer {
                            entry.deinit(a);
                        }
                    } else if (std.ascii.eqlIgnoreCase("title", elementName) and itemOpened) {
                        entry.title = getElementContents(a, "title", reader.buf);
                        continue;
                    } else if (std.ascii.eqlIgnoreCase("description", elementName) and itemOpened) {
                        entry.subject = getElementContents(a, "description", reader.buf);
                        continue;
                    } else if (std.ascii.eqlIgnoreCase("link", elementName) and itemOpened) {
                        entry.link = getElementContents(a, "link", reader.buf);
                        continue;
                    } else if (std.ascii.eqlIgnoreCase("pubDate", elementName) and itemOpened) {
                        entry.published = getElementContents(a, "pubDate", reader.buf);

                        const dt = time.parseDateTime(entry.published, io) catch |err| {
                            try l.format(.Error, "ERROR: {s} -> {any}\n", .{ entry.published, err }, @typeName(@This()));
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
                    const publishedDt = try time.parseDateTime(entry.published, io);
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
    fn getElementContents(a: std.mem.Allocator, elementName: []const u8, buffer: []const u8) []const u8 {
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
            return "";
        }
    }
};

const std = @import("std");
const logger = @import("utilities").log;
const logBuilder = @import("utilities").log.buildLogger;
const structs = @import("structs.zig");
const feedResult = structs.FeedResult;
const feedRequest = structs.FeedRequest;
const feedRequests = structs.FeedRequests;
const summary = structs.Summary;
const Client = @import("client.zig").Client;
const utilities = @import("utilities");
const protectedCollection = utilities.protectedCollection;

const client_name = "test-client-russell";

pub const rss = struct {
    const Self = @This();

    a: std.mem.Allocator = undefined,
    io: std.Io = undefined,
    protectedCollection: protectedCollection(feedResult),
    logger: *logger.Logger,

    pub fn init(s: *Self, a: std.mem.Allocator, io: std.Io, l: *logger.Logger) *Self {
        s.a = a;
        s.io = io;
        s.protectedCollection.init(a, io);
        s.logger = l;
        return s;
    }

    pub fn deinit(s: *Self) void {
        for (s.protectedCollection.collection.items) |item| {
            item.deinit();

            const item_type = @TypeOf(item);
            if (@typeInfo(item_type) == .pointer) {
                s.a.destroy(item);
            }
        }
        s.protectedCollection.collection.deinit(s.a);
    }

    fn log(s: *Self, level: logger.Level, comptime msg: []const u8, args: anytype) void {
        s.logger.format(level, msg, args, @typeName(Self)) catch unreachable;
    }

    pub fn buildRequest(s: *Self, json: []const u8) !feedRequest {
        var scanner = std.json.Scanner.initCompleteInput(s.a, json);
        defer scanner.deinit();

        var diag = std.json.Diagnostics{};
        scanner.enableDiagnostics(&diag);

        const options = std.json.ParseOptions{ .ignore_unknown_fields = true, .allocate = .alloc_always };
        const parsed = std.json.parseFromTokenSource(feedRequest, s.a, &scanner, options) catch |err| {
            s.log(.Info, "Parsing failed at {d}:{d} - {s}\n", .{
                diag.getLine(),
                diag.getColumn(),
                @errorName(err),
            });
            return err;
        };
        defer parsed.deinit();

        // Clone before parsed is deinitialized so the returned request owns
        // its memory independently of the parser's temporary allocations.
        const return_value = parsed.value.clone(s.a);

        return return_value;
    }

    pub fn processRequests(s: *Self, requests: feedRequests) !std.ArrayList(feedResult) {
        var g: std.Io.Group = .init;
        // Clear prior results so each call returns only the current batch.
        try s.protectedCollection.clear();

        for (requests.requests) |request| {
            try g.concurrent(s.io, pullFeed, .{ s, request });
        }

        g.await(s.io) catch |err| {
            s.log(.Error, "Error awaiting group: {any}\n", .{err});
            return err;
        };

        return try s.protectedCollection.get();
    }

    pub fn pullFeed(s: *Self, request: feedRequest) !void {
        var cl = s.a.create(Client) catch unreachable;
        cl.init(s.a, s.io, client_name, s.logger) catch unreachable;
        defer s.a.destroy(cl);
        defer cl.deinit();

        const result = cl.pull(request) catch |err| errorCapture: {
            var erredFeed: feedResult = .init(s.a);
            erredFeed.request = request.clone(s.a);
            s.log(.Warning, "ERRORED {s}: error while pulling feed.\n", .{@errorName(err)});
            const error_message = std.fmt.allocPrint(s.a, "{s} error while pulling feed.  Bad URL", .{@errorName(err)}) catch unreachable;
            defer s.a.free(error_message);
            erredFeed.errors.append(s.a, s.a.dupe(u8, error_message) catch unreachable) catch unreachable;
            break :errorCapture erredFeed;
        };
        defer result.deinit();

        s.protectedCollection.add(result) catch unreachable;
    }

    pub fn toJson(s: *Self, results: []feedResult) ![]const u8 {
        var out: std.Io.Writer.Allocating = .init(s.a);
        const writer = &out.writer;
        defer out.deinit();

        var summaries: std.ArrayList(*summary) = .empty;
        defer summaries.deinit(s.a);
        defer for (summaries.items) |sum| {
            sum.deinit(s.a);
            s.a.destroy(sum);
        };

        for (results) |result| {
            const sum = summary.fromFeedResult(s.a, result);
            try summaries.append(s.a, sum);
        }

        try std.json.Stringify.value(summaries, .{ .whitespace = .indent_tab }, writer);
        return std.fmt.allocPrint(s.a, "{s}", .{writer.buffer[0..writer.end]});
    }
};

test "buildRequest parses json request" {
    const a = std.testing.allocator;

    const log = try logBuilder(a, std.testing.io, .{});
    defer log.deinit();

    var service_instance: rss = undefined;
    _ = service_instance.init(a, std.testing.io, log);
    defer service_instance.deinit();

    var request = try service_instance.buildRequest("{\"url\":\"https://example.com/feed\",\"age_limit_hours\":24,\"item_limit\":5}");
    defer request.deinit(a);

    try std.testing.expectEqualStrings("https://example.com/feed", request.url);
    try std.testing.expectEqual(@as(usize, 24), request.age_limit_hours);
    try std.testing.expectEqual(@as(usize, 5), request.item_limit);
}

test "pullFeed captures request errors into the collection" {
    const a = std.testing.allocator;

    const log = try logBuilder(a, std.testing.io, .{});
    defer log.deinit();

    var service_instance: rss = undefined;
    _ = service_instance.init(a, std.testing.io, log);
    defer service_instance.deinit();

    const request = feedRequest{ .url = try a.dupe(u8, "not a url"), .age_limit_hours = 1, .item_limit = 1 };
    defer utilities.deinitStruct(request, a);

    try service_instance.pullFeed(request);

    var results = try service_instance.protectedCollection.get();
    defer {
        for (results.items) |item| {
            item.deinit();
        }
        results.deinit(a);
    }

    try std.testing.expectEqual(@as(usize, 1), results.items.len);
    try std.testing.expectEqual(@as(usize, 1), results.items[0].errors.items.len);
    try std.testing.expect(std.mem.indexOf(u8, results.items[0].errors.items[0], "error while pulling feed") != null);
}

test "processRequests returns error summaries for invalid requests" {
    const a = std.testing.allocator;

    const log = try logBuilder(a, std.testing.io, .{});
    defer log.deinit();

    var service_instance: rss = undefined;
    _ = service_instance.init(a, std.testing.io, log);
    defer service_instance.deinit();

    var request_items = [_]feedRequest{
        .{ .url = try a.dupe(u8, "not a url"), .age_limit_hours = 0, .item_limit = 1 },
    };
    defer for (request_items) |item| @constCast(&item).deinit(a);
    const requests = feedRequests{ .requests = request_items[0..] };

    var results = try service_instance.processRequests(requests);
    defer {
        for (results.items) |item| {
            item.deinit();
        }
        results.deinit(a);
    }

    try std.testing.expectEqual(@as(usize, 1), results.items.len);
    try std.testing.expectEqual(@as(usize, 1), results.items[0].errors.items.len);
}

test "toJson serializes summaries without stealing original ownership" {
    const a = std.testing.allocator;

    const log = try logBuilder(a, std.testing.io, .{});
    defer log.deinit();

    var service_instance: rss = undefined;
    _ = service_instance.init(a, std.testing.io, log);
    defer service_instance.deinit();

    var request = feedRequest{ .url = try a.dupe(u8, "https://example.com/feed"), .age_limit_hours = 24, .item_limit = 1 };
    defer request.deinit(a);

    const result = try a.create(feedResult);
    result.* = feedResult.init(a);
    defer {
        result.deinit();
        a.destroy(result);
    }

    result.url = try a.dupe(u8, request.url);
    result.body = try a.dupe(u8, "<rss />");
    result.request = request.clone(a);
    try result.errors.append(a, try a.dupe(u8, "failure"));

    const val = result.*;
    var results = [_]feedResult{val};
    const json = try service_instance.toJson(results[0..]);
    defer a.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "https://example.com/feed") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "failure") != null);
}

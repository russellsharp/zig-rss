const std = @import("std");
const service = @import("rss.zig").Service;
const structs = @import("rss.zig").Structs;
const utilities = @import("utilities");

const logBuilder = utilities.log.buildLogger;
const feedRequest = structs.FeedRequest;
const feedResult = structs.FeedResult;
const feedRequests = structs.FeedRequests;

test "buildRequest parses json request" {
    const a = std.testing.allocator;

    const log = try logBuilder(a, std.testing.io, .{});
    log.options.stdLog = false;
    defer log.deinit();

    var service_instance: service.rss = undefined;
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
    log.options.stdLog = false;
    defer log.deinit();

    var service_instance: service.rss = undefined;
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
    log.options.stdLog = false;
    defer log.deinit();

    var service_instance: service.rss = undefined;
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
    log.options.stdLog = false;
    defer log.deinit();

    var service_instance: service.rss = undefined;
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

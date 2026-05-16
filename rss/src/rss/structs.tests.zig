const std = @import("std");
const structs = @import("rss.zig").Structs;

const FeedEntry = structs.FeedEntry;
const FeedRequest = structs.FeedRequest;
const FeedResult = structs.FeedResult;
const Summary = structs.Summary;
const http = std.http;

test "Summary.fromFeedResult clones owned data" {
    const a = std.testing.allocator;

    const request = FeedRequest{ .url = try a.dupe(u8, "https://example.com/feed"), .age_limit_hours = 1, .item_limit = 1 };
    defer @constCast(&request).deinit(a);

    var result: FeedResult = .init(a);
    defer result.deinit();

    result.url = try a.dupe(u8, request.url);
    result.body = try a.dupe(u8, "<rss />");
    result.request = request.clone(a);

    const entry: FeedEntry = .init(a, "https://example.com/post", "summary", "Wed, 10 Dec 2025 23:06:28 +0000", "title", "2025-12-10T23:06:28Z");
    try result.entries.append(a, entry);
    try result.errors.append(a, try a.dupe(u8, "parse failed"));

    const summary = Summary.fromFeedResult(a, result);
    defer {
        summary.deinit(a);
        a.destroy(summary);
    }

    try std.testing.expect(summary.title.ptr != result.url.?.ptr);
    try std.testing.expectEqualStrings(result.url.?, summary.title);
    try std.testing.expectEqualStrings(result.entries.items[0].title, summary.entries.items[0].title);
    try std.testing.expectEqualStrings(result.errors.items[0], summary.errors.items[0]);
}

test "FeedResult.contentLength parses and defaults" {
    const a = std.testing.allocator;

    var request = FeedRequest{ .url = try a.dupe(u8, "https://example.com/feed"), .age_limit_hours = 1, .item_limit = 1 };
    defer request.deinit(a);

    var result: FeedResult = .init(a);
    defer result.deinit();
    result.url = try a.dupe(u8, request.url);
    result.body = try a.dupe(u8, "body");
    result.request = request.clone(a);
    result.headers = .empty;

    try std.testing.expectEqual(@as(usize, 0), try result.contentLength());

    const header = try a.create(http.Header);
    header.* = .{ .name = try a.dupe(u8, "Content-Length"), .value = try a.dupe(u8, "42") };
    try result.headers.?.append(a, header);

    try std.testing.expectEqual(@as(usize, 42), try result.contentLength());
}

const std = @import("std");
const structs = @import("rss.zig").Structs;

const FeedEntry = structs.FeedEntry;
const FeedRequest = structs.FeedRequest;
const FeedResult = structs.FeedResult;
const Summary = structs.Summary;
const http = std.http;
const string = @import("string").string(u8);

test "Summary.fromFeedResult clones owned data" {
    const a = std.testing.allocator;

    const request = FeedRequest{ .url = .init(a, "https://example.com/feed/1"), .age_limit_hours = 1, .item_limit = 1 };
    defer @constCast(&request).deinit();

    var result: FeedResult = .init(a);
    defer result.deinit();

    result.url = request.url.clone(a);
    result.body = string.init(a, "<rss />");
    result.request.deinit();
    result.request = request.clone(a);

    var link = string.init(a, "https://example.com/post");
    defer link.deinit();
    var subject = string.init(a, "summary");
    defer subject.deinit();
    var published = string.init(a, "Wed, 10 Dec 2025 23:06:28 +0000");
    defer published.deinit();
    var title = string.init(a, "title");
    defer title.deinit();
    var parsed_date = string.init(a, "2025-12-10T23:06:28Z");
    defer parsed_date.deinit();

    const entry: FeedEntry = .init(a, link, subject, published, title, parsed_date);
    try result.entries.append(a, entry);
    try result.errors.append(a, string.init(a, "parse failed"));

    const summary = Summary.fromFeedResult(a, result);
    defer {
        summary.deinit(a);
        a.destroy(summary);
    }

    try std.testing.expect(summary.title.str().ptr != result.url.?.str().ptr);
    try std.testing.expectEqualStrings(result.url.?.str(), summary.title.str());
    try std.testing.expectEqualStrings(result.entries.items[0].title.?.str(), summary.entries.items[0].title.?.str());
    try std.testing.expectEqualStrings(result.errors.items[0].str(), summary.errors.items[0].str());
}

test "FeedResult.contentLength parses and defaults" {
    const a = std.testing.allocator;

    var request = FeedRequest{ .url = string.init(a, "https://example.com/feed"), .age_limit_hours = 1, .item_limit = 1 };
    defer request.deinit();

    var result: FeedResult = .init(a);
    defer result.deinit();
    result.url = request.url.clone(a);
    result.body = string.init(a, "body");
    result.request.deinit();
    result.request = request.clone(a);
    result.headers = .empty;

    try std.testing.expectEqual(@as(usize, 0), try result.contentLength());

    const header = try a.create(http.Header);
    header.* = .{ .name = try a.dupe(u8, "Content-Length"), .value = try a.dupe(u8, "42") };
    try result.headers.?.append(a, header);

    try std.testing.expectEqual(@as(usize, 42), try result.contentLength());
}

const std = @import("std");
const cloneList = @import("utilities").cloneList;

const structs = @import("rss.zig").Structs;

test "copy ArrayList(feedResult)  098t0ah" {
    const a = std.heap.page_allocator;
    const T = structs.FeedResult;

    const tester: structs.FeedResult = .{
        .url = try a.dupe(u8, "hello"),
        .status = .ok,
        .request = .init(a),
        .entries = .empty,
        .body = try a.dupe(u8, "body"),
        .headers = null,
        .errors = .empty,
    };

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);
    defer for (list_0.items) |item| {
        item.deinit();
    };

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);
    defer for (list_1.items) |item| {
        item.deinit();
    };

    try list_0.append(a, tester);

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqualStrings("hello", list_0.items[0].url.?);
    try std.testing.expectEqualStrings("hello", list_1.items[0].url.?);
    try std.testing.expectEqualStrings("body", list_0.items[0].body.?);
    try std.testing.expectEqualStrings("body", list_1.items[0].body.?);
    try std.testing.expectEqual(@intFromEnum(std.http.Status.ok), @intFromEnum(list_0.items[0].status));
    try std.testing.expectEqual(@intFromEnum(std.http.Status.ok), @intFromEnum(list_1.items[0].status));

    try std.testing.expect(list_0.items[0].url.?.ptr != list_1.items[0].url.?.ptr);
    try std.testing.expect(list_0.items[0].body.?.ptr != list_1.items[0].body.?.ptr);
}

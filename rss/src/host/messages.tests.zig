const std = @import("std");
const host = @import("host.zig");

const ContentType = host.messages.ContentType;

test "ContentType to_string" {
    try std.testing.expectEqualStrings("text/plain", ContentType.to_string(&ContentType.PlainText));
    try std.testing.expectEqualStrings("application/json", ContentType.to_string(&ContentType.Json));
    try std.testing.expectEqualStrings("unknown,", ContentType.to_string(&ContentType.Unknown));
}

test "ContentType from_string plain text" {
    const ct = try ContentType.from_string("text/plain");
    try std.testing.expectEqual(ContentType.PlainText, ct);
}

test "ContentType from_string json" {
    const ct = try ContentType.from_string("application/json");
    try std.testing.expectEqual(ContentType.Json, ct);
}

test "ContentType from_string unknown" {
    const ct = try ContentType.from_string("text/html");
    try std.testing.expectEqual(ContentType.Unknown, ct);
}

test "ContentType from_string strips trailing CRLF" {
    const ct = try ContentType.from_string("text/plain\r\nother");
    try std.testing.expectEqual(ContentType.PlainText, ct);
}

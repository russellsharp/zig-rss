const std = @import("std");
const Io = std.Io;
const http = std.http;
const builtin = @import("builtin");

pub fn find_next(haystack: []const u8, needle: u8, start: usize, end: usize) usize {
    for (haystack[start..end], start..) |c, i| {
        if (c == needle) {
            return i;
        }
    }
    return haystack.len;
}

// Intentionally minimal parser: splits on '=' and '&' with no URL decoding,
// repeated key, or empty value handling. Suitable for simple known-format URLs.
pub fn get_query_parameters(url: []const u8, params: anytype) !void {
    var start = find_next(url, '?', 0, url.len) + 1;

    if (start >= url.len - 1) return;

    var end = url.len - 1;
    while (end < url.len) {
        //find name
        end = find_next(url, '=', start, url.len - 1);
        const name = url[start..end];

        //find value
        start = end + 1;
        end = find_next(url, '&', start, url.len);
        const value = url[start..end];

        start = end + 1;

        try params.put(name, @constCast(value));
    }
}

test "parsing parameters" {
    const a = std.testing.allocator;
    var paramMap = std.StringHashMap([]u8).init(a);
    defer paramMap.deinit();

    const url: []const u8 = "/hello/?arg2=2&arg1=1&arg3=three&.";
    const trimmed_url = std.mem.trim(u8, url, " &=\\.\n");

    try get_query_parameters(trimmed_url, &paramMap);

    const one = paramMap.get("arg1").?;
    const two = paramMap.get("arg2").?;
    const three = paramMap.get("arg3").?;

    try std.testing.expectEqualSlices(u8, "1", one);
    try std.testing.expectEqualSlices(u8, "2", two);
    try std.testing.expectEqualSlices(u8, "three", three);
}

const std = @import("std");
const host = @import("host.zig");

test "parsing parameters" {
    const a = std.testing.allocator;
    var paramMap = std.StringHashMap([]u8).init(a);
    defer paramMap.deinit();

    const url: []const u8 = "/hello/?arg2=2&arg1=1&arg3=three&.";
    const trimmed_url = std.mem.trim(u8, url, " &=\\.\n");

    try host.utilities.get_query_parameters(trimmed_url, &paramMap);

    const one = paramMap.get("arg1").?;
    const two = paramMap.get("arg2").?;
    const three = paramMap.get("arg3").?;

    try std.testing.expectEqualSlices(u8, "1", one);
    try std.testing.expectEqualSlices(u8, "2", two);
    try std.testing.expectEqualSlices(u8, "three", three);
}

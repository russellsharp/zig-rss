const std = @import("std");
const utilities = @import("utilities.zig");

const log = utilities.log;

test "logger" {
    const io = std.testing.io;

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var logger = try log.buildLogger(a, io, .{});
    defer logger.deinit();

    logger.info("hello", @typeName(@This()));
    try std.Io.sleep(io, .fromMilliseconds(1000), .real);
    logger.info("asdf", @typeName(@This()));
    try std.Io.sleep(io, .fromMilliseconds(1000), .real);
    logger.info("waaa", @typeName(@This()));
}

test "logger load test" {
    const io = std.testing.io;

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var logger = try log.buildLogger(a, io, .{});
    defer logger.deinit();

    const wait_time_ms = 1;
    for (0..150) |i| {
        try logger.format(.Debug, "{d}", .{i}, @typeName(@This()));
        try std.Io.sleep(io, .fromMilliseconds(wait_time_ms), .real);
    }
}

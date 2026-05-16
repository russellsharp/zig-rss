const std = @import("std");
const Thread = std.Thread;
const utilities = @import("utilities.zig");

const tasks = utilities.tasks;

var test_counter: u32 = 0;

fn thread_fn() !void {
    test_counter += 1;
}

test "a thread" {
    var coll = try tasks.collection.init(std.testing.allocator);
    defer coll.deinit();

    const counter = test_counter;
    const thread1 = try Thread.spawn(.{}, thread_fn, .{});
    const thread2 = try Thread.spawn(.{}, thread_fn, .{});

    try coll.add(thread1);
    try coll.add(thread2);
    try coll.wait(false);

    try std.testing.expectEqual(test_counter, counter + 2);
}

test "cancel a thread" {
    var coll = try tasks.collection.init(std.testing.allocator);
    defer coll.deinit();

    const thread = try Thread.spawn(.{}, thread_fn, .{});

    try coll.add(thread);
    try coll.wait(true);
}

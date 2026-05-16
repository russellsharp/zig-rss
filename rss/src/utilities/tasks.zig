const std = @import("std");
const Io = std.Io;
const ArrayList = @import("std").ArrayList;
const Thread = @import("std").Thread;

const tasks = @This();

pub const collection = struct {
    const Self = @This();

    collection: ?std.ArrayList(std.Thread) = .empty,

    allocator: ?std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !collection {
        return collection{
            .allocator = allocator,
            .collection = .empty,
        };
    }

    pub fn deinit(s: *Self) void {
        s.collection.?.deinit(s.allocator.?);
    }

    pub fn add(s: *Self, new_thread: std.Thread) !void {
        try s.collection.?.append(s.allocator.?, new_thread);
    }

    pub fn wait(s: *Self, cancel: bool) !void {
        if (cancel) {
            // Detach lets work continue in background when shutdown should not
            // block on long-running worker threads.
            for (s.collection.?.items) |task| task.detach();
        } else {
            // Join provides deterministic completion for tests and clean exits.
            for (s.collection.?.items) |task| task.join();
        }
    }
};

var test_counter: u32 = 0;

fn thread_fn() !void {
    test_counter += 1;
}

test "a thread" {
    var coll = try collection.init(std.testing.allocator);
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
    var coll = try collection.init(std.testing.allocator);
    defer coll.deinit();

    const thread = try Thread.spawn(.{}, thread_fn, .{});

    try coll.add(thread);
    try coll.wait(true);
}

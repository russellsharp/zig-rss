const std = @import("std");
const utilities = @import("utilities.zig");

const protectedCollection = utilities.protectedCollection;

test "protectedCollection clear removes items" {
    var coll: protectedCollection(u32) = undefined;
    coll.init(std.testing.allocator, std.testing.io);
    defer coll.clear() catch unreachable;

    try coll.add(1);
    try coll.add(2);

    var items_0 = try coll.get();
    try std.testing.expectEqual(@as(usize, 2), items_0.items.len);
    defer items_0.deinit(std.testing.allocator);

    try coll.clear();

    var items_1 = try coll.get();
    defer items_1.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), items_1.items.len);
}

test "protectedCollection add and get round-trip" {
    var coll: protectedCollection(u32) = undefined;
    coll.init(std.testing.allocator, std.testing.io);
    defer coll.clear() catch unreachable;

    try coll.add(42);

    var items = try coll.get();
    defer items.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), items.items.len);
    try std.testing.expectEqual(@as(u32, 42), items.items[0]);
}

test "protectedCollection get returns independent copy" {
    var coll: protectedCollection(u32) = undefined;
    coll.init(std.testing.allocator, std.testing.io);
    defer coll.clear() catch unreachable;

    try coll.add(7);

    var first = try coll.get();
    defer first.deinit(std.testing.allocator);
    try first.append(std.testing.allocator, 99);

    var second = try coll.get();
    defer second.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), second.items.len);
    try std.testing.expectEqual(@as(u32, 7), second.items[0]);
}

test "protectedCollection add multiple items preserves order" {
    var coll: protectedCollection(u32) = undefined;
    coll.init(std.testing.allocator, std.testing.io);
    defer coll.clear() catch unreachable;

    try coll.add(1);
    try coll.add(2);
    try coll.add(3);

    var items = try coll.get();
    defer items.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), items.items.len);
    try std.testing.expectEqual(@as(u32, 1), items.items[0]);
    try std.testing.expectEqual(@as(u32, 2), items.items[1]);
    try std.testing.expectEqual(@as(u32, 3), items.items[2]);
}

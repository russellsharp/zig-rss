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

const std = @import("std");
const cloneList = @import("clone.zig").cloneList;

pub fn protectedCollection(T: type) type {
    return struct {
        const Self = @This();
        collection: std.ArrayList(T) = .empty,
        lock: std.Io.Mutex = .init,
        a: std.mem.Allocator,
        io: std.Io,

        pub fn init(s: *Self, a: std.mem.Allocator, io: std.Io) void {
            s.collection = .empty;
            s.lock = .init;
            s.a = a;
            s.io = io;
        }

        pub fn add(s: *Self, item: T) !void {
            try s.lock.lock(s.io);
            defer s.lock.unlock(s.io);
            switch (@typeInfo(T)) {
                .pointer => {
                    var var_ptr = &(std.meta.Child(T).clone(item, s.a));
                    _ = &var_ptr;
                    s.collection.append(s.a, @constCast(var_ptr)) catch unreachable;
                },
                .@"struct" => {
                    const copy = item.clone(s.a);
                    s.collection.append(s.a, copy) catch unreachable;
                },
                else => s.collection.append(s.a, item) catch unreachable,
            }
        }

        // Returns a cloned snapshot of the collection so callers can iterate
        // without holding the mutex or racing with concurrent writers.
        pub fn get(s: *Self) !std.ArrayList(T) {
            try s.lock.lock(s.io);
            defer s.lock.unlock(s.io);
            const copy = cloneList(s.a, T, s.collection);
            return copy;
        }

        pub fn clear(s: *Self) !void {
            try s.lock.lock(s.io);
            defer s.lock.unlock(s.io);
            for (s.collection.items) |item| {
                if (std.meta.hasMethod(T, "deinit")) {
                    item.deinit();
                }
            }
            s.collection.clearAndFree(s.a);
        }
    };
}

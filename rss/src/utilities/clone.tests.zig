const std = @import("std");
const http = std.http;
const utilities = @import("utilities");

const clone = @import("clone.zig");
const cloneList = clone.cloneList;
const deinitList = clone.deinitList;
const deinitStruct = clone.deinitStruct;
const cloneStruct = clone.cloneStruct;
const isArrayList = clone.isArrayList;

const innerStruct = struct {
    const Self = @This();
    innerSlice: []const u8 = "",
    innerList: std.ArrayList(u32) = .empty,

    pub fn deinit(s: *const Self, a: std.mem.Allocator) void {
        a.free(s.innerSlice);

        var list_ptr = @constCast(&s.innerList);
        _ = &list_ptr;
        list_ptr.deinit(a);
    }

    pub fn equals(s: *Self, b: Self) bool {
        var matched = std.mem.eql(u8, s.innerSlice, b.innerSlice) and
            s.innerList.items.len == b.innerList.items.len;

        matched = matched and for (0..s.innerList.items.len) |i| {
            if (s.innerList.items[i] != b.innerList.items[i]) {
                break false;
            }
        } else true;

        return matched;
    }
};

const testStruct = struct {
    const Self = @This();
    slice: []const u8,
    integer: u32,
    float: f32,
    inner: innerStruct = .{},

    pub fn init(a: std.mem.Allocator, slice: []const u8, integer: u32, float: f32) Self {
        return Self{
            .slice = a.dupe(u8, slice) catch unreachable,
            .integer = integer,
            .float = float,
            .inner = .{},
        };
    }

    pub fn clone(s: *const Self, a: std.mem.Allocator) !Self {
        return Self{
            .slice = try a.dupe(u8, s.slice),
            .integer = s.integer,
            .float = s.float,
            .inner = try cloneStruct(a, innerStruct, s.inner),
        };
    }

    pub fn deinit(s: *const Self, a: std.mem.Allocator) void {
        a.free(s.slice);
        s.inner.deinit(a);
    }

    pub fn equals(s: *Self, other: Self) bool {
        return std.mem.eql(u8, s.slice, other.slice) and
            s.integer == other.integer and
            s.float == other.float and
            s.inner.equals(other.inner);
    }
};

fn innerTwo(T: type) type {
    return struct {
        const Self = @This();
        inner: T,

        pub fn deinit(s: *Self, a: std.mem.Allocator) void {
            if (isArrayList(T))
                deinitList(s.inner, a);
        }
    };
}

fn innerOne(T: type) type {
    return struct {
        const Self = @This();
        innerList: std.ArrayList(T) = .empty,

        pub fn deinit(s: *Self, a: std.mem.Allocator) void {
            deinitList(s.innerList, a);
        }
    };
}

fn complexStruct(C: type) type {
    return struct {
        const Self = @This();
        innerList: std.ArrayList(C) = .empty,

        pub fn deinit(s: *Self, a: std.mem.Allocator) void {
            deinitList(s.innerList, a);
        }
    };
}

test "copy ArrayList(*struct)" {
    const a = std.testing.allocator;
    const T = *testStruct;

    var tester: *testStruct = try a.create(testStruct);
    _ = &tester;
    tester.* = .init(a, "hello", 34, 34.28);

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);
    defer for (list_0.items) |item| {
        item.deinit(a);
        a.destroy(item);
    };

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);
    defer for (list_1.items) |item| {
        item.deinit(a);
        a.destroy(item);
    };

    try list_0.append(a, tester);

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqualStrings("hello", list_0.items[0].slice);
    try std.testing.expectEqualStrings("hello", list_1.items[0].slice);
    try std.testing.expectEqual(@as(usize, 1), list_0.items.len);
    try std.testing.expectEqual(@as(usize, 1), list_1.items.len);
    try std.testing.expectEqual(@as(u32, 34), list_0.items[0].integer);
    try std.testing.expectEqual(@as(u32, 34), list_1.items[0].integer);

    try std.testing.expect(list_0.items[0].slice.ptr != list_1.items[0].slice.ptr);
    list_1.items[0].integer = 99;
    try std.testing.expectEqual(@as(u32, 34), list_0.items[0].integer);
    try std.testing.expectEqual(@as(u32, 99), list_1.items[0].integer);
}

test "copy ArrayList(struct)" {
    const a = std.testing.allocator;
    const T = testStruct;

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);
    defer for (list_0.items) |item| {
        deinitStruct(item, a);
    };

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);
    defer for (list_1.items) |item| {
        deinitStruct(item, a);
    };

    const tester: testStruct = .init(a, "hello", 34, 34.28);
    try list_0.append(a, tester);

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqual(@as(usize, 1), list_0.items.len);
    try std.testing.expectEqual(@as(usize, 1), list_1.items.len);
    try std.testing.expectEqual(@as(u32, 34), list_1.items[0].integer);

    try std.testing.expect(list_0.items[0].slice.ptr != list_1.items[0].slice.ptr);
    list_1.items[0].integer = 99;
    try std.testing.expectEqual(@as(u32, 34), list_0.items[0].integer);
    try std.testing.expectEqual(@as(u32, 99), list_1.items[0].integer);
}

test "copy ArrayList(slice(const u8))" {
    const a = std.testing.allocator;
    const T = []const u8;
    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);
    defer for (list_0.items) |item| a.free(item);

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);
    defer for (list_1.items) |item| a.free(item);

    try list_0.append(a, try a.dupe(u8, "hello"));

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqual(@as(usize, 1), list_1.items.len);
    try std.testing.expect(list_0.items[0].ptr != list_1.items[0].ptr);
    try std.testing.expectEqualStrings(list_0.items[0], list_1.items[0]);
}

test "copy ArrayList(u32)" {
    const T: type = u32;
    const a = std.testing.allocator;
    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);

    try list_0.append(a, 350);

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqual(@as(usize, 1), list_1.items.len);
}

test "copy ArrayList(*u32)" {
    const T: type = *u32;
    const a = std.testing.allocator;

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);
    defer for (list_0.items) |item| a.destroy(item);

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);
    defer for (list_1.items) |item| a.destroy(item);

    const new_thang: T = try a.create(@typeInfo(T).pointer.child);
    new_thang.* = 350;

    try list_0.append(a, new_thang);

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqual(@as(@typeInfo(T).pointer.child, 350), list_1.items[0].*);
    try std.testing.expectEqual(@as(usize, 1), list_1.items.len);
}

test "copy ArrayList(*f32)" {
    const T: type = *f32;
    const a = std.testing.allocator;

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);
    defer for (list_0.items) |item| a.destroy(item);

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);
    defer for (list_1.items) |item| a.destroy(item);

    const new_thang: T = try a.create(@typeInfo(T).pointer.child);
    new_thang.* = 350.2984;

    try list_0.append(a, new_thang);

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqual(@as(@typeInfo(T).pointer.child, 350.2984), list_1.items[0].*);
    try std.testing.expectEqual(@as(usize, 1), list_1.items.len);
}

test "copy ArrayList(f32)" {
    const T: type = f32;
    const a = std.testing.allocator;
    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);

    try list_0.append(a, 350.24580);

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqual(@as(usize, 1), list_1.items.len);
}

test "copy ArrayList(bool)" {
    const T: type = bool;
    const a = std.testing.allocator;
    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);

    try list_0.append(a, true);
    try list_0.append(a, false);
    try list_0.append(a, true);

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqual(@as(usize, 3), list_0.items.len);
    try std.testing.expect(!list_0.items[1]);
    try std.testing.expect(list_1.items[0]);
    try std.testing.expect(!list_1.items[1]);
    try std.testing.expect(list_1.items[2]);
}

test "copy ArrayList(?u32)" {
    const T: type = ?u32;
    const a = std.testing.allocator;
    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);

    try list_0.append(a, 45);
    try list_0.append(a, null);
    try list_0.append(a, 3);

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqual(@as(usize, 3), list_0.items.len);
    try std.testing.expectEqual(null, list_0.items[1]);
    try std.testing.expectEqual(45, list_1.items[0]);
    try std.testing.expectEqual(null, list_1.items[1]);
    try std.testing.expectEqual(3, list_1.items[2]);
}

test "copy ArrayList(array(u32))" {
    const C: type = u32;
    const T: type = []C;
    const a = std.testing.allocator;

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);
    defer for (list_0.items) |item| a.free(item);

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);
    defer for (list_1.items) |item| a.free(item);

    const one = [_]C{ 4, 2, 1 };
    const two = [_]C{ 20, 1, 9 };
    const three = [_]C{2};

    const one_slice = one[0..];
    const two_slice = two[0..];
    const three_slice = three[0..];

    try list_0.append(a, try a.dupe(C, one_slice));
    try list_0.append(a, try a.dupe(C, two_slice));
    try list_0.append(a, try a.dupe(C, three_slice));

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqual(@as(usize, 3), list_0.items.len);
    try std.testing.expectEqual(@as(usize, 3), list_1.items.len);
    try std.testing.expect(std.mem.eql(C, one[0..], list_0.items[0]));
    try std.testing.expect(std.mem.eql(C, one[0..], list_1.items[0]));
    try std.testing.expect(std.mem.eql(C, two[0..], list_1.items[1]));
    try std.testing.expect(std.mem.eql(C, three[0..], list_1.items[2]));
}

test "copy ArrayList(fixed array(u32))" {
    const C: type = u32;
    const T: type = [3]C;
    const a = std.testing.allocator;

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);

    const one = [_]C{ 4, 2, 1 };
    const two = [_]C{ 20, 1, 9 };
    const three = [_]C{ 2, 4, 0 };

    try list_0.append(a, one);
    try list_0.append(a, two);
    try list_0.append(a, three);

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqual(@as(usize, 3), list_0.items.len);
    try std.testing.expectEqual(@as(usize, 3), list_1.items.len);

    for (0..list_0.items.len) |i| {
        try std.testing.expectEqual(list_0.items[i], list_1.items[i]);
    }
}

test "copy ArrayList(slice([]struct))" {
    const C: type = testStruct;
    const T: type = []C;
    const a = std.testing.allocator;

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);
    defer for (list_0.items) |item| {
        for (0..item.len) |i| {
            deinitStruct(item[i], a);
        }
        a.free(item);
    };

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);
    defer for (list_1.items) |item| {
        for (0..item.len) |i| {
            deinitStruct(item[i], a);
        }
        a.free(item);
    };

    const one: testStruct = .init(a, "hello", 2, 9.1);
    const two: testStruct = .init(a, "heyo", 2, 4);
    const three: testStruct = .init(a, "alright", 9, 2);

    var array_0: std.ArrayList(C) = .empty;
    defer array_0.deinit(a);
    try array_0.append(a, one);
    try array_0.append(a, two);
    try array_0.append(a, three);

    const owned = try array_0.toOwnedSlice(a);
    try list_0.append(a, owned);

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqual(@as(usize, 1), list_0.items.len);
    try std.testing.expectEqual(@as(usize, 1), list_1.items.len);

    for (0..list_0.items.len) |i| {
        try std.testing.expect(!std.meta.eql(list_0.items[i], list_1.items[i]));
        for (0..list_0.items[i].len) |j| {
            try std.testing.expect(list_0.items[i][j].equals(list_1.items[i][j]));
        }
    }
}

test "copy ArrayList(fixed array([]struct))" {
    const C: type = testStruct;
    const T: type = [3]C;
    const a = std.testing.allocator;

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);
    defer for (list_0.items) |item| {
        for (0..item.len) |i| {
            deinitStruct(item[i], a);
        }
    };

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);
    defer for (list_1.items) |item| {
        for (0..item.len) |i| {
            deinitStruct(item[i], a);
        }
    };

    const one: testStruct = .init(a, "hello", 2, 9.1);
    const two: testStruct = .init(a, "heyo", 2, 4);
    const three: testStruct = .init(a, "alright", 9, 2);

    const fixed_array: [3]testStruct = [_]testStruct{ one, two, three };

    try list_0.append(a, fixed_array);

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqual(@as(usize, 1), list_0.items.len);
    try std.testing.expectEqual(@as(usize, 1), list_1.items.len);

    for (0..list_0.items.len) |i| {
        try std.testing.expect(!std.meta.eql(list_0.items[i], list_1.items[i]));
        for (0..list_0.items[i].len) |j| {
            try std.testing.expect(list_0.items[i][j].equals(list_1.items[i][j]));
        }
    }
}

test "copy ArrayList(empty) returns empty clone" {
    const a = std.testing.allocator;

    var int_src: std.ArrayList(u32) = .empty;
    defer int_src.deinit(a);
    var int_copy = cloneList(a, u32, int_src);
    defer int_copy.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), int_copy.items.len);

    var struct_src: std.ArrayList(testStruct) = .empty;
    defer struct_src.deinit(a);
    var struct_copy = cloneList(a, testStruct, struct_src);
    defer struct_copy.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), struct_copy.items.len);

    var slice_src: std.ArrayList([]const u8) = .empty;
    defer slice_src.deinit(a);
    var slice_copy = cloneList(a, []const u8, slice_src);
    defer slice_copy.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), slice_copy.items.len);
}

test "copy ArrayList(u64) preserves values and order" {
    const T = u64;
    const a = std.testing.allocator;

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);

    try list_0.append(a, 100);
    try list_0.append(a, 200);
    try list_0.append(a, 300);

    var list_1 = cloneList(a, T, list_0);
    defer list_1.deinit(a);

    try std.testing.expectEqual(@as(usize, 3), list_1.items.len);
    try std.testing.expectEqual(@as(T, 100), list_1.items[0]);
    try std.testing.expectEqual(@as(T, 200), list_1.items[1]);
    try std.testing.expectEqual(@as(T, 300), list_1.items[2]);
}

test "copy ArrayList([]u8) deep-copies mutable slices" {
    const T = []u8;
    const a = std.testing.allocator;

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);
    defer for (list_0.items) |item| a.free(item);

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);
    defer for (list_1.items) |item| a.free(item);

    try list_0.append(a, try a.dupe(u8, "hello"));

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqual(@as(usize, 1), list_1.items.len);
    try std.testing.expectEqualStrings(list_0.items[0], list_1.items[0]);
    try std.testing.expect(list_0.items[0].ptr != list_1.items[0].ptr);
    list_1.items[0][0] = 'H';
    try std.testing.expect(list_0.items[0][0] == 'h');
}

test "copy ArrayList([4]u8) copies fixed-size byte arrays" {
    const T = [4]u8;
    const a = std.testing.allocator;

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);

    const arr: T = .{ 1, 2, 3, 4 };
    try list_0.append(a, arr);

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqual(@as(usize, 1), list_1.items.len);
    try std.testing.expectEqualSlices(u8, &arr, &list_1.items[0]);
}

test "copy ArrayList(duplicate source elements) keeps duplicates intact" {
    const T = u32;
    const a = std.testing.allocator;

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);

    try list_0.append(a, 42);
    try list_0.append(a, 42);
    try list_0.append(a, 42);

    var list_1 = cloneList(a, T, list_0);
    defer list_1.deinit(a);

    try std.testing.expectEqual(@as(usize, 3), list_1.items.len);
    try std.testing.expectEqual(@as(T, 42), list_1.items[0]);
    try std.testing.expectEqual(@as(T, 42), list_1.items[1]);
    try std.testing.expectEqual(@as(T, 42), list_1.items[2]);
}

test "copy ArrayList(source modified after clone) clone remains independent" {
    const T = u32;
    const a = std.testing.allocator;

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);

    try list_0.append(a, 10);
    try list_0.append(a, 20);

    var list_1 = cloneList(a, T, list_0);
    defer list_1.deinit(a);

    list_0.items[0] = 999;
    try list_0.append(a, 30);

    try std.testing.expectEqual(@as(usize, 2), list_1.items.len);
    try std.testing.expectEqual(@as(T, 10), list_1.items[0]);
    try std.testing.expectEqual(@as(T, 20), list_1.items[1]);
}

test "copy ArrayList(large input) all elements preserved" {
    const T = u32;
    const count = 10_000;
    const a = std.testing.allocator;

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);

    for (0..count) |i| {
        try list_0.append(a, @intCast(i));
    }

    var list_1 = cloneList(a, T, list_0);
    defer list_1.deinit(a);

    try std.testing.expectEqual(@as(usize, count), list_1.items.len);
    for (0..count) |i| {
        try std.testing.expectEqual(@as(T, @intCast(i)), list_1.items[i]);
    }
}

test "copy ArrayList([]const u8) deep-copies slice contents, source mutation independent" {
    const T = []const u8;
    const a = std.testing.allocator;

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);
    defer for (list_0.items) |item| a.free(item);

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);
    defer for (list_1.items) |item| a.free(item);

    try list_0.append(a, try a.dupe(u8, "original"));

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqualStrings("original", list_1.items[0]);
    try std.testing.expect(list_0.items[0].ptr != list_1.items[0].ptr);
}

test "copy ArrayList(struct) deep-copies owned fields, source mutation independent" {
    const T = testStruct;
    const a = std.testing.allocator;

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);
    defer for (list_0.items) |item| deinitStruct(item, a);

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);
    defer for (list_1.items) |item| deinitStruct(item, a);

    try list_0.append(a, .init(a, "world", 7, 3.14));

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqualStrings("world", list_1.items[0].slice);
    try std.testing.expectEqual(@as(u32, 7), list_1.items[0].integer);
    try std.testing.expect(list_0.items[0].slice.ptr != list_1.items[0].slice.ptr);
    list_0.items[0].integer = 999;
    try std.testing.expectEqual(@as(u32, 7), list_1.items[0].integer);
}

test "isMyArrayList matches aligned array list types" {
    try std.testing.expect(isArrayList(std.ArrayList(u32)));
    try std.testing.expect(isArrayList(std.ArrayListAligned(u32, null)));
    try std.testing.expect(isArrayList(std.ArrayListAlignedUnmanaged(u32, null)));
    try std.testing.expect(!isArrayList(struct {
        items: []u32,
        capacity: usize,
    }));
}

const deinitableEntry = struct {
    value: []const u8,

    pub fn init(a: std.mem.Allocator, value: []const u8) @This() {
        return .{ .value = a.dupe(u8, value) catch unreachable };
    }

    pub fn deinit(s: @This(), a: std.mem.Allocator) void {
        a.free(s.value);
    }
};

test "isArrayList and deinitList accept pointer array list of deinitable structs" {
    const a = std.testing.allocator;
    const List = std.ArrayList(deinitableEntry);

    var entries: List = .empty;
    try entries.append(a, deinitableEntry.init(a, "one"));

    const entries_ptr = &entries;

    try std.testing.expect(isArrayList(List));
    try std.testing.expect(isArrayList(@TypeOf(entries_ptr)));

    deinitList(entries_ptr, a);
}

test "clone struct" {
    const a = std.testing.allocator;
    const first = testStruct{ .integer = 384, .float = 23.42, .slice = try a.dupe(u8, "what"), .inner = .{ .innerSlice = try a.dupe(u8, "what") } };
    defer first.deinit(a);
    const second = try cloneStruct(a, testStruct, first);
    defer second.deinit(a);

    try std.testing.expect(std.mem.eql(u8, first.slice, second.slice));
    try std.testing.expect(&first != &second);
}

test "clone *struct" {
    const a = std.testing.allocator;
    const C = testStruct;
    const T = *C;
    var first = try a.create(C);
    first.* = C{ .integer = 384, .float = 23.42, .slice = try a.dupe(u8, "what"), .inner = .{ .innerSlice = try a.dupe(u8, "what"), .innerList = std.ArrayList(u32).empty } };
    defer a.destroy(first);
    defer first.deinit(a);
    var second = try cloneStruct(a, T, first);
    defer a.destroy(second);
    defer second.deinit(a);

    try std.testing.expect(std.mem.eql(u8, first.slice, second.slice));
    try std.testing.expect(first != second);
}

test "clone *Header" {
    const a = std.testing.allocator;

    var first = try a.create(http.Header);
    _ = &first;
    first.* = http.Header{ .name = try a.dupe(u8, "chimi"), .value = try a.dupe(u8, "changa") };
    defer a.destroy(first);
    defer a.free(first.name);
    defer a.free(first.value);

    var second = try cloneStruct(a, @TypeOf(first), first);
    _ = &second;
    defer a.destroy(second);
    defer a.free(second.name);
    defer a.free(second.value);

    try std.testing.expect(std.mem.eql(u8, first.name, second.name));
    try std.testing.expect(first != second);
}

test "copy ArrayList(*http.Header)" {
    const a = std.testing.allocator;
    const T = *http.Header;

    const C = std.meta.Child(T);

    var tester: T = try a.create(C);
    _ = &tester;
    tester.* = .{ .name = try a.dupe(u8, "chimi"), .value = try a.dupe(u8, "changa") };

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);
    defer for (list_0.items) |item| {
        a.free(item.name);
        a.free(item.value);
        a.destroy(item);
    };

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);
    defer for (list_1.items) |item| {
        a.free(item.name);
        a.free(item.value);
        a.destroy(item);
    };

    try list_0.append(a, tester);

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqualStrings("chimi", list_0.items[0].name);
    try std.testing.expectEqualStrings("chimi", list_1.items[0].name);
    try std.testing.expectEqual(@as(usize, 1), list_0.items.len);
    try std.testing.expectEqual(@as(usize, 1), list_1.items.len);
    try std.testing.expectEqualStrings("changa", list_0.items[0].value);
    try std.testing.expectEqualStrings("changa", list_1.items[0].value);

    try std.testing.expect(list_0.items[0].name.ptr != list_1.items[0].name.ptr);
    a.free(list_1.items[0].name);
    list_1.items[0].name = try a.dupe(u8, "burrito");
    try std.testing.expect(std.mem.eql(u8, "chimi", list_0.items[0].name));
    try std.testing.expect(std.mem.eql(u8, "burrito", list_1.items[0].name));
}

test "copy ArrayList(minStruct)" {
    const a = std.testing.allocator;
    const U = innerTwo(u8);
    const T = innerOne(U);

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);
    defer for (list_0.items) |item| {
        deinitStruct(item, a);
    };

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);
    defer for (list_1.items) |item| {
        deinitStruct(item, a);
    };

    const inner_struct: U = .{ .inner = 8 };

    var tester: T = .{ .innerList = std.ArrayList(U).empty };
    try tester.innerList.append(a, inner_struct);
    try list_0.append(a, tester);

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqual(@as(usize, 1), list_0.items.len);
    try std.testing.expectEqual(@as(usize, 1), list_1.items.len);
}

test "copy ArrayList(struct with list of struct)" {
    const a = std.testing.allocator;
    const W = std.ArrayList(u8);
    const V = innerTwo(W);
    const U = innerOne(V);
    const T = complexStruct(U);

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);
    defer for (list_0.items) |item| {
        deinitStruct(item, a);
    };

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);
    defer for (list_1.items) |item| {
        deinitStruct(item, a);
    };

    var inmostList: W = .empty;
    try inmostList.append(a, 82);

    const m2 = V{ .inner = inmostList };
    var m2List: std.ArrayList(V) = .empty;
    try m2List.append(a, m2);

    const m1 = U{ .innerList = m2List };
    var m1List = std.ArrayList(U).empty;
    try m1List.append(a, m1);

    const tester = T{ .innerList = m1List };
    try list_0.append(a, tester);

    list_1 = cloneList(a, T, list_0);

    try std.testing.expectEqual(@as(usize, 1), list_0.items.len);
    try std.testing.expectEqual(@as(usize, 1), list_1.items.len);
    try std.testing.expectEqual(list_0.items[0].innerList.items[0].innerList.items[0].inner.items.len, list_1.items[0].innerList.items[0].innerList.items[0].inner.items.len);
    try std.testing.expect(list_0.items[0].innerList.items[0].innerList.items[0].inner.items.ptr != list_1.items[0].innerList.items[0].innerList.items[0].inner.items.ptr);
}

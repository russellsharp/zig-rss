const std = @import("std");
const http = std.http;

pub fn cloneList(a: std.mem.Allocator, T: type, source: std.ArrayList(T)) std.ArrayList(T) {
    var copy: std.ArrayList(T) = .empty;
    for (source.items) |item| {
        copy.append(a, cloneElement(a, T, item) catch unreachable) catch unreachable;
    }
    return copy;
}

pub fn cloneStruct(a: std.mem.Allocator, T: type, s: T) !T {
    const info = @typeInfo(T);
    const copy_type: type = switch (info) {
        .pointer => info.pointer.child,
        else => T,
    };

    const copy = try a.create(copy_type);
    errdefer a.destroy(copy);

    const copy_value = switch (@typeInfo(copy_type)) {
        .@"struct" => blk: {
            inline for (std.meta.fields(copy_type)) |field| {
                @field(copy, field.name) = try cloneElement(a, field.type, @field(switch (info) {
                    .pointer => s.*,
                    else => s,
                }, field.name));
            }
            break :blk copy.*;
        },
        else => try cloneElement(a, copy_type, switch (info) {
            .pointer => s.*,
            else => s,
        }),
    };

    if (info == .pointer) {
        return copy;
    }

    defer a.destroy(copy);
    return copy_value;
}

pub inline fn isArrayList(T: type) bool {
    const input_type = switch (@typeInfo(T)) {
        .pointer => |ptr| ptr.child,
        else => T,
    };

    if (@typeInfo(input_type) != .@"struct") return false;
    if (!@hasDecl(input_type, "Slice") or !@hasField(input_type, "items") or !@hasField(input_type, "capacity")) return false;

    const Slice = input_type.Slice;
    const slice_info = switch (@typeInfo(Slice)) {
        .pointer => |info| info,
        else => return false,
    };

    if (slice_info.size != .slice) return false;
    if (@TypeOf(@field(@as(input_type, undefined), "items")) != Slice) return false;

    // Match std array list instantiations (including managed variants) without
    // depending on a single concrete type alias.
    return std.mem.indexOf(u8, @typeName(input_type), "array_list") != null;
}

fn cloneElement(a: std.mem.Allocator, T: type, item: T) !T {
    if (std.meta.hasFn(T, "clone")) {
        // ArrayList.clone keeps shared backing semantics for nested data; recurse
        // element-wise instead so callers receive a true deep copy.
        if (comptime isArrayList(T)) {
            const ItemsType = @TypeOf(@as(T, undefined).items);
            const items_info = @typeInfo(ItemsType);
            const Child = items_info.pointer.child;
            return cloneList(a, Child, item);
        }
        return item.clone(a);
    }

    return switch (@typeInfo(T)) {
        .bool, .int, .float, .comptime_float, .comptime_int, .enum_literal, .@"enum" => item,
        .optional => |opt| blk: {
            if (item) |value| {
                break :blk @as(T, try cloneElement(a, opt.child, value));
            }
            break :blk null;
        },
        .pointer => |ptr| blk: {
            if (ptr.size == .slice) {
                const child = ptr.child;
                if (child == u8) {
                    break :blk try a.dupe(u8, item);
                }

                var temp: std.ArrayList(child) = .empty;
                defer temp.deinit(a);
                for (item) |elem| {
                    try temp.append(a, try cloneElement(a, child, elem));
                }
                break :blk try temp.toOwnedSlice(a);
            }

            const new_ptr = try a.create(ptr.child);
            new_ptr.* = try cloneElement(a, ptr.child, item.*);
            break :blk new_ptr;
        },
        .array => |array| blk: {
            var new_array: T = item;
            inline for (0..array.len) |i| {
                new_array[i] = try cloneElement(a, @TypeOf(item[i]), item[i]);
            }
            break :blk new_array;
        },
        .@"struct" => try cloneStruct(a, T, item),
        else => item,
    };
}

pub fn deinitList(list: anytype, a: std.mem.Allocator) void {
    const input_type = @TypeOf(list);
    const list_type = switch (@typeInfo(input_type)) {
        .pointer => |ptr| ptr.child,
        else => input_type,
    };

    if (comptime !isArrayList(list_type)) {
        std.debug.print("Cannot use deinitArrayList to deinit other types.  Type: {s}\n", .{@typeName(list_type)});
        unreachable;
    }

    const slice_info = @typeInfo(list_type.Slice);
    const child_type = slice_info.pointer.child;
    if (std.meta.hasMethod(child_type, "deinit")) {
        for (list.items) |item| deinitStruct(item, a);
    } else if (@typeInfo(child_type) == .pointer and @typeInfo(child_type).pointer.size == .slice) {
        for (list.items) |item| {
            a.free(item);
        }
    }

    switch (@typeInfo(input_type)) {
        .pointer => {
            var list_ptr = @constCast(list);
            list_ptr.deinit(a);
        },
        else => deinitStruct(list, a),
    }
}

pub fn deinitStruct(item: anytype, a: std.mem.Allocator) void {
    if (!std.meta.hasMethod(@TypeOf(item), "deinit")) {
        unreachable;
    }

    const T = @TypeOf(item);
    var ptr: *T = @constCast(&item);
    _ = &ptr;

    const type_info = @typeInfo(@TypeOf(T.deinit));
    const param_count = type_info.@"fn".params.len;
    if (param_count > 1) {
        ptr.deinit(a);
    } else {
        ptr.deinit();
    }
}

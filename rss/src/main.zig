const std = @import("std");
const Io = std.Io;
const root = @import("root");
const host = @import("host");
const api = host.api.Server;
const apiContext = host.api.Context;
const logBuilder = @import("utilities").log.buildLogger;
const options = @import("options");

pub const std_options: std.Options = .{
    .log_level = .debug,
};

pub fn main(init: std.process.Init) !void {
    // const a: std.mem.Allocator = init.arena.allocator();
    const io = init.io;

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const args = try readArgs(a, init.minimal.args);

    const loggingEnabled = options.enable_logging and args.loggingEnabled;

    const log = try logBuilder(a, io, .{ .enabled = loggingEnabled, .minLevel = .Trace });
    defer log.deinit();

    var context = try a.create(apiContext);
    try context.init(a, io, args.host, args.port, log);
    defer a.destroy(context);
    defer context.deinit() catch {};

    const server_instance = try a.create(api);
    try api.init(context);
    defer a.destroy(server_instance);
    defer api.deinit(context);

    var server_thread = try std.Thread.spawn(.{ .allocator = a }, api.run, .{context});
    defer server_thread.join();
}

fn readArgs(a: std.mem.Allocator, args: std.process.Args) !config {
    var argsMap = std.StringHashMap([]const u8).init(a);
    var arg_iter = try std.process.Args.iterateAllocator(args, a);
    defer arg_iter.deinit();

    while (arg_iter.next()) |nv| {
        if (std.mem.containsAtLeastScalar2(u8, nv, '=', 1)) {
            var parts = std.mem.splitScalar(u8, nv, '=');
            const name = if (parts.next()) |part| part else null;
            const value = if (parts.next()) |part| part else null;
            if (name != null and value != null)
                try argsMap.put(name.?, value.?);
        } else {
            try argsMap.put(nv, "");
        }
    }
    const log_key = "logEnabled";
    const port = try std.fmt.parseInt(u16, argsMap.get("port") orelse "8089", 10);
    const local = argsMap.get("address") orelse "127.0.0.1";
    // "logEnabled" with no explicit value is treated as enabled for CLI
    // convenience (e.g. passing only `logEnabled`).
    const enable_logging = std.ascii.eqlIgnoreCase(argsMap.get(log_key) orelse "true", "true") or std.ascii.eqlIgnoreCase(argsMap.get(log_key) orelse "", "");

    return config{
        .host = local,
        .port = port,
        .loggingEnabled = enable_logging,
    };
}

const config = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8089,
    loggingEnabled: bool = true,
};

fn makeArgsFromCmdLine(a: std.mem.Allocator, cmd_line: []const u8) !struct { args: std.process.Args, raw: []u16 } {
    const cmd_line_w = try std.unicode.wtf8ToWtf16LeAlloc(a, cmd_line);
    return .{
        .args = .{ .vector = cmd_line_w },
        .raw = cmd_line_w,
    };
}

test "readArgs defaults when no args provided" {
    const a = std.testing.allocator;

    const input = try makeArgsFromCmdLine(a, "rss.exe");
    defer a.free(input.raw);

    const parsed = try readArgs(a, input.args);

    try std.testing.expectEqual(@as(u16, 8089), parsed.port);
    try std.testing.expectEqual(true, parsed.loggingEnabled);
    try std.testing.expectEqualStrings("127.0.0.1", parsed.host);
}

test "readArgs parses port and address" {
    const a = std.testing.allocator;

    const input = try makeArgsFromCmdLine(a, "rss.exe port=9090 address=0.0.0.0");
    defer a.free(input.raw);

    const parsed = try readArgs(a, input.args);

    try std.testing.expectEqual(@as(u16, 9090), parsed.port);
    try std.testing.expectEqualStrings("0.0.0.0", parsed.host);
}

test "readArgs logEnabled flag without value enables logging" {
    const a = std.testing.allocator;

    const input = try makeArgsFromCmdLine(a, "rss.exe logEnabled");
    defer a.free(input.raw);

    const parsed = try readArgs(a, input.args);

    try std.testing.expectEqual(true, parsed.loggingEnabled);
}

test "readArgs logEnabled=false disables logging" {
    const a = std.testing.allocator;

    const input = try makeArgsFromCmdLine(a, "rss.exe logEnabled=false");
    defer a.free(input.raw);

    const parsed = try readArgs(a, input.args);

    try std.testing.expectEqual(false, parsed.loggingEnabled);
}

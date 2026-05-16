const std = @import("std");
const Io = std.Io;
const host_mod = @import("host");
const Server = host_mod.api.Server;
const serverContext = host_mod.api.Context;

const io = std.testing.io;
const host_address = "127.0.0.1";

var next_port: u16 = 18080;

fn uniquePort() u16 {
    defer next_port += 1;
    return next_port;
}

fn sendRawRequest(a: std.mem.Allocator, port: u16, request: []const u8) ![]u8 {
    const address = try Io.net.IpAddress.parse(host_address, port);

    var attempt: usize = 0;
    while (true) : (attempt += 1) {
        var stream = address.connect(io, .{ .mode = .stream }) catch |err| {
            if (attempt < 20) {
                continue;
            }
            return err;
        };
        defer stream.close(io);

        var write_buffer: [2048]u8 = undefined;
        var reader_buffer: [2048]u8 = undefined;
        var stream_writer = stream.writer(io, &write_buffer);
        var stream_reader = stream.reader(io, &reader_buffer);

        try stream_writer.interface.writeAll(request);
        try stream_writer.interface.flush();

        return try stream_reader.interface.allocRemaining(a, .unlimited);
    }
}

fn requestWithContentLength(a: std.mem.Allocator, method: []const u8, target: []const u8, content_type: ?[]const u8, body: []const u8) ![]u8 {
    if (content_type) |ct| {
        return try std.fmt.allocPrint(
            a,
            "{s} {s} HTTP/1.1\r\nHost: {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ method, target, host_address, ct, body.len, body },
        );
    }

    return try std.fmt.allocPrint(
        a,
        "{s} {s} HTTP/1.1\r\nHost: {s}\r\nContent-Length: {d}\r\n\r\n{s}",
        .{ method, target, host_address, body.len, body },
    );
}

fn runStartupRequest(a: std.mem.Allocator, port: u16, request: []const u8) ![]u8 {
    const thread = try std.Thread.spawn(.{ .allocator = a }, Server.startup, .{ a, io, port, host_address });
    defer thread.join();
    return try sendRawRequest(a, port, request);
}

test "integration GET returns plain text body" {
    const a = std.testing.allocator;
    const port = uniquePort();
    const request = "GET /hello?arg1=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\n\r\n";

    const response = try runStartupRequest(a, port, request);
    defer a.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "200 OK") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "What\\") != null);
}

test "integration PUT returns method not allowed" {
    const a = std.testing.allocator;
    const port = uniquePort();
    const request = "PUT /rss HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\n\r\n";

    const response = try runStartupRequest(a, port, request);
    defer a.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "405 Method Not Allowed") != null);
}

test "integration POST rejects malformed json" {
    const a = std.testing.allocator;
    const port = uniquePort();
    const body = "{";
    const request = try requestWithContentLength(a, "POST", "/rss", "application/json", body);
    defer a.free(request);

    const response = try runStartupRequest(a, port, request);
    defer a.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "400 Bad Request") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "Error") != null);
}

test "integration POST returns JSON for invalid feed requests" {
    const a = std.testing.allocator;
    const port = uniquePort();
    const body = "{\"requests\":[{\"url\":\"not a url\",\"age_limit_hours\":1,\"item_limit\":1}]}";
    const request = try requestWithContentLength(a, "POST", "/rss", "application/json", body);
    defer a.free(request);

    const response = try runStartupRequest(a, port, request);
    defer a.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "200 OK") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "error while pulling feed") != null);
}

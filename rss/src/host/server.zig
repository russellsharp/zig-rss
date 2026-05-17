const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const http = std.http;
const logger = @import("utilities").log;
const hostUtilities = @import("utilities.zig");
const message = @import("messages.zig");
const ContentType = @import("messages.zig").ContentType;
const tasklist = @import("utilities").tasks.collection;
const service = @import("rss").Service;
const rssStructs = @import("rss").Structs;
const utilities = @import("utilities");

pub const Context = struct {
    host: ?[]u8 = null,
    port: u16,
    service: ?Io.net.Server = null,
    work: std.atomic.Value(bool),
    tasks: ?tasklist,
    a: std.mem.Allocator,
    io: std.Io,
    rss: *service.rss,
    logger: *logger.Logger,

    const Self = @This();

    pub fn init(s: *Self, a: std.mem.Allocator, io: std.Io, host: []const u8, port: u16, l: *logger.Logger) !void {
        s.host = try a.dupe(u8, host);
        s.port = port;
        s.work.store(true, .seq_cst);
        s.tasks = try tasklist.init(a);
        s.io = io;
        s.a = a;
        s.logger = l;
        s.rss = (a.create(service.rss) catch unreachable).init(a, io, l);
    }

    pub fn deinit(s: *Self) !void {
        s.tasks.?.deinit();
        if (s.host) |host| s.a.free(host);
        s.rss.deinit();
        s.a.destroy(s.rss);
        s.logger.deinit();
    }
};

const RouteHandler = struct {
    const Self = @This();
    supported_routes: std.ArrayList([]const u8) = .empty,

    fn init(a: std.mem.Allocator, to_support: []const []const u8) Self {
        var initialized = Self{};
        for (to_support) |route| {
            initialized.supported_routes.append(a, a.dupe(u8, route) catch unreachable) catch unreachable;
        }
        return initialized;
    }

    fn isSupported(s: *Self, route: []const u8) bool {
        return for (s.supported_routes.items) |item| {
            if (std.ascii.eqlIgnoreCase(route, item)) break true;
        } else false;
    }

    fn deinit(s: *Self, a: std.mem.Allocator) void {
        utilities.deinitList(s.supported_routes, a);
    }
};

pub const Server = struct {
    const Self = @This();

    pub fn startup(a: std.mem.Allocator, io: std.Io, port: u16, address: []const u8) !void {
        const context = try a.create(Context);
        defer a.destroy(context);

        const l = try logger.buildLogger(a, io);
        if (builtin.is_test) {
            l.options.stdLog = false;
        }
        try context.init(a, io, address, port, l);
        defer context.deinit() catch {};

        const server_address = try Io.net.IpAddress.parse(address, port);
        var listener = try server_address.listen(io, .{ .reuse_address = true });
        defer listener.deinit(io);

        try context.logger.format(.Warning, "Server listening on {s}:{d}\n", .{ address, port }, @typeName(@This()));

        const client_con = listener.accept(io) catch |err| {
            log(context, .Error, "Unable to accept client connections: {s}\n", .{@errorName(err)});
            return;
        };

        handle_incoming(context, client_con) catch |err| {
            log(context, .Error, "Failed to handle request: {s}", .{@errorName(err)});
            return;
        };
    }

    fn log(c: *Context, level: logger.Level, comptime msg: []const u8, fmt: anytype) void {
        c.logger.format(level, msg, fmt, @typeName(@This())) catch unreachable;
    }

    pub fn init(context: *Context) !void {
        const server_address = try Io.net.IpAddress.parse(context.host.?, context.port);
        context.service = try server_address.listen(context.io, .{ .reuse_address = true });
    }

    pub fn deinit(c: *Context) void {
        c.work.store(false, .seq_cst);
        // Send a dummy connection to unblock accept
        if (c.service) |s| {
            const port = s.socket.address.getPort();
            const wake_addr = Io.net.IpAddress.parse("127.0.0.1", port) catch return;
            var wake_stream = wake_addr.connect(c.io, .{ .mode = .stream }) catch return;
            wake_stream.close(c.io);
        }

        // Close the listener after the thread has exited
        if (c.service) |*s| {
            s.deinit(c.io);
            c.service = null;
        }
    }

    pub fn run(c: *Context) !void {
        if (c.service == null) {
            return;
        }

        if (c.tasks == null) {
            return;
        }

        while (c.work.load(.seq_cst)) {
            const client_con = c.service.?.accept(c.io) catch |err| {
                log(c, .Error, "Unable to accept client connections: {s}\n", .{@errorName(err)});
                if (err == error.Unexpected) {
                    log(c, .Info, "Most likely because of the server being forcibly closed.\n", .{});
                }
                return;
            };
            const new_thread = try std.Thread.spawn(.{ .allocator = c.a }, Server.handle_incoming, .{ c, client_con });
            try c.tasks.?.add(new_thread);
        }
    }

    fn handle_incoming(c: *Context, client_con: std.Io.net.Stream) !void {
        defer client_con.close(c.io);
        const read_buffer = try c.a.alloc(u8, 8 * 1024);
        defer c.a.free(read_buffer);
        const write_buffer = try c.a.alloc(u8, 8 * 1024);
        defer c.a.free(write_buffer);

        var con_reader = client_con.reader(c.io, read_buffer);
        var con_writer = client_con.writer(c.io, write_buffer);

        var server_instance = http.Server.init(&con_reader.interface, &con_writer.interface);

        var req = try server_instance.receiveHead();

        log(c, .Info, "Address requested: {s}\n", .{req.head.target});

        var paramMap = std.StringHashMap([]u8).init(c.a);
        defer paramMap.deinit();
        try hostUtilities.get_query_parameters(req.head.target, &paramMap);

        switch (req.head.method) {
            .POST => try handle_post(c, &req),
            else => try req.respond("", .{ .status = .method_not_allowed }),
        }
    }

    fn handle_connection(c: *Context, client_con: std.net.Server.Connection) !void {
        defer client_con.stream.close();
        const read_buffer = try c.a.alloc(u8, 8 * 1024);
        defer c.a.free(read_buffer);
        const write_buffer = try c.a.alloc(u8, 8 * 1024);
        defer c.a.free(write_buffer);

        var con_reader = client_con.stream.reader(read_buffer);
        var con_writer = client_con.stream.writer(write_buffer);

        var server_instance = http.Server.init(con_reader.interface(), &con_writer.interface);
        var req = try server_instance.receiveHead();

        try switch (req.head.method) {
            .POST => try handle_post(c, &req),
            else => try req.respond("", .{ .status = .method_not_allowed }),
        };
    }

    fn handle_post(c: *Context, req: *http.Server.Request) !void {
        var error_message: []const u8 = try c.a.alloc(u8, 0);
        defer c.a.free(error_message);

        var supported_routes: RouteHandler = .init(c.a, &[_][]const u8{"/rss"});
        defer supported_routes.deinit(c.a);

        //headers go away when accessing the body so grab the header info first.
        if (!supported_routes.isSupported(req.head.target)) {
            try @constCast(req).respond(error_message, .{ .status = .bad_request, .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain" }} });
            return;
        }

        const content_type = req.head.content_type;
        if (content_type == null) {
            error_message = try std.fmt.allocPrint(c.a, "Expects a content type specified, application/json.", .{});
        } else {
            const type_content = try ContentType.from_string(req.head.content_type.?);

            if (type_content != ContentType.Json) {
                error_message = try std.fmt.allocPrint(c.a, "Expects a content type specified, application/json.", .{});
            } else if (req.head.content_length == null) {
                error_message = try std.fmt.allocPrint(c.a, "Expects a Content-Length header for the request body.", .{});
            } else {
                const req_body = try c.a.alloc(u8, req.head.content_length.?);
                defer c.a.free(req_body);

                try read_request_body(req_body, req);

                var requests = parse_json(c, rssStructs.FeedRequests, req_body) catch |err| {
                    const response_body = try std.fmt.allocPrint(c.a, "Error {s}: {s}", .{ @errorName(err), req_body });
                    defer c.a.free(response_body);
                    try @constCast(req).respond(response_body, .{ .status = .bad_request, .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain" }} });
                    return;
                };
                defer requests.deinit(c.a);

                const results = c.rss.processRequests(requests) catch |err| {
                    const response_body = try std.fmt.allocPrint(c.a, "Error {s}", .{@errorName(err)});
                    defer c.a.free(response_body);
                    try @constCast(req).respond(response_body, .{ .status = .internal_server_error, .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain" }} });
                    return;
                };
                defer utilities.deinitList(results, c.a);

                const response_body = try c.rss.toJson(results.items);
                defer c.a.free(response_body);

                // std.debug.print("{s}\n", .{response_body});

                // Content-Type is intentionally text/plain to keep the client
                // side simple; the body is valid JSON regardless of the header.
                try @constCast(req).respond(response_body, .{ .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain" }} });

                return;
            }
        }

        try @constCast(req).respond(error_message, .{ .status = .bad_request, .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain" }} });
    }

    fn parse_json(c: *Context, T: type, input: []const u8) !T {
        const white_space = " \n\r";
        const trimmed = std.mem.trim(u8, input, white_space);

        var scanner = std.json.Scanner.initCompleteInput(c.a, trimmed);
        defer scanner.deinit();

        var diag = std.json.Diagnostics{};
        scanner.enableDiagnostics(&diag);

        const options = std.json.ParseOptions{ .ignore_unknown_fields = true, .allocate = .alloc_always };
        const parsed = std.json.parseFromTokenSource(T, c.a, &scanner, options) catch |err| {
            log(c, .Error, "Parsing failed at {d}:{d} - {s}\n", .{
                diag.getLine(),
                diag.getColumn(),
                @errorName(err),
            });
            return err;
        };
        defer parsed.deinit();

        // Clone before parsed is deinitialized so the returned value owns its memory
        // independently of the scanner and its underlying allocations.
        const requests = parsed.value.clone(c.a);
        return requests;
    }

    // Reads exactly Content-Length bytes into buffer. If Content-Length is absent
    // nothing is read; chunked transfer encoding and partial reads are not handled.
    fn read_request_body(buffer: []u8, req: *http.Server.Request) !void {
        if (req.head.content_length != null) {
            try req.readerExpectNone(buffer).fill(@as(usize, req.head.content_length.?));
        }
    }
};

test "RouteHandler.isSupported returns true for registered route" {
    const a = std.testing.allocator;
    var routes = RouteHandler.init(a, &[_][]const u8{"/rss"});
    defer routes.deinit(a);

    try std.testing.expect(routes.isSupported("/rss"));
}

test "RouteHandler.isSupported returns false for unregistered route" {
    const a = std.testing.allocator;
    var routes = RouteHandler.init(a, &[_][]const u8{"/rss"});
    defer routes.deinit(a);

    try std.testing.expect(!routes.isSupported("/other"));
}

test "RouteHandler.isSupported is case-insensitive" {
    const a = std.testing.allocator;
    var routes = RouteHandler.init(a, &[_][]const u8{"/rss"});
    defer routes.deinit(a);

    try std.testing.expect(routes.isSupported("/RSS"));
}

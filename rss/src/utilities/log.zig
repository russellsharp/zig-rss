const std = @import("std");
const dateTime = @import("time.zig").DateTime;

var s_instance: ?*Logger = null;
var s_ref_count: std.atomic.Value(u32) = .init(0);

const MESSAGE_MAX_LENGTH: u32 = 5000;

pub fn buildLogger(a: std.mem.Allocator, io: std.Io, options: ?LoggerOptions) !*Logger {
    if (s_instance == null) {
        const cwd = try std.process.currentPathAlloc(io, a);
        defer a.free(cwd);

        const paths = [2][]const u8{ cwd, "logs" };
        const full_path = try std.fs.path.join(a, &paths);
        defer a.free(full_path);

        s_instance = try Logger.init(a, io, full_path, options orelse LoggerOptions{});
    }
    _ = s_ref_count.fetchAdd(1, .monotonic);
    return s_instance.?;
}

pub const Level = enum {
    Trace,
    Debug,
    Info,
    Warning,
    Error,

    pub fn meets(self: Level, other: Level) bool {
        return (@intFromEnum(self) >= @intFromEnum(other));
    }
};

pub const LoggerOptions = struct {
    enabled: bool = true,
    minLevel: Level = Level.Error,
    stdLog: bool = true,
    usePrefixTimestamp: bool = true,
    autoNewLine: bool = false,
};

pub const Logger = struct {
    const Self = @This();

    io: std.Io,
    a: std.mem.Allocator,
    file: ?std.Io.File,
    directory: ?std.Io.Dir,
    writer: ?std.Io.Writer,
    path: []const u8,

    options: LoggerOptions,

    tasks: ?std.Io.Group,
    innerLock: std.Io.Mutex = .init,

    fn init(a: std.mem.Allocator, io: std.Io, path: []const u8, options: ?LoggerOptions) !*Self {
        var log_instance = try a.create(Self);
        log_instance.a = a;
        log_instance.io = io;
        log_instance.path = try a.dupe(u8, path);
        log_instance.options = options orelse LoggerOptions{};
        log_instance.tasks = .init;
        //initializes file and directory
        try log_instance.open();
        log_instance.innerLock = std.Io.Mutex.init;
        return log_instance;
    }

    pub fn deinit(s: *Self) void {
        _ = s_ref_count.fetchSub(1, .monotonic);
        if (s_instance == null) return;
        const count = s_ref_count.load(.monotonic);
        if (count <= 0) {
            if (s.tasks != null) {
                s.tasks.?.await(s.io) catch unreachable;
            }
            s.a.free(s.path);
            s.close();
            s.a.destroy(s_instance.?);
            s_instance = null;
        }
    }

    fn open(s: *Self) !void {

        //create directory
        s.directory = std.Io.Dir.cwd().createDirPathOpen(s.io, s.path, .{ .open_options = .{ .iterate = true } }) catch |fail| {
            std.log.err("Error while attempting to open path: {s}. Error: {s}", .{ s.path, @errorName(fail) });
            return fail;
        };

        const file_name = try s.newFileName(s.directory.?);
        defer s.a.free(file_name);
        const paths = [_][]const u8{ s.path, file_name };
        const full_path = try std.fs.path.join(s.a, &paths);
        defer s.a.free(full_path);

        //create and open file
        s.file = s.directory.?.createFile(s.io, full_path, .{}) catch |fail| {
            std.log.err("Error while attempting to open path: {s}. Error: {s}", .{ full_path, @errorName(fail) });
            return fail;
        };
    }

    fn close(s: *Self) void {
        if (s.file != null) {
            s.file.?.close(s.io);
            s.file = null;
        }
        if (s.file != null) {
            s.directory.?.close(s.io);
            s.directory = null;
        }
    }

    pub fn log(s: *Self, level: Level, msg: []const u8, category: []const u8) void {
        if (!s.options.enabled or !level.meets(s.options.minLevel)) return;

        var writerAllocating = std.Io.Writer.Allocating.init(s.a);
        defer writerAllocating.deinit();
        var writer = &writerAllocating.writer;

        if (s.options.usePrefixTimestamp) {
            const timestamp = getTimeStamp(s.a, s.io);
            defer s.a.free(timestamp);
            _ = writer.write(timestamp) catch unreachable;
        }

        if (category.len > 0) {
            _ = writer.write(category) catch unreachable;
            _ = writer.write(" - ") catch unreachable;
        }

        _ = writer.write(msg) catch unreachable;
        if (s.options.autoNewLine)
            _ = writer.write("\n") catch unreachable;
        writer.flush() catch unreachable;

        const log_entry = writer.buffer[0..writer.end];
        std.log.debug("log {s}", .{log_entry});

        // log_entry is backed by the temporary writer buffer above, so we duplicate
        // it before scheduling the async write. Cross-entry write order is not
        // guaranteed; inner acquires a mutex to serialize individual file writes.
        const copy = s.a.dupe(u8, log_entry) catch unreachable;
        s.tasks.?.concurrent(s.io, inner, .{ s, copy }) catch unreachable;

        if (s.options.stdLog) logToStream(level, msg);
    }

    //frees the msg buffer
    fn inner(s: *Self, msg: []const u8) void {
        s.innerLock.lock(s.io) catch unreachable;
        defer s.innerLock.unlock(s.io);

        //msg buffer will be freed
        defer s.a.free(msg);

        if (s.file) |file|
            file.writeStreamingAll(s.io, msg) catch unreachable;
    }

    pub fn format(s: *Self, level: Level, comptime fmt: []const u8, args: anytype, category: []const u8) !void {
        const buffer = try s.a.alloc(u8, MESSAGE_MAX_LENGTH);
        defer s.a.free(buffer);
        const formatted_msg = try std.fmt.bufPrint(buffer, fmt, args);
        s.log(level, formatted_msg, category);
    }

    pub fn err(s: *Self, msg: []const u8, category: []const u8) void {
        s.log(.Error, msg, category);
    }

    pub fn warn(s: *Self, msg: []const u8, category: []const u8) void {
        s.log(.Warning, msg, category);
    }

    pub fn info(s: *Self, msg: []const u8, category: []const u8) void {
        s.log(.Info, msg, category);
    }

    pub fn debug(s: *Self, msg: []const u8, category: []const u8) void {
        s.log(.Debug, msg, category);
    }

    pub fn trace(s: *Self, msg: []const u8, category: []const u8) void {
        s.log(.Trace, msg, category);
    }

    fn fileExists(s: *Self, dir: std.Io.Dir, file_name: []const u8) !bool {
        var iter = dir.iterate();
        while (try iter.next(s.io)) |entry| {
            if (std.ascii.eqlIgnoreCase(file_name, entry.name)) {
                return true;
            }
        }
        return false;
    }

    fn newFileName(s: *Self, dir: std.Io.Dir) ![]const u8 {
        const dt = dateTime.now(s.io);
        var file_name = try std.fmt.allocPrint(s.a, "log_{d:0>4}{d:0>2}{d:0>2}_{d:0>2}{d:0>2}{d:0>2}.txt", .{ dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second });
        defer s.a.free(file_name);

        var i: usize = 0;
        while (try s.fileExists(dir, file_name)) : (i += 1) {
            s.a.free(file_name);
            file_name = try std.fmt.allocPrint(s.a, "log_{d}{d}{d}_{d}{d}{d}_{d:0>2}.txt", .{ dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second, i });
        }

        return try s.a.dupe(u8, file_name);
    }

    fn logToStream(level: Level, msg: []const u8) void {
        switch (level) {
            .Trace => return std.log.info("{s}\n", .{msg}),
            .Debug => return std.log.debug("{s}\n", .{msg}),
            .Info => return std.log.info("{s}\n", .{msg}),
            .Warning => return std.log.warn("{s}\n", .{msg}),
            .Error => return std.log.err("{s}\n", .{msg}),
        }
    }
};

fn getTimeStamp(a: std.mem.Allocator, io: std.Io) []const u8 {
    const dt = dateTime.now(io);
    return std.fmt.allocPrint(a, "{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3} - ", .{ dt.hour, dt.minute, dt.second, dt.millisecond }) catch unreachable;
}

test "logger" {
    const io = std.testing.io;

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var log = try buildLogger(a, io, .{});
    defer log.deinit();

    log.info("hello", @typeName(@This()));
    try std.Io.sleep(io, .fromMilliseconds(1000), .real);
    log.info("asdf", @typeName(@This()));
    try std.Io.sleep(io, .fromMilliseconds(1000), .real);
    log.info("waaa", @typeName(@This()));
}

test "logger load test" {
    const io = std.testing.io;

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var log = try buildLogger(a, io, .{});
    defer log.deinit();

    const wait_time_ms = 1;
    for (0..150) |i| {
        try log.format(.Debug, "{d}", .{i}, @typeName(@This()));
        try std.Io.sleep(io, .fromMilliseconds(wait_time_ms), .real);
    }
}

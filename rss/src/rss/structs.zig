const std = @import("std");
const cloneList = @import("utilities").cloneList;
const deinitList = @import("utilities").deinitList;
const deinitStruct = @import("utilities").deinitStruct;
const string = []const u8;
const http = std.http;

pub const Summary = struct {
    const Self = @This();
    title: string = undefined,
    entries: std.ArrayList(FeedEntry) = .empty,
    request: FeedRequest = undefined,
    errors: std.ArrayList(string) = .empty,

    pub fn deinit(s: *Summary, a: std.mem.Allocator) void {
        a.free(s.title);
        deinitList(s.entries, a);
        deinitStruct(s.request, a);
        deinitList(s.errors, a);
    }

    pub fn fromFeedResult(a: std.mem.Allocator, result: FeedResult) *Summary {
        var s = a.create(Summary) catch unreachable;
        // Prefer the resolved response URL when available (after redirects);
        // otherwise preserve the original request URL for traceability.
        s.title = a.dupe(u8, result.url orelse result.request.url) catch unreachable;
        s.entries = cloneList(a, FeedEntry, result.entries);
        s.request = result.request.clone(a);
        s.errors = cloneList(a, string, result.errors);
        return s;
    }

    pub fn toString(s: *Summary, a: std.mem.Allocator) !string {
        var contents: std.ArrayList(string) = .empty;
        defer contents.deinit(a);
        try contents.append(a, try std.fmt.allocPrint(a, "{s}\n", .{s.title}));
        try contents.append(a, try std.fmt.allocPrint(a, "{any}\n", .{s.entries}));
        try contents.append(a, try std.fmt.allocPrint(a, "{any}\n", .{s.request}));
        try contents.append(a, try std.fmt.allocPrint(a, "{any}\n", .{s.errors}));
        return try fromArrayList(&contents, a);
    }
};

fn fromArrayList(contents: *const std.ArrayList(string), a: std.mem.Allocator) !string {
    return try std.mem.join(a, "", contents.items);
}

pub const FeedRequests = struct {
    const Self = @This();
    requests: []FeedRequest,

    pub fn deinit(s: *Self, a: std.mem.Allocator) void {
        for (s.requests) |*item| {
            item.deinit(a);
        }
        a.free(s.requests);
    }

    pub fn clone(s: *const Self, a: std.mem.Allocator) Self {
        var copy = s.*;
        copy.requests = a.alloc(FeedRequest, s.requests.len) catch unreachable;
        for (0..s.requests.len) |i| {
            copy.requests[i] = s.requests[i].clone(a);
        }
        return copy;
    }
};

pub const FeedRequest = struct {
    const Self = @This();
    url: string,
    age_limit_hours: usize,
    item_limit: usize,

    pub fn init(a: std.mem.Allocator) Self {
        return Self{
            .url = a.dupe(u8, "") catch unreachable,
            .age_limit_hours = 0,
            .item_limit = 0,
        };
    }

    pub fn clone(s: *const Self, a: std.mem.Allocator) Self {
        return Self{
            .url = a.dupe(u8, s.url) catch unreachable,
            .age_limit_hours = s.age_limit_hours,
            .item_limit = s.item_limit,
        };
    }

    pub fn deinit(s: Self, a: std.mem.Allocator) void {
        a.free(s.url);
    }
};

pub const FeedEntry = struct {
    const Self = @This();
    link: string = undefined,
    subject: string = undefined,
    published: string = undefined,
    title: string = undefined,
    parsedDate: ?string = null,

    pub fn init(a: std.mem.Allocator, link: string, subject: string, published: string, title: string, parsedDate: string) Self {
        var s = a.create(FeedEntry) catch unreachable;
        defer a.destroy(s);
        s.link = a.dupe(u8, link) catch unreachable;
        s.subject = a.dupe(u8, subject) catch unreachable;
        s.published = a.dupe(u8, published) catch unreachable;
        s.title = a.dupe(u8, title) catch unreachable;
        s.parsedDate = a.dupe(u8, parsedDate) catch unreachable;
        return s.*;
    }

    pub fn deinit(s: Self, a: std.mem.Allocator) void {
        a.free(s.link);
        a.free(s.subject);
        a.free(s.published);
        a.free(s.title);
        a.free(s.parsedDate.?);
    }

    pub fn clone(s: *const Self, a: std.mem.Allocator) !Self {
        var copy = s.*;
        copy.link = try a.dupe(u8, s.link);
        copy.subject = try a.dupe(u8, s.subject);
        copy.published = try a.dupe(u8, s.published);
        copy.title = try a.dupe(u8, s.title);
        copy.parsedDate = try a.dupe(u8, s.parsedDate.?);
        return copy;
    }

    pub fn toString(s: *const Self, a: std.mem.Allocator) !string {
        var contents: std.ArrayList(string) = .empty;
        defer contents.deinit(a);
        try contents.append(a, try std.fmt.allocPrint(a, "{s}\n", .{s.link}));
        try contents.append(a, try std.fmt.allocPrint(a, "{s}\n", .{s.subject}));
        try contents.append(a, try std.fmt.allocPrint(a, "{s}\n", .{s.published}));
        try contents.append(a, try std.fmt.allocPrint(a, "{s}\n", .{s.title}));
        try contents.append(a, try std.fmt.allocPrint(a, "{s}\n", .{s.parsedDate.?}));
        return try fromArrayList(&contents, a);
    }
};

pub const FeedResult = struct {
    const Self = @This();
    allocator: std.mem.Allocator = std.heap.page_allocator,
    url: ?string = null,
    status: http.Status = .ok,
    request: FeedRequest = .init(std.heap.page_allocator),
    entries: std.ArrayList(FeedEntry) = .empty,
    body: ?string = null,
    headers: ?std.ArrayList(*http.Header) = null,
    errors: std.ArrayList(string) = .empty,

    pub fn init(a: std.mem.Allocator) Self {
        return Self{
            .allocator = a,
            .url = null,
            .status = .ok,
            .request = .init(a),
            .entries = .empty,
            .body = null,
            .headers = null,
            .errors = .empty,
        };
    }

    pub fn clone(s: *const Self, a: std.mem.Allocator) Self {
        return Self{
            .allocator = a,
            .url = if (s.url) |url| a.dupe(u8, url) catch unreachable else null,
            .status = s.status,
            .request = s.request.clone(a),
            .entries = cloneList(a, FeedEntry, s.entries),
            .body = if (s.body) |body| a.dupe(u8, body) catch unreachable else null,
            // Headers are stored as pointers, so this must deep-copy pointed
            // header instances to keep clone/deinit ownership independent.
            .headers = if (s.headers) |headers| cloneList(a, *http.Header, headers) else null,
            .errors = cloneList(a, string, s.errors),
        };
    }

    pub fn deinit(s: *const Self) void {
        const a = s.allocator;
        if (s.url) |url| a.free(url);
        s.request.deinit(a);
        deinitList(s.entries, a);
        if (s.body) |body| a.free(body);
        if (s.headers) |headers| {
            for (headers.items) |header| {
                a.free(header.name);
                a.free(header.value);
                a.destroy(header);
            }
            var headers_copy = headers;
            headers_copy.deinit(a);
        }
        deinitList(s.errors, a);
    }

    pub fn contentLength(s: *const Self) !usize {
        if (s.headers == null) return 0;
        for (s.headers.?.items) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "Content-Length")) {
                return try std.fmt.parseInt(usize, header.value, 10);
            }
        }
        return 0;
    }

    pub fn dupeHeader(original: http.Header, copy: *http.Header, a: std.mem.Allocator) !void {
        copy.* = .{
            .name = try a.dupe(u8, original.name),
            .value = try a.dupe(u8, original.value),
        };
    }

    pub fn print(s: *const Self, writer: *std.Io.Writer) !void {
        try writer.print("url: {?s}\n", .{s.url});
        try writer.print("request: {any}\n", .{s.request});
        try writer.print("entries: {any}\n", .{s.entries.items});
        try writer.print("body: {?s}\n", .{s.body});
        try writer.print("headers: {?any}\n", .{s.headers});
        try writer.print("errors: {any}\n", .{s.errors.items});
    }
};

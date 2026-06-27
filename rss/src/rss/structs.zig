const std = @import("std");
const cloneList = @import("utilities").cloneList;
const deinitList = @import("utilities").deinitList;
const deinitStruct = @import("utilities").deinitStruct;
const string = @import("string").string(u8);
const http = std.http;

fn deinit_optional(field: *const ?string) void {
    var var_ptr: *?string = @constCast(field);
    _ = &var_ptr;
    if (var_ptr.*) |ptr| {
        @constCast(&ptr).deinit();
    }
    var_ptr.* = null;
}

pub const Summary = struct {
    const Self = @This();
    title: string = undefined,
    entries: std.ArrayList(FeedEntry) = .empty,
    request: FeedRequest = undefined,
    errors: std.ArrayList(string) = .empty,

    pub fn deinit(s: *Summary, a: std.mem.Allocator) void {
        s.title.deinit();
        deinitList(s.entries, a);
        deinitStruct(s.request, a);
        deinitList(s.errors, a);
    }

    pub fn fromFeedResult(a: std.mem.Allocator, result: FeedResult) *Summary {
        var s = a.create(Summary) catch unreachable;
        // Prefer the resolved response URL when available (after redirects);
        // otherwise preserve the original request URL for traceability.
        s.title = if (!result.url.?.empty()) result.url.?.clone(a) else result.request.url.clone(a);
        s.entries = cloneList(a, FeedEntry, result.entries);
        s.request = result.request.clone(a);
        s.errors = cloneList(a, string, result.errors);
        return s;
    }

    pub fn toString(s: *Summary, a: std.mem.Allocator) !string {
        var contents: std.ArrayList(string) = .empty;
        defer contents.deinit(a);
        var formatted_string = string.init(a, "");
        defer formatted_string.deinit();
        try contents.append(a, formatted_string.assign_format("{s}\n", .{s.title}));
        try contents.append(a, formatted_string.assign_format("{any}\n", .{s.entries}));
        try contents.append(a, formatted_string.assign_format("{any}\n", .{s.request}));
        try contents.append(a, formatted_string.assign_format("{any}\n", .{s.errors}));
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
            item.deinit();
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
            .url = .init(a, ""),
            .age_limit_hours = 0,
            .item_limit = 0,
        };
    }

    pub fn clone(s: *const Self, a: std.mem.Allocator) Self {
        return Self{
            .url = s.url.clone(a),
            .age_limit_hours = s.age_limit_hours,
            .item_limit = s.item_limit,
        };
    }

    pub fn deinit(s: *Self) void {
        @constCast(&s.url).deinit();
    }
};

pub const FeedEntry = struct {
    const Self = @This();
    link: ?string = undefined,
    subject: ?string = undefined,
    published: ?string = undefined,
    title: ?string = undefined,
    parsedDate: ?string = null,

    pub fn init(a: std.mem.Allocator, link: string, subject: string, published: string, title: string, parsedDate: string) Self {
        var s = a.create(FeedEntry) catch unreachable;
        defer a.destroy(s);
        s.link = link.clone(a);
        s.subject = subject.clone(a);
        s.published = published.clone(a);
        s.title = title.clone(a);
        s.parsedDate = parsedDate.clone(a);
        return s.*;
    }

    pub fn init_empty(a: std.mem.Allocator) Self {
        var s = a.create(FeedEntry) catch unreachable;
        defer a.destroy(s);
        s.link = string.init(a, "");
        s.subject = string.init(a, "");
        s.published = string.init(a, "");
        s.title = string.init(a, "");
        s.parsedDate = string.init(a, "");
        return s.*;
    }

    pub fn deinit(s: *Self) void {
        deinit_optional(&s.link);
        deinit_optional(&s.subject);
        deinit_optional(&s.published);
        deinit_optional(&s.title);
        deinit_optional(&s.parsedDate);
    }

    pub fn clone(s: *const Self, a: std.mem.Allocator) !Self {
        var copy = s.*;
        copy.link = s.link.?.clone(a);
        copy.subject = s.subject.?.clone(a);
        copy.published = s.published.?.clone(a);
        copy.title = s.title.?.clone(a);
        copy.parsedDate = s.parsedDate.?.clone(a);
        return copy;
    }

    pub fn toString(s: *const Self, a: std.mem.Allocator) !string {
        var contents: std.ArrayList(string) = .empty;
        defer contents.deinit(a);
        try contents.append(a, try std.fmt.allocPrint(a, "{s}\n", .{s.link.?.str()}));
        try contents.append(a, try std.fmt.allocPrint(a, "{s}\n", .{s.subject.?.str()}));
        try contents.append(a, try std.fmt.allocPrint(a, "{s}\n", .{s.published.?.str()}));
        try contents.append(a, try std.fmt.allocPrint(a, "{s}\n", .{s.title.?.str()}));
        try contents.append(a, try std.fmt.allocPrint(a, "{s}\n", .{s.parsedDate.?.str()}));
        return try fromArrayList(&contents, a);
    }
};

pub const FeedResult = struct {
    const Self = @This();
    allocator: std.mem.Allocator = undefined,
    url: ?string = null,
    status: http.Status = .ok,
    request: FeedRequest = undefined,
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
            .url = if (s.url) |url| url.clone(a) else null,
            .status = s.status,
            .request = s.request.clone(a),
            .entries = cloneList(a, FeedEntry, s.entries),
            .body = if (s.body) |body| body.clone(a) else null,
            // Headers are stored as pointers, so this must deep-copy pointed
            // header instances to keep clone/deinit ownership independent.
            .headers = if (s.headers) |headers| cloneList(a, *http.Header, headers) else null,
            .errors = cloneList(a, string, s.errors),
        };
    }

    pub fn deinit(s: *const Self) void {
        const a = s.allocator;
        deinit_optional(&s.url);
        @constCast(&s.request).deinit();
        deinitList(s.entries, a);

        deinit_optional(&s.body);

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

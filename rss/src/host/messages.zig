const std = @import("std");
const Io = std.Io;
const http = std.http;
const utilities = @import("utilities.zig");

const white_space_characters = "\r\t \n";
pub const Messages = @This();

pub const TestMessage = struct { field_string: ?[]const u8, field_unsigned: ?u32, field_struct: ?InnerMessage };

pub const InnerMessage = struct {
    msg: ?[]const u8,
};

pub const ContentType = enum {
    PlainText,
    Json,
    Unknown,

    pub fn to_string(content: *const ContentType) []const u8 {
        switch (content.*) {
            ContentType.PlainText => return "text/plain",
            ContentType.Json => return "application/json",
            ContentType.Unknown => return "unknown,",
        }
    }

    pub fn from_string(text: []const u8) !ContentType {
        // Some HTTP stacks include CRLF and other white space after header values; compare only the
        // first line so "application/json\r\n" still resolves correctly.
        const relevant_text = text[0 .. std.mem.indexOf(u8, text, "\r") orelse text.len];
        if (std.mem.eql(u8, relevant_text, to_string(&ContentType.PlainText))) return ContentType.PlainText;
        if (std.mem.eql(u8, relevant_text, to_string(&ContentType.Json))) return ContentType.Json;
        return ContentType.Unknown;
    }
};

test "ContentType to_string" {
    try std.testing.expectEqualStrings("text/plain", ContentType.to_string(&ContentType.PlainText));
    try std.testing.expectEqualStrings("application/json", ContentType.to_string(&ContentType.Json));
    try std.testing.expectEqualStrings("unknown,", ContentType.to_string(&ContentType.Unknown));
}

test "ContentType from_string plain text" {
    const ct = try ContentType.from_string("text/plain");
    try std.testing.expectEqual(ContentType.PlainText, ct);
}

test "ContentType from_string json" {
    const ct = try ContentType.from_string("application/json");
    try std.testing.expectEqual(ContentType.Json, ct);
}

test "ContentType from_string unknown" {
    const ct = try ContentType.from_string("text/html");
    try std.testing.expectEqual(ContentType.Unknown, ct);
}

test "ContentType from_string strips trailing CRLF" {
    const ct = try ContentType.from_string("text/plain\r\nother");
    try std.testing.expectEqual(ContentType.PlainText, ct);
}

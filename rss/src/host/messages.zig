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
        // Normalize content-type values by keeping only the first line,
        // dropping parameters (e.g. charset), and trimming spaces.
        const first_line = text[0 .. std.mem.indexOfAny(u8, text, "\r\n") orelse text.len];
        const media_type = first_line[0 .. std.mem.indexOfScalar(u8, first_line, ';') orelse first_line.len];
        const relevant_text = std.mem.trim(u8, media_type, " \t");

        if (std.ascii.eqlIgnoreCase(relevant_text, to_string(&ContentType.PlainText))) return ContentType.PlainText;
        if (std.ascii.eqlIgnoreCase(relevant_text, to_string(&ContentType.Json))) return ContentType.Json;
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

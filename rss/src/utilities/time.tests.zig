const std = @import("std");
const utilities = @import("utilities.zig");

const time_mod = utilities.time;

const example = "Fri, 17 Apr 2026 08:00:00 -0400";
const example_single_digit_day = "Fri, 7 Apr 2026 08:00:00 -0400";

test "difference in unix times in hours" {
    const dt_1 = try time_mod.parseDateTime("Fri, 17 Apr 2026 08:00:00 -0400");
    const dt_2 = try time_mod.parseDateTime("Fri, 17 Apr 2026 03:00:00 -0400");
    const unix_1: i64 = @intCast(time_mod.dateTimeToUnixUtc(dt_1));
    const unix_2: i64 = @intCast(time_mod.dateTimeToUnixUtc(dt_2));
    const diff = time_mod.differenceHours(unix_1, unix_2);
    try std.testing.expectEqual(-5, diff);
}

test "date time to unix" {
    const dt = try time_mod.parseDateTime(example);
    try std.testing.expectEqual(17, dt.day);
    try std.testing.expectEqual(4, dt.month);
    try std.testing.expectEqual(2026, dt.year);
    try std.testing.expectEqual(8, dt.hour);
    const unix_time = time_mod.dateTimeToUnixUtc(dt);
    try std.testing.expectEqual(1776427200, unix_time);
}

test "getDayReadable" {
    const shortDay: []const u8 = example[0..3];
    const shortDayIndex = time_mod.dayOfTheWeek(shortDay);
    try std.testing.expectEqual(5, shortDayIndex);
}

test "dayOfTheMonthNumeral" {
    const dayofTheMonthNumeralString = example[5..7];
    const dayNumeral = try time_mod.dayOfTheMonth(dayofTheMonthNumeralString);
    try std.testing.expectEqual(17, dayNumeral);
}

test "short month string to month numeral" {
    const monthString = example[8..11];
    const monthNumeral = try time_mod.monthFromShortMonth(monthString);
    try std.testing.expectEqual(4, monthNumeral);
}

test "year string to year numeral" {
    const yearString = example[12..16];
    const yearNumeral = try time_mod.yearFromFourDigits(yearString);
    try std.testing.expectEqual(2026, yearNumeral);
}

test "time" {
    const timeString = example[17..25];
    const clockTime = try time_mod.timeStampFromString(timeString);
    try std.testing.expectEqual(@as(u8, 8), clockTime.hour);
    try std.testing.expectEqual(@as(u8, 0), clockTime.minute);
    try std.testing.expectEqual(@as(u8, 0), clockTime.second);
}

test "timezone" {
    const tzString = example[26..31];
    const timeZone = try time_mod.tzFromString(tzString);
    try std.testing.expectEqual(-400, timeZone);
}

test "isLeapYear" {
    try std.testing.expect(time_mod.isLeapYear(2000));
    try std.testing.expect(time_mod.isLeapYear(2024));
    try std.testing.expect(!time_mod.isLeapYear(1900));
    try std.testing.expect(!time_mod.isLeapYear(2023));
}

test "daysInMonth" {
    try std.testing.expectEqual(@as(u8, 31), time_mod.daysInMonth(1, 2024));
    try std.testing.expectEqual(@as(u8, 29), time_mod.daysInMonth(2, 2024));
    try std.testing.expectEqual(@as(u8, 28), time_mod.daysInMonth(2, 2023));
    try std.testing.expectEqual(@as(u8, 30), time_mod.daysInMonth(4, 2024));
    try std.testing.expectEqual(@as(u8, 31), time_mod.daysInMonth(12, 2024));
}

test "unixTimestampToUTC epoch" {
    const dt = time_mod.unixTimestampToUTC(0);
    try std.testing.expectEqual(@as(u32, 1970), dt.year);
    try std.testing.expectEqual(@as(u8, 1), dt.month);
    try std.testing.expectEqual(@as(u8, 1), dt.day);
    try std.testing.expectEqual(@as(u8, 0), dt.hour);
    try std.testing.expectEqual(@as(u8, 0), dt.minute);
    try std.testing.expectEqual(@as(u8, 0), dt.second);
}

test "differenceHours" {
    try std.testing.expectEqual(@as(i64, 2), time_mod.differenceHours(0, 7200));
    try std.testing.expectEqual(@as(i64, -2), time_mod.differenceHours(7200, 0));
    try std.testing.expectEqual(@as(i64, 0), time_mod.differenceHours(3600, 3600));
    try std.testing.expectEqual(@as(i64, 24), time_mod.differenceHours(0, 86400));
}

test "parseDateTime two-digit day" {
    const input = "Wed, 10 Dec 2025 23:06:28 +0000";
    const dt = try time_mod.parseDateTime(input);
    try std.testing.expectEqual(@as(u32, 2025), dt.year);
    try std.testing.expectEqual(@as(u8, 12), dt.month);
    try std.testing.expectEqual(@as(u8, 10), dt.day);
    try std.testing.expectEqual(@as(u8, 23), dt.hour);
    try std.testing.expectEqual(@as(u8, 6), dt.minute);
    try std.testing.expectEqual(@as(u8, 28), dt.second);
    try std.testing.expectEqual(@as(i16, 0), dt.timezone);
}

test "single digit day" {
    const dt = try time_mod.parseDateTime(example_single_digit_day);
    try std.testing.expectEqual(7, dt.day);
    try std.testing.expectEqual(4, dt.month);
}

test "dateTime by function" {
    const dt = try time_mod.parseDateTime(example);
    try std.testing.expectEqual(17, dt.day);
    try std.testing.expectEqual(4, dt.month);
    try std.testing.expectEqual(2026, dt.year);
}

test "apply timezone new year rollover" {
    const new_years_eve = "Fri, 31 DEC 2026 23:59:00 -0000";
    const dt_0 = try time_mod.parseDateTime(new_years_eve);
    try std.testing.expectEqual(23, dt_0.hour);
    const dt_offset = try time_mod.applyOffset(dt_0, 4);
    try std.testing.expectEqual(3, dt_offset.hour);
    try std.testing.expectEqual(1, dt_offset.day);
    try std.testing.expectEqual(1, dt_offset.month);
}

test "apply timezone new years day rollback" {
    const new_years_day = "Fri, 01 JAN 2026 00:00:00 -0100";
    const dt_1 = try time_mod.parseDateTime(new_years_day);
    const dt_offset = try time_mod.applyOffset(dt_1, -1);
    try std.testing.expectEqual(2025, dt_offset.year);
    try std.testing.expectEqual(12, dt_offset.month);
    try std.testing.expectEqual(31, dt_offset.day);
    try std.testing.expectEqual(23, dt_offset.hour);
}

test "Diary of a CEO timestamp" {
    const timestamp = "Mon, 01 Jun 2026 05:00:00 -0000";
    const dt = try time_mod.parseDateTime(timestamp);
    try std.testing.expectEqual(2026, dt.year);
    try std.testing.expectEqual(1, dt.day);
    try std.testing.expectEqual(6, dt.month);
    try std.testing.expectEqual(5, dt.hour);
    try std.testing.expectEqual(0, dt.minute);
    try std.testing.expectEqual(0, dt.second);
    try std.testing.expectEqual(0, dt.timezone);
}

test "unix to string" {
    const allocator = std.heap.page_allocator;

    var out: std.Io.Writer.Allocating = .init(allocator);
    const writer = &out.writer;
    defer out.deinit();

    const timestamp: u64 = @intCast(std.Io.Timestamp.now(std.testing.io, .real).toMilliseconds());

    const dt = time_mod.unixTimestampToUTC(timestamp);

    const iso8601 = try std.fmt.allocPrint(
        allocator,
        "{}-{:0>2}-{:0>2}T{:0>2}:{:0>2}:{:0>2}.{:0>3} {:0}",
        .{ dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second, dt.millisecond, dt.timezone },
    );
    defer allocator.free(iso8601);

    try writer.print("ISO 8601 UTC: {s}", .{iso8601});
    try writer.flush();
}

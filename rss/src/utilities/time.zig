const std = @import("std");
const parseTime = @This();
const time = @import("std").time;
const string = []const u8;

pub fn parseDateTime(date_time: string, io: std.Io) !DateTime {
    var dt = DateTime.now(io);

    const dayofTheMonthNumeralString = date_time[5..7];
    var day_offset: usize = 0;
    if (dayofTheMonthNumeralString[1] == ' ') {
        day_offset += 1;
    }
    // RSS feeds sometimes emit single-digit days with an extra space (e.g.
    // "Mon,  2 Jan ..."); day_offset keeps all following slices aligned.
    dt.day = try dayOfTheMonth(std.mem.trim(u8, dayofTheMonthNumeralString, " "));

    const monthString = date_time[8 - day_offset .. 11 - day_offset];
    dt.month = try monthFromShortMonth(monthString);
    const yearString = date_time[12 - day_offset .. 16 - day_offset];
    dt.year = try yearFromFourDigits(yearString);
    const timeString = date_time[17 - day_offset .. 25 - day_offset];
    const clockTime = try timeStampFromString(timeString);

    dt.hour = clockTime.hour;
    dt.minute = clockTime.minute;
    dt.second = clockTime.second;
    dt.millisecond = clockTime.millisecond;

    const tz_end = @min(date_time.len, 31);
    const tzString = date_time[26 - day_offset .. tz_end - day_offset];
    dt.timezone = try tzFromString(tzString);

    return dt;
}

const seconds_in_day: u32 = 86400;
const seconds_in_hour: u32 = 3600;

pub fn dateTimeToUnixUtc(dt: DateTime) u64 {
    if (dt.year < 1970) unreachable;

    var running_total: u64 = 0;

    for (1970..dt.year) |year| {
        running_total += daysInYear(year) * seconds_in_day;
    }

    for (1..dt.month) |month| {
        running_total += @as(u64, daysInMonth(@intCast(month), dt.year)) * seconds_in_day;
    }

    running_total += @as(u64, dt.day - 1) * seconds_in_day;
    running_total += @as(u64, dt.hour) * seconds_in_hour;
    running_total += @as(u64, dt.minute) * 60;
    running_total += dt.second;

    const timezone_hours: i64 = @divTrunc(dt.timezone, 100);
    const offset: i64 = timezone_hours * @as(i64, seconds_in_hour);
    var total_with_offset: i64 = @intCast(running_total);
    // Local timestamp -> UTC epoch: subtract local offset from wall-clock time.
    total_with_offset -= offset;
    running_total = @intCast(total_with_offset);

    return running_total;
}

pub fn differenceHours(unix_0: i64, unix_1: i64) i64 {
    return @divTrunc(unix_1 - unix_0, 3600);
}

pub const DateTime = struct {
    year: u32,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    millisecond: u16,
    timezone: i16,

    pub fn now(io: std.Io) DateTime {
        const timestamp_now = std.Io.Timestamp.now(io, .real).toMilliseconds();
        const unsigned_now: u64 = @intCast(timestamp_now);
        return unixTimestampToUTC(unsigned_now);
    }
};

const Time = struct {
    hour: u8,
    minute: u8,
    second: u8,
    millisecond: u16,
};

pub fn isLeapYear(year: u32) bool {
    return (@rem(year, 4) == 0 and @rem(year, 100) != 0) or (@rem(year, 400) == 0);
}

const short_month_names = [_]string{
    "jan",
    "feb",
    "mar",
    "apr",
    "may",
    "jun",
    "jul",
    "aug",
    "sep",
    "oct",
    "nov",
    "dec",
};

pub fn daysInMonth(month: u8, year: u32) u8 {
    return switch (month) {
        1 => 31,
        2 => if (isLeapYear(year)) 29 else 28,
        3 => 31,
        4 => 30,
        5 => 31,
        6 => 30,
        7 => 31,
        8 => 31,
        9 => 30,
        10 => 31,
        11 => 30,
        12 => 31,
        else => unreachable,
    };
}

pub fn unixTimestampToUTC(timestamp: u64) DateTime {
    const MILLIS_PER_SEC = 1000;
    const SECS_PER_MIN = 60;
    const SECS_PER_HOUR = SECS_PER_MIN * 60;
    const SECS_PER_DAY = SECS_PER_HOUR * 24;

    const millisecond: u16 = @intCast(@rem(timestamp, MILLIS_PER_SEC));
    const seconds = @divTrunc(timestamp, MILLIS_PER_SEC);

    const hour: u8 = @intCast(@divTrunc(@rem(seconds, SECS_PER_DAY), SECS_PER_HOUR));
    const minute: u8 = @intCast(@divTrunc(@rem(seconds, SECS_PER_HOUR), SECS_PER_MIN));
    const second: u8 = @intCast(@rem(seconds, SECS_PER_MIN));

    var days = @divTrunc(seconds, SECS_PER_DAY);
    var year: u32 = 1970;

    while (true) {
        const days_in_year: u16 = if (isLeapYear(year)) 366 else 365;
        if (days >= days_in_year) {
            days -= days_in_year;
            year += 1;
        } else break;
    }

    var month: u8 = 1;
    while (true) {
        const day_of_month = daysInMonth(month, year);
        if (days >= day_of_month) {
            days -= day_of_month;
            month += 1;
        } else break;
    }

    const day: u8 = @intCast(days + 1);

    return DateTime{
        .year = year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
        .millisecond = millisecond,
        .timezone = 0,
    };
}

pub fn dayOfTheWeek(dayReadable: string) !usize {
    return switch (std.ascii.toLower(dayReadable[0])) {
        's' => if (std.ascii.eqlIgnoreCase(dayReadable, "sun")) 0 else 6,
        'm' => 1,
        't' => if (std.ascii.eqlIgnoreCase(dayReadable, "thu")) 4 else 2,
        'w' => 3,
        'f' => 5,
        else => 0,
    };
}

pub fn dayOfTheMonth(dayNumeralString: string) !u8 {
    return try std.fmt.parseInt(u8, dayNumeralString, 10);
}

pub fn monthFromShortMonth(monthShort: string) !u8 {
    for (short_month_names, 0..) |month, i| {
        if (std.ascii.eqlIgnoreCase(monthShort, month)) return @intCast(i + 1);
    }
    return 0;
}

pub fn yearFromFourDigits(yearString: string) !u32 {
    return try std.fmt.parseInt(u32, yearString, 10);
}

pub fn timeStampFromString(timeString: string) !Time {
    const hourString = timeString[0..2];
    const minuteString = timeString[3..5];
    const secondString = timeString[6..8];
    return Time{
        .hour = try std.fmt.parseInt(u8, hourString, 10),
        .minute = try std.fmt.parseInt(u8, minuteString, 10),
        .second = try std.fmt.parseInt(u8, secondString, 10),
        .millisecond = 0,
    };
}

pub fn tzFromString(tzString: string) !i16 {
    return std.fmt.parseInt(i16, tzString, 10) catch |err| {
        if (std.ascii.eqlIgnoreCase("gmt", tzString)) return 0;
        return err;
    };
}

pub fn applyOffset(dt: DateTime, offset: i8) !DateTime {
    var dt_offset = dt;
    const offset_abs: u8 = @intCast(@abs(offset));

    if (offset > 0) {
        if (dt_offset.hour + offset_abs > 23) {
            dt_offset.hour = @intCast(dt_offset.hour + offset_abs - 24);
            if (dt_offset.day + 1 > daysInMonth(dt_offset.month, dt_offset.year)) {
                if (dt_offset.month + 1 > 12) {
                    dt_offset.year += 1;
                    dt_offset.month = 1;
                    dt_offset.day = 1;
                } else {
                    dt_offset.month += 1;
                    dt_offset.day = 1;
                }
            } else {
                dt_offset.day += 1;
            }
        } else {
            dt_offset.hour += offset_abs;
        }
    } else if (offset < 0) {
        if (dt_offset.hour < offset_abs) {
            dt_offset.hour = @intCast(24 + dt_offset.hour - offset_abs);
            if (dt_offset.day <= 1) {
                if (dt_offset.month == 1) {
                    dt_offset.year -= 1;
                    dt_offset.month = 12;
                    dt_offset.day = daysInMonth(12, dt_offset.year);
                } else {
                    dt_offset.month -= 1;
                    dt_offset.day = daysInMonth(dt_offset.month, dt_offset.year);
                }
            } else {
                dt_offset.day -= 1;
            }
        } else {
            dt_offset.hour -= offset_abs;
        }
    }

    return dt_offset;
}

fn daysInYear(year: usize) usize {
    const value: u32 = @intCast(year);
    return if (isLeapYear(value)) @as(usize, 366) else @as(usize, 365);
}

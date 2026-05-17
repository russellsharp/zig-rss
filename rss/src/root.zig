//! By convention, root.zig is the root source file when making a package.
const std = @import("std");

pub const log_level: std.log.Level = .debug;

test {
    _ = @import("main.zig");
    _ = @import("host/server.zig");
    _ = @import("host/messages.tests.zig");
    _ = @import("host/utilities.tests.zig");
    _ = @import("rss/client.zig");
    _ = @import("rss/structs.tests.zig");
    _ = @import("rss/service.tests.zig");
    _ = @import("rss/rss.tests.zig");
    _ = @import("utilities/clone.tests.zig");
    _ = @import("utilities/log.tests.zig");
    _ = @import("utilities/protectedCollection.tests.zig");
    _ = @import("utilities/tasks.tests.zig");
    _ = @import("utilities/time.tests.zig");
    _ = @import("test.zig");
}

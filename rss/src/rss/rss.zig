pub const Client = @import("client.zig");
pub const Service = @import("service.zig");
pub const Structs = @import("structs.zig");

test {
    _ = @import("rss.tests.zig");
    _ = @import("service.tests.zig");
    _ = @import("structs.tests.zig");
}

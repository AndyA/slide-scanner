const std = @import("std");

pub fn main() void {
    std.debug.print("Hello!\n", .{});
}

test {
    _ = @import("runtime/crc.zig");
    _ = @import("runtime/events.zig");
    _ = @import("runtime/tools.zig");
}

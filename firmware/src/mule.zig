const std = @import("std");

pub fn main() void {
    std.debug.print("Hey!", .{});
}

test {
    _ = @import("runtime/events.zig");
    _ = @import("runtime/tools.zig");
}

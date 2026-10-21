const std = @import("std");
const assert = std.debug.assert;

pub fn main() void {
    std.debug.print("Hello!\n", .{});
}

test {
    _ = @import("runtime/events.zig");
    _ = @import("runtime/tools.zig");
    _ = @import("drivers/TMC2209.zig");
}

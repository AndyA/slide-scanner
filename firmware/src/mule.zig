const std = @import("std");
const assert = std.debug.assert;

const A = struct {
    pub fn greet(_: @This()) void {
        std.debug.print("A\n", .{});
    }
};

const B = struct {
    pub fn greet(_: @This()) void {
        std.debug.print("B\n", .{});
    }
};

const V = union(enum) { a: A, b: B };

fn greet(v: V) void {
    switch (v) {
        inline else => |x| x.greet(),
    }
}

pub fn main() void {
    greet(.{ .a = .{} });
    greet(.{ .b = .{} });
    std.debug.print("Hello!\n", .{});
}

test {
    _ = @import("runtime/events.zig");
    _ = @import("runtime/tools.zig");
    _ = @import("drivers/TMC2209.zig");
}

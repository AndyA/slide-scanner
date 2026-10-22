const std = @import("std");
const assert = std.debug.assert;

pub fn Promise(comptime T: type, comptime max_listeners: usize) type {
    return struct {
        const Self = @This();
        pub const Type = T;

        pub const Value = union(enum) {
            resolved: T,
            rejected: anyerror,
        };

        pub const Listener = fn (ctx: *anyopaque, value: Value) void;
        const Slot = struct {
            cb: *const Listener,
            ctx: *anyopaque,
        };

        value: ?Value = null,
        listeners: [max_listeners]Slot = undefined,
        used: u32 = 0,

        fn despatch(self: Self) void {
            if (self.value) |value| {
                for (self.listeners[0..self.used]) |listener| {
                    listener.cb(listener.ctx, value);
                }
                return;
            }
            unreachable;
        }

        pub fn then(self: *Self, cb: *const Listener, ctx: *anyopaque) void {
            if (self.value) |value| {
                cb(ctx, value);
            } else {
                assert(self.used < max_listeners);
                self.listeners[self.used] = .{ .cb = cb, .ctx = ctx };
                self.used += 1;
            }
        }

        pub fn resolve(self: *Self, value: T) void {
            assert(self.value == null);
            self.value = .{ .resolved = value };
            self.despatch();
        }

        pub fn reject(self: *Self, err: anyerror) void {
            assert(self.value == null);
            self.value = .{ .rejected = err };
            self.despatch();
        }
    };
}

test Promise {
    const BoolPromise = Promise(bool, 5);
    const Listener = struct {
        value: ?bool = null,
        fn resolved(ctx: *anyopaque, value: BoolPromise.Value) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            switch (value) {
                .resolved => |v| self.value = v,
                else => {
                    std.debug.print("Got: {s}\n", .{@tagName(value)});
                },
            }
        }
    };
    var p: BoolPromise = .{};
    var l1: Listener = .{};
    var l2: Listener = .{};
    p.then(Listener.resolved, &l1);
    try std.testing.expectEqual(null, l1.value);
    try std.testing.expectEqual(null, l2.value);

    p.resolve(true);

    try std.testing.expectEqual(true, l1.value);
    try std.testing.expectEqual(null, l2.value);

    p.then(Listener.resolved, &l2);

    try std.testing.expectEqual(true, l1.value);
    try std.testing.expectEqual(true, l2.value);
}

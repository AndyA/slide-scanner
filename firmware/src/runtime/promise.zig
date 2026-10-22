const std = @import("std");
const assert = std.debug.assert;

pub fn Promise(comptime T: type, comptime max_listeners: usize) type {
    return struct {
        const Self = @This();
        pub const Type = T;

        pub const Value = union(enum) {
            pending: void,
            resolved: T,
            rejected: error{},
        };

        pub const Listener = *fn (ctx: *anyopaque, value: Value) void;
        const Slot = struct {
            cb: Listener,
            ctx: *anyopaque,
        };

        value: Value = .{ .pending = {} },
        listeners: [max_listeners]Slot = undefined,
        used: u32 = 0,

        fn despatch(self: Self) void {
            for (self.listeners) |l| {
                l.cb(l.ctx, self.value);
            }
        }

        pub fn then(self: *Self, cb: Listener, ctx: *anyopaque) void {
            switch (self.value) {
                .pending => {
                    assert(self.used < max_listeners);
                    self.listeners[self.used] = .{ .cb = cb, .ctx = ctx };
                    self.used += 1;
                },
                else => cb(ctx, self.value),
            }
        }

        pub fn resolve(self: *Self, value: T) void {
            assert(self.value == .pending);
            self.value = .{ .resolved = value };
            self.despatch();
        }

        pub fn reject(self: *Self, err: error{}) void {
            assert(self.value == .pending);
            self.value = .{ .rejected = err };
            self.despatch();
        }
    };
}

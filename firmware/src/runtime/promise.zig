const std = @import("std");
const assert = std.debug.assert;

const Later = @import("Later.zig");

pub fn Promise(comptime T: type, comptime then_size: u8) type {
    return struct {
        const Self = @This();
        pub const Type = T;
        pub const Size = then_size;
        pub const Value = union(enum) {
            pending: void,
            resolved: T,
            rejected: anyerror,
        };

        pub const Then = *const fn (ctx: *anyopaque, value: Value) void;
        const ThenSlot = struct { then_fn: Then, ctx: *anyopaque };

        value: Value = .{ .pending = {} },
        thens: [Size]ThenSlot = undefined,
        used: u8 = 0,
        later: Later = .empty,

        pub fn then(self: *Self, then_fn: Then, ctx: *anyopaque) void {
            assert(self.used < Size);
            self.thens[self.used] = .{ .then_fn = then_fn, .ctx = ctx };
            self.used += 1;

            switch (self.value) {
                .pending => {},
                else => self.later.ensure(shim, self),
            }
        }

        fn shim(ctx: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.notify();
        }

        fn notify(self: *Self) void {
            assert(self.value != .pending);
            for (self.thens[0..self.used]) |t| {
                t.then_fn(t.ctx, self.value);
            }
            self.used = 0;
        }

        pub fn resolve(self: *Self, result: T) void {
            assert(self.value == .pending);
            self.value = .{ .resolved = result };
            self.notify();
        }

        pub fn reject(self: *Self, err: anyerror) void {
            assert(self.value == .pending);
            self.value = .{ .rejected = err };
            self.notify();
        }
    };
}

test Promise {
    const P = Promise(u32, 5);
    const Listener = struct {
        value: P.Value = .{ .pending = {} },
        fn then_fn(ctx: *anyopaque, value: P.Value) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.value = value;
        }
    };

    var p1: P = .{};
    var l1: Listener = .{};
    p1.then(Listener.then_fn, &l1);
    p1.resolve(0x12345678);
    try std.testing.expectEqual(0x12345678, l1.value.resolved);
    var l2: Listener = .{};
    p1.then(Listener.then_fn, &l2);
    Later.run();
    try std.testing.expectEqual(0x12345678, l2.value.resolved);
}

fn AllPromise(promises: anytype) type {
    const info = @typeInfo(@TypeOf(promises));
    if (info != .@"struct" or !info.@"struct".is_tuple)
        @compileError("expected tuple argument, found " ++ @typeName((@TypeOf(promises))));
    const field_types = info.@"struct".field_types;

    const result_types = blk: {
        var types: [field_types.len]type = undefined;
        for (field_types, &types) |t, *rt| {
            rt.* = @field(t, "Type");
        }
        break :blk types;
    };

    const then_size = blk: {
        var size: u8 = 0;
        for (field_types) |t| {
            size = @max(size, @field(t, "Size"));
        }
        break :blk size;
    };

    return Promise(@Tuple(result_types), then_size);
}

pub fn all(promises: anytype) AllPromise(promises) {
    const P = AllPromise(promises);
    _ = P;
}

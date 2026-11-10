const std = @import("std");
const assert = std.debug.assert;

const Later = @import("Later.zig");

pub fn Promise(comptime T: type, comptime then_size: u8) type {
    return struct {
        const Self = @This();
        pub const Type = T;
        pub const Value = union(enum) {
            pending: void,
            resolved: T,
            rejected: anyerror,
        };

        pub const Then = *const fn (ctx: *anyopaque, value: Value) void;
        const ThenSlot = struct { then_fn: Then, ctx: *anyopaque };

        value: Value = .{ .pending = {} },
        thens: [then_size]ThenSlot = undefined,
        used: u8 = 0,
        later: Later = .empty,

        pub fn then(self: *Self, then_fn: Then, ctx: *anyopaque) void {
            assert(self.used < then_size);
            self.thens[self.used] = .{ .then_fn = then_fn, .ctx = ctx };
            self.used += 1;

            if (self.value != .pending)
                self.schedule();
        }

        fn schedule(self: *Self) void {
            self.later.ensure(laterFn, self);
        }

        fn laterFn(ctx: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.notify();
        }

        fn notify(self: *Self) void {
            // std.debug.print("notify! {d}\n", .{self.used});
            assert(self.value != .pending);
            for (self.thens[0..self.used]) |t| {
                t.then_fn(t.ctx, self.value);
            }
            self.used = 0;
        }

        pub fn resolve(self: *Self, result: T) void {
            assert(self.value == .pending);
            self.value = .{ .resolved = result };
            self.schedule();
        }

        pub fn reject(self: *Self, err: anyerror) void {
            assert(self.value == .pending);
            self.value = .{ .rejected = err };
            self.schedule();
        }

        pub fn reset(self: *Self) void {
            self.later.cancel();
            self.value = .{ .pending = {} };
            self.used = 0;
        }
    };
}

fn TestListener(V: type) type {
    return struct {
        value: V = .{ .pending = {} },
        count: usize = 0,
        fn thenFn(ctx: *anyopaque, value: V) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.value = value;
            self.count += 1;
        }
    };
}

test Promise {
    const P = Promise(u32, 5);
    const L = TestListener(P.Value);

    var p1: P = .{};
    var l1: L = .{};
    p1.then(L.thenFn, &l1);
    p1.resolve(0x12345678);
    try std.testing.expectEqual(0, l1.count);
    Later.run();
    try std.testing.expectEqual(1, l1.count);
    try std.testing.expectEqual(0x12345678, l1.value.resolved);

    var l2: L = .{};
    p1.then(L.thenFn, &l2);
    try std.testing.expectEqual(0, l2.count);
    Later.run();
    try std.testing.expectEqual(1, l1.count);
    try std.testing.expectEqual(1, l2.count);
    try std.testing.expectEqual(0x12345678, l2.value.resolved);
}

fn AllPromise(comptime PromiseTypes: []const type, comptime then_size: u8) type {
    const n_promises = PromiseTypes.len;

    const Type: type = blk: {
        var rt: [n_promises]type = undefined;
        for (PromiseTypes, &rt) |pt, *t|
            t.* = @field(pt, "Type");
        break :blk @Tuple(&rt);
    };

    const PromiseType = Promise(Type, then_size);

    const Refs: type = blk: {
        var pp: [n_promises]type = undefined;
        for (PromiseTypes, &pp) |pt, *t|
            t.* = @Pointer(.one, .{}, pt, null);
        break :blk @Tuple(&pp);
    };

    return struct {
        const Self = @This();

        promise: PromiseType = .{},
        value: Type = undefined,
        outstanding: u8 = 0,

        pub fn reset(self: *Self) void {
            self.promise.reset();
            self.outstanding = 0;
        }

        pub fn all(self: *Self, promises: Refs) *PromiseType {
            self.outstanding = n_promises;
            inline for (promises, PromiseTypes, 0..) |p, t, i| {
                const shim = struct {
                    fn thenFn(ctx: *anyopaque, value: t.Value) void {
                        const me: *Self = @ptrCast(@alignCast(ctx));
                        switch (value) {
                            .resolved => |v| {
                                if (me.promise.value == .rejected)
                                    return;
                                me.value[i] = v;
                                assert(me.outstanding != 0);
                                me.outstanding -= 1;
                                if (me.outstanding == 0)
                                    me.promise.resolve(me.value);
                            },
                            .rejected => |e| {
                                me.promise.reject(e);
                            },
                            else => unreachable,
                        }
                    }
                };
                p.then(shim.thenFn, self);
            }
            return &self.promise;
        }
    };
}

test AllPromise {
    const Pbool = Promise(bool, 3);
    const Pu32 = Promise(u32, 5);
    const AllP = AllPromise(&.{ Pbool, Pu32 }, 4);

    var p_bool: Pbool = .{};
    var p_u32: Pu32 = .{};
    var p_all: AllP = .{};

    _ = p_all.all(.{ &p_bool, &p_u32 });
}

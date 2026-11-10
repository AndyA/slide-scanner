const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;

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
        notfying: bool = false,

        pub fn then(self: *Self, then_fn: Then, ctx: *anyopaque) void {
            assert(!self.notfying);
            assert(self.used < then_size);
            self.thens[self.used] = .{ .then_fn = then_fn, .ctx = ctx };
            self.used += 1;

            if (self.value != .pending)
                self.schedule();
        }

        fn schedule(self: *Self) void {
            if (self.used != 0)
                self.later.ensure(laterFn, self);
        }

        fn laterFn(ctx: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.notify();
        }

        fn notify(self: *Self) void {
            assert(!self.notfying);
            self.notfying = true;
            defer self.notfying = false;
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
            assert(!self.notfying);
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
    Later.drain();
    try std.testing.expectEqual(1, l1.count);
    try std.testing.expectEqual(0x12345678, l1.value.resolved);

    var l2: L = .{};
    p1.then(L.thenFn, &l2);
    try std.testing.expectEqual(0, l2.count);
    Later.drain();
    try std.testing.expectEqual(1, l1.count);
    try std.testing.expectEqual(1, l2.count);
    try std.testing.expectEqual(0x12345678, l2.value.resolved);
}

fn AllPromise(comptime PromiseTypes: []const type, comptime then_size: u8) type {
    const n_promises = PromiseTypes.len;

    const T: type = blk: {
        var rt: [n_promises]type = undefined;
        for (PromiseTypes, &rt) |pt, *t|
            t.* = @field(pt, "Type");
        break :blk @Tuple(&rt);
    };

    const PromiseType = Promise(T, then_size);

    const Refs: type = blk: {
        var pp: [n_promises]type = undefined;
        for (PromiseTypes, &pp) |pt, *t|
            t.* = @Pointer(.one, .{}, pt, null);
        break :blk @Tuple(&pp);
    };

    return struct {
        const Self = @This();
        pub const Value = PromiseType.Value;
        pub const Type = PromiseType.Type;

        promise: PromiseType = .{},
        value: T = undefined,
        outstanding: u8 = 0,

        pub fn reset(self: *Self) void {
            self.promise.reset();
            self.outstanding = 0;
        }

        fn maybeResolve(self: *Self) void {
            assert(self.outstanding != 0);
            self.outstanding -= 1;
            if (self.outstanding == 0) {
                self.promise.resolve(self.value);
            }
        }

        pub fn all(self: *Self, promises: Refs) *PromiseType {
            assert(promises.len == n_promises);
            self.outstanding = promises.len;
            inline for (promises, PromiseTypes, 0..) |p, t, i| {
                const shim = struct {
                    fn thenFn(ctx: *anyopaque, value: t.Value) void {
                        const me: *Self = @ptrCast(@alignCast(ctx));
                        switch (value) {
                            .resolved => |v| {
                                if (me.promise.value == .rejected)
                                    return;
                                me.value[i] = v;
                                me.maybeResolve();
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
    const Pall = AllPromise(&.{ Pbool, Pu32 }, 4);

    const Lbool = TestListener(Pbool.Value);
    const Lu32 = TestListener(Pu32.Value);
    const Lall = TestListener(Pall.Value);

    var p_bool: Pbool = .{};
    var l_bool: Lbool = .{};
    var p_u32: Pu32 = .{};
    var l_u32: Lu32 = .{};
    var p_all: Pall = .{};
    var l_all: Lall = .{};

    var p_all_p = p_all.all(.{ &p_bool, &p_u32 });
    p_bool.then(Lbool.thenFn, &l_bool);
    p_u32.then(Lu32.thenFn, &l_u32);
    p_all_p.then(Lall.thenFn, &l_all);

    p_u32.resolve(0x12345678);
    Later.drain();
    try std.testing.expectEqual(0, l_bool.count);
    try std.testing.expectEqual(1, l_u32.count);
    try std.testing.expectEqual(0, l_all.count);
    try std.testing.expectEqual(0x12345678, l_u32.value.resolved);

    p_bool.resolve(true);
    Later.drain();
    try std.testing.expectEqual(1, l_bool.count);
    try std.testing.expectEqual(1, l_u32.count);
    try std.testing.expectEqual(1, l_all.count);
    try std.testing.expectEqual(true, l_bool.value.resolved);
    try std.testing.expectEqual(0x12345678, l_u32.value.resolved);
    try std.testing.expectEqual(.{ true, 0x12345678 }, l_all.value.resolved);
}
